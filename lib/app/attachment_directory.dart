import 'dart:io';

import 'package:path_provider/path_provider.dart';

Future<Directory> resolveActentAttachmentDirectory() async {
  final root = await getApplicationSupportDirectory();
  final attachments = Directory(
    '${root.path}${Platform.pathSeparator}actent${Platform.pathSeparator}attachments',
  );
  await attachments.create(recursive: true);
  return attachments;
}
