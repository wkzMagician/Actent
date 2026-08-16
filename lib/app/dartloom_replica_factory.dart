import 'dart:io';

import 'package:dartloom_runtime/dartloom_runtime.dart';
import 'package:dartloom_storage/dartloom_storage.dart';
import 'package:dartloom_storage_json_file/dartloom_storage_json_file.dart';
import 'package:path_provider/path_provider.dart';

Future<DartloomBinding<Object>> createJsonReplicaStore(
  DartloomFactoryContext context,
) async {
  final (businessRoot, metadataRoot) = await resolveJsonReplicaDirectories();
  final value = await JsonDirectoryStore.openAt(
    directory: businessRoot,
    metadataDirectory: metadataRoot,
    hierarchical: true,
  );
  return DartloomBinding<ReplicaStore>(value, dispose: value.close);
}

Future<(Directory, Directory)> resolveJsonReplicaDirectories() async {
  final applicationRoot = await getApplicationSupportDirectory();
  final businessRoot = Directory(
    '${applicationRoot.path}${Platform.pathSeparator}pigeon',
  );
  final metadataRoot = Directory(
    '${applicationRoot.path}${Platform.pathSeparator}.pigeon-replica-metadata',
  );
  await businessRoot.create(recursive: true);
  await metadataRoot.create(recursive: true);
  return (businessRoot, metadataRoot);
}

Future<Directory> resolvePigeonAttachmentDirectory() async {
  final (businessRoot, _) = await resolveJsonReplicaDirectories();
  final attachments = Directory(
    '${businessRoot.path}${Platform.pathSeparator}attachments',
  );
  await attachments.create(recursive: true);
  return attachments;
}

final dartloomApplicationFactories = <String, DartloomFactory>{
  'createJsonReplicaStore': createJsonReplicaStore,
};
