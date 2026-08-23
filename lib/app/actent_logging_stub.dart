import 'package:dartloom_logging/dartloom_logging.dart';
import 'package:dartloom_logging_logger/dartloom_logging_logger.dart';

class ActentLogService {
  ActentLogService(this.logger, {this.directory});

  final AppLogger logger;
  final String? directory;

  Future<void> close() async {}
}

final AppLogger currentAppLogger = LoggerAppLogger();

Future<ActentLogService> openActentLogService() async =>
    ActentLogService(currentAppLogger);
