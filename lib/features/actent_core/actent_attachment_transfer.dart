import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dartloom_storage/dartloom_storage.dart';

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
    final completed = File('${directory.path}${Platform.pathSeparator}payload');
    _completedHandle = await completed.exists() ? completed.path : null;
  }

  @override
  Future<Set<int>> receivedChunkIndexes(AttachmentManifest manifest) async {
    if (_completedHandle != null) {
      return Set<int>.from(
        List<int>.generate(manifest.totalChunks, (index) => index),
      );
    }
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
    if (await target.exists()) {
      _completedHandle = target.path;
      return;
    }
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
    final completed = part == null
        ? null
        : File('${part.parent.path}${Platform.pathSeparator}payload');
    if (completed != null && await completed.exists()) await completed.delete();
    final ranges = part == null
        ? null
        : File('${part.parent.path}${Platform.pathSeparator}ranges.json');
    if (ranges != null && await ranges.exists()) await ranges.delete();
    _completedHandle = null;
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

/// Restart-safe attachment sink for Web/IndexedDB and other ObjectStore-backed
/// application compositions. Each plaintext chunk is local-only and removed
/// after the verified final object is assembled.
class ActentObjectStoreAttachmentSink
    implements AttachmentSink, ActentAttachmentSinkHandle {
  ActentObjectStoreAttachmentSink(this.store);

  final ObjectStore store;
  String? _completedHandle;

  @override
  String? get completedHandle => _completedHandle;

  @override
  Future<void> begin(AttachmentManifest manifest) async {
    final key = _completedKey(manifest);
    _completedHandle = await store.read(key) == null
        ? null
        : 'actent-indexeddb://$key';
  }

  @override
  Future<Set<int>> receivedChunkIndexes(AttachmentManifest manifest) async {
    if (_completedHandle != null) {
      return Set<int>.from(
        List<int>.generate(manifest.totalChunks, (index) => index),
      );
    }
    final prefix = '${_chunkPrefix(manifest)}/';
    final indexes = <int>{};
    for (final item in await store.scan()) {
      if (!item.key.startsWith(prefix)) continue;
      final index = int.tryParse(item.key.substring(prefix.length));
      if (index != null && index >= 0 && index < manifest.totalChunks) {
        indexes.add(index);
      }
    }
    return indexes;
  }

  @override
  Future<void> writeChunk(
    AttachmentManifest manifest,
    int index,
    Uint8List plaintext,
  ) => store.write('${_chunkPrefix(manifest)}/$index', plaintext);

  @override
  Future<Uint8List> readChunk(AttachmentManifest manifest, int index) async {
    final value = await store.read('${_chunkPrefix(manifest)}/$index');
    if (value == null) throw StateError('attachment chunk is unavailable');
    return Uint8List.fromList(value);
  }

  @override
  Future<void> commit(AttachmentManifest manifest) async {
    final key = _completedKey(manifest);
    if (await store.read(key) == null) {
      final bytes = BytesBuilder(copy: false);
      for (var index = 0; index < manifest.totalChunks; index++) {
        bytes.add(await readChunk(manifest, index));
      }
      await store.write(key, bytes.takeBytes());
    }
    await _deleteChunks(manifest);
    _completedHandle = 'actent-indexeddb://$key';
  }

  @override
  Future<void> abort(AttachmentManifest manifest) async {
    await _deleteChunks(manifest);
    await store.delete(_completedKey(manifest));
    _completedHandle = null;
  }

  Future<void> _deleteChunks(AttachmentManifest manifest) async {
    final prefix = '${_chunkPrefix(manifest)}/';
    for (final item in await store.scan()) {
      if (item.key.startsWith(prefix)) await store.delete(item.key);
    }
  }

  String _chunkPrefix(AttachmentManifest manifest) =>
      'attachmentTransfers/v2/${_id(manifest.messageId)}/${_id(manifest.attachmentId)}';

  String _completedKey(AttachmentManifest manifest) =>
      'attachments/v2/${_id(manifest.messageId)}/${_id(manifest.attachmentId)}';
}

String _key(AttachmentManifest manifest) =>
    '${manifest.messageId}\u0000${manifest.attachmentId}';

String _id(String value) =>
    base64Url.encode(utf8.encode(value)).replaceAll('=', '');
