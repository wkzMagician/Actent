import 'dart:async';

import 'package:dartloom_external_input/dartloom_external_input.dart';

/// Presents multiple platform acquisition mechanisms as one input stream.
///
/// Each source keeps ownership of its own lifecycle and pending queue. The
/// application consumes the resulting batches through one business path.
final class CombinedExternalInputService implements ExternalInputService {
  CombinedExternalInputService(Iterable<ExternalInputService> services)
    : _services = List.unmodifiable(services);

  final List<ExternalInputService> _services;
  Stream<ExternalInputBatch>? _inputs;

  @override
  Stream<ExternalInputBatch> get inputs =>
      _inputs ??= Stream.multi((controller) {
        final subscriptions = [
          for (final service in _services)
            service.inputs.listen(
              controller.add,
              onError: controller.addError,
              onDone: () {},
            ),
        ];
        controller.onCancel = () {
          for (final subscription in subscriptions) {
            unawaited(subscription.cancel());
          }
        };
      }, isBroadcast: true);

  @override
  Future<List<ExternalInputBatch>> takePending() async => [
    for (final service in _services) ...await service.takePending(),
  ];
}
