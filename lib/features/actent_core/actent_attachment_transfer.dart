import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import '../messaging/attachment_chunks.dart';

abstract interface class ActentAttachmentSinkHandle {
  String? get completedHandle;
}

class ActentFileAttachmentSource implements AttachmentSource {
  ActentFileAttachmentSource(this.file);

  final File file;

  @override
  int get byteLength => file.lengthSync();

  @override
  Future<Uint8List> read(int offset, int length) async {
    final handle = await file.open();
    try {
      await handle.setPosition(offset);
      return Uint8List.fromList(await handle.read(length));
    } finally {
      await handle.close();
    }
  }
}

class ActentFileAttachmentSink
    implements AttachmentSink, ActentAttachmentSinkHandle {
  ActentFileAttachmentSink(this.root);

  final Directory root;
  final Map<String, File> _parts = {};
  String? _completedHandle;

  @override
  String? get completedHandle => _completedHandle;

  @override
  Future<void> begin(AttachmentManifest manifest) async {
    final directory = Directory(
      '${root.path}${Platform.pathSeparator}${manifest.messageId}${Platform.pathSeparator}${manifest.attachmentId}',
    );
    await directory.create(recursive: true);
    _parts[_key(manifest)] = File(
      '${directory.path}${Platform.pathSeparator}payload.part',
    );
    _completedHandle = null;
  }

  @override
  Future<Set<int>> receivedChunkIndexes(AttachmentManifest manifest) async {
    final ranges = await _rangesFile(manifest);
    if (!await ranges.exists()) return <int>{};
    final value = jsonDecode(await ranges.readAsString());
    if (value is! List) return <int>{};
    return value.whereType<int>().toSet();
  }

  @override
  Future<void> writeChunk(
    AttachmentManifest manifest,
    int index,
    Uint8List plaintext,
  ) async {
    final file = _parts[_key(manifest)];
    if (file == null) throw StateError('attachment sink was not started');
    final handle = await file.open(mode: FileMode.writeOnly);
    try {
      await handle.setPosition(index * manifest.chunkSize);
      await handle.writeFrom(plaintext);
    } finally {
      await handle.close();
    }
    final indexes = await receivedChunkIndexes(manifest)
      ..add(index);
    await (await _rangesFile(manifest))
        .writeAsString(jsonEncode(indexes.toList()));
  }

  @override
  Future<Uint8List> readChunk(AttachmentManifest manifest, int index) async {
    final file = _parts[_key(manifest)];
    if (file == null) throw StateError('attachment sink was not started');
    final offset = index * manifest.chunkSize;
    final length = math.min(manifest.chunkSize, manifest.byteLength - offset);
    final handle = await file.open();
    try {
      await handle.setPosition(offset);
      return Uint8List.fromList(await handle.read(length));
    } finally {
      await handle.close();
    }
  }

  @override
  Future<void> commit(AttachmentManifest manifest) async {
    final part = _parts[_key(manifest)];
    if (part == null) throw StateError('attachment sink was not started');
    final target = File('${part.parent.path}${Platform.pathSeparator}payload');
    if (await target.exists()) await target.delete();
    await part.rename(target.path);
    final ranges = await _rangesFile(manifest);
    if (await ranges.exists()) await ranges.delete();
    _completedHandle = target.path;
  }

  @override
  Future<void> abort(AttachmentManifest manifest) async {
    final part = _parts.remove(_key(manifest));
    if (part != null && await part.exists()) await part.delete();
    final ranges = await _rangesFile(manifest);
    if (await ranges.exists()) await ranges.delete();
  }

  Future<File> _rangesFile(AttachmentManifest manifest) async {
    final part = _parts[_key(manifest)];
    if (part == null) throw StateError('attachment sink was not started');
    return File('${part.parent.path}${Platform.pathSeparator}ranges.json');
  }
}

class ActentCallbackAttachmentSink
    implements AttachmentSink, ActentAttachmentSinkHandle {
  ActentCallbackAttachmentSink(this.writeAttachment);

  final Future<String> Function(
    String messageId,
    String attachmentId,
    Uint8List bytes,
  )
  writeAttachment;
  final MemoryAttachmentSink _memory = MemoryAttachmentSink();
  String? _completedHandle;

  @override
  String? get completedHandle => _completedHandle;

  @override
  Future<void> begin(AttachmentManifest manifest) async {
    await _memory.begin(manifest);
    _completedHandle = null;
  }

  @override
  Future<Set<int>> receivedChunkIndexes(AttachmentManifest manifest) =>
      _memory.receivedChunkIndexes(manifest);

  @override
  Future<void> writeChunk(
    AttachmentManifest manifest,
    int index,
    Uint8List plaintext,
  ) => _memory.writeChunk(manifest, index, plaintext);

  @override
  Future<Uint8List> readChunk(AttachmentManifest manifest, int index) =>
      _memory.readChunk(manifest, index);

  @override
  Future<void> commit(AttachmentManifest manifest) async {
    final bytes = <int>[];
    for (var index = 0; index < manifest.totalChunks; index++) {
      bytes.addAll(await _memory.readChunk(manifest, index));
    }
    _completedHandle = await writeAttachment(
      manifest.messageId,
      manifest.attachmentId,
      Uint8List.fromList(bytes),
    );
  }

  @override
  Future<void> abort(AttachmentManifest manifest) => _memory.abort(manifest);
}

String _key(AttachmentManifest manifest) =>
    '${manifest.messageId}\u0000${manifest.attachmentId}';
