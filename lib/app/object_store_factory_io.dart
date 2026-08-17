import 'dart:io';

import 'package:dartloom_storage/dartloom_storage.dart';
import 'package:dartloom_storage_file/dartloom_storage_file.dart';
import 'package:path_provider/path_provider.dart';

Future<ObjectStore> openActentObjectStore() async {
  final root = await getApplicationSupportDirectory();
  return FileObjectStore.open(
    root: Directory('${root.path}${Platform.pathSeparator}actent'),
  );
}
