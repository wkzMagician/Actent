import 'package:dartloom_storage/dartloom_storage.dart';
import 'package:dartloom_storage_indexeddb/dartloom_storage_indexeddb.dart';

Future<ObjectStore> openActentObjectStore() async =>
    IndexedDbObjectStore(namespace: 'actent');
