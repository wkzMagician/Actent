import 'dart:typed_data';

import 'package:dartloom_storage/dartloom_storage.dart';
import 'package:file_selector/file_selector.dart';

import '../actent_core/actent_models.dart';

Future<ActentMessage?> pickLocalWorkInputFile({
  Object? attachmentStore,
  String attachmentDirectory = '',
  required String deviceId,
}) async {
  final store = attachmentStore;
  if (store is! ObjectStore) return null;
  final files = await openFiles();
  if (files.isEmpty) return null;
  final now = DateTime.now().toUtc();
  final identity = now.microsecondsSinceEpoch.toRadixString(36);
  final messageId = 'file-$identity';
  final attachments = <ActentAttachment>[];
  for (var index = 0; index < files.length; index++) {
    final file = files[index];
    final bytes = await file.readAsBytes();
    final id = 'attachment-$identity-$index';
    final key = 'attachments/$messageId/$id';
    await store.write(key, Uint8List.fromList(bytes));
    attachments.add(
      ActentAttachment(
        id: id,
        name: file.name,
        mimeType: file.mimeType ?? 'application/octet-stream',
        byteLength: bytes.length,
        handle: 'actent-indexeddb://$key',
      ),
    );
  }
  return ActentMessage(
    id: messageId,
    traceId: messageId,
    createdAt: now,
    source: ActentSource(
      kind: 'file-picker',
      deviceId: deviceId,
      appName: 'Actent',
      platform: 'web',
    ),
    content: ActentContent(
      type: classifyAttachmentContentTypes(
        attachments.map((attachment) => attachment.mimeType),
      ),
      data: {
        'name': files.length == 1 ? files.single.name : '${files.length} files',
      },
    ),
    attachments: attachments,
  );
}

Future<ActentMessage?> importLocalWorkInputFiles({
  required List<String> paths,
  required String attachmentDirectory,
  required String deviceId,
}) async => null;
