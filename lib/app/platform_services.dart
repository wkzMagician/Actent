import 'package:dartloom_resident/dartloom_resident.dart';
import 'package:dartloom_singleton/dartloom_singleton.dart';

import 'platform_services_io.dart'
    if (dart.library.js_interop) 'platform_services_web.dart'
    as platform;

Future<ResidentService?> createResidentService() =>
    platform.createResidentService();

SingleInstanceService? createSingleInstanceService() =>
    platform.createSingleInstanceService();
