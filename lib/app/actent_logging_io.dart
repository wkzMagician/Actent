import 'dart:io';

import 'package:dartloom_logging/dartloom_logging.dart';
import 'package:dartloom_logging_logger/dartloom_logging_logger.dart';
import 'package:logger/logger.dart';
import 'package:path_provider/path_provider.dart';

class ActentLogService {
  ActentLogService(this.logger, this.directory, this._rawLogger);

  final AppLogger logger;
  final String directory;
  final Logger _rawLogger;

  Future<void> close() => _rawLogger.close();
}

AppLogger currentAppLogger = LoggerAppLogger();

Future<ActentLogService> openActentLogService() async {
  final support = await getApplicationSupportDirectory();
  final directory = Directory(
    '${support.path}${Platform.pathSeparator}actent${Platform.pathSeparator}logs',
  );
  await directory.create(recursive: true);
  await _deleteExpiredLogs(directory);
  final rawLogger = Logger(
    filter: ProductionFilter(),
    printer: SimplePrinter(printTime: true, colors: false),
    output: AdvancedFileOutput(
      path: directory.path,
      maxFileSizeKB: 1024,
      maxRotatedFilesCount: 4,
      maxDelay: const Duration(seconds: 2),
    ),
  );
  currentAppLogger = LoggerAppLogger(logger: rawLogger);
  return ActentLogService(currentAppLogger, directory.path, rawLogger);
}

Future<void> _deleteExpiredLogs(Directory directory) async {
  final cutoff = DateTime.now().subtract(const Duration(days: 7));
  await for (final entity in directory.list()) {
    if (entity is! File) continue;
    if ((await entity.lastModified()).isBefore(cutoff)) {
      await entity.delete();
    }
  }
}
