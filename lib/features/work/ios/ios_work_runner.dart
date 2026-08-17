import '../../actent_core/actent_models.dart';
import '../work_runner.dart';

/// iOS is intentionally not registered in the first release. This shared
/// contract keeps future Intent/HTTP implementations from changing Core.
abstract interface class IOSWorkRunner implements WorkRunner {}

class IOSRunnerPlaceholder implements IOSWorkRunner {
  const IOSRunnerPlaceholder();

  @override
  String get id => 'ios-placeholder';

  @override
  Future<WorkRunResult> run(
    Work work,
    ActentMessage message, {
    required String requestId,
    required CancellationToken cancellation,
  }) async => const WorkRunResult.failure(errorCode: 'ios_not_registered');
}
