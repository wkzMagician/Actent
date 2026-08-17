import '../actent_core/actent_models.dart';
import 'work_runner.dart';

class WebJsWorkConfig {
  const WebJsWorkConfig({required this.source, this.allowedHosts = const []});

  final String source;
  final List<String> allowedHosts;
}

class WebJsWorkRunner implements WorkRunner {
  const WebJsWorkRunner(this.config);

  final WebJsWorkConfig config;

  @override
  String get id => 'web-js';

  @override
  Future<WorkRunResult> run(
    Work work,
    ActentMessage message, {
    required String requestId,
    required CancellationToken cancellation,
  }) async => const WorkRunResult.failure(errorCode: 'web_only_work');
}
