import 'package:dartloom_logging/dartloom_logging.dart';

import 'actent_logging_stub.dart'
    if (dart.library.io) 'actent_logging_io.dart'
    show ActentLogService;
import 'actent_logging_stub.dart'
    if (dart.library.io) 'actent_logging_io.dart'
    as implementation;

export 'actent_logging_stub.dart'
    if (dart.library.io) 'actent_logging_io.dart'
    show ActentLogService;

Future<ActentLogService> openActentLogService() =>
    implementation.openActentLogService();

/// Keeps application code dependent on the Dartloom logging contract.
AppLogger get appLogger => implementation.currentAppLogger;
