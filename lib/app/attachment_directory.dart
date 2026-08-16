import 'dart:io';

import 'package:path_provider/path_provider.dart';

Future<Directory> resolvePigeonAttachmentDirectory() async {
  final root = await getApplicationSupportDirectory();
  final attachments = Directory(
    '${root.path}${Platform.pathSeparator}pigeon${Platform.pathSeparator}attachments',
  );
  await attachments.create(recursive: true);
  return attachments;
}
