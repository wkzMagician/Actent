import 'dart:io';

import 'package:file_selector/file_selector.dart';

import '../actent_core/actent_models.dart';

Future<ActentMessage?> pickLocalWorkInputFile({
  Object? attachmentStore,
  String attachmentDirectory = '',
  required String deviceId,
}) async {
  final files = await openFiles();
  return _importFiles(
    files,
    attachmentDirectory: attachmentDirectory,
    deviceId: deviceId,
  );
}

Future<ActentMessage?> importLocalWorkInputFiles({
  required List<String> paths,
  required String attachmentDirectory,
  required String deviceId,
}) async {
  final files = paths
      .where((path) => path.isNotEmpty && File(path).existsSync())
      .map(XFile.new)
      .toList(growable: false);
  return _importFiles(
    files,
    attachmentDirectory: attachmentDirectory,
    deviceId: deviceId,
  );
}

Future<ActentMessage?> _importFiles(
  List<XFile> files, {
  required String attachmentDirectory,
  required String deviceId,
}) async {
  if (files.isEmpty) return null;

  final timestamp = DateTime.now().toUtc();
  final identity = timestamp.microsecondsSinceEpoch.toRadixString(36);
  final messageId = 'file-$identity';
  if (files.length == 1 &&
      (files.single.name.endsWith('.actent-text') ||
          files.single.name.endsWith('.actent-url'))) {
    final value = (await File(files.single.path).readAsString()).trim();
    if (value.isEmpty) return null;
    final isUrl = files.single.name.endsWith('.actent-url');
    return ActentMessage(
      id: messageId,
      traceId: messageId,
      createdAt: timestamp,
      source: ActentSource(
        kind: 'share',
        deviceId: deviceId,
        appName: 'iOS Share Extension',
        platform: Platform.operatingSystem,
      ),
      content: ActentContent(
        type: isUrl ? ActentContentType.url : ActentContentType.text,
        data: {isUrl ? 'url' : 'text': value},
      ),
    );
  }
  final attachments = <ActentAttachment>[];
  for (var index = 0; index < files.length; index++) {
    final file = files[index];
    final source = File(file.path);
    final length = await source.length();
    final attachmentId = 'attachment-$identity-$index';
    final destination = File(
      '$attachmentDirectory${Platform.pathSeparator}$messageId'
      '${Platform.pathSeparator}$attachmentId${Platform.pathSeparator}payload',
    );
    await destination.parent.create(recursive: true);
    await source.copy(destination.path);
    attachments.add(
      ActentAttachment(
        id: attachmentId,
        name: file.name,
        mimeType: file.mimeType ?? 'application/octet-stream',
        byteLength: length,
        handle: destination.path,
      ),
    );
  }
  final contentType = classifyAttachmentContentTypes(
    attachments.map((attachment) => attachment.mimeType),
  );

  return ActentMessage(
    id: messageId,
    traceId: messageId,
    createdAt: timestamp,
    source: ActentSource(
      kind: 'file-picker',
      deviceId: deviceId,
      appName: 'Actent',
      platform: Platform.operatingSystem,
    ),
    content: ActentContent(
      type: contentType,
      data: {
        'name': files.length == 1 ? files.single.name : '${files.length} files',
      },
    ),
    attachments: attachments,
  );
}
