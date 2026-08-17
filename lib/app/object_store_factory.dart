import 'package:dartloom_storage/dartloom_storage.dart';

import 'object_store_factory_io.dart'
    if (dart.library.js_interop) 'object_store_factory_web.dart'
    as platform;

Future<ObjectStore> openActentObjectStore() => platform.openActentObjectStore();
