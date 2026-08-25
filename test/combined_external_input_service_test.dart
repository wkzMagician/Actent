import 'dart:async';

import 'package:actent/app/combined_external_input_service.dart';
import 'package:dartloom_external_input/dartloom_external_input.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'combines live batches and pending batches from every input source',
    () async {
      final first = _TestExternalInputService();
      final second = _TestExternalInputService();
      final combined = CombinedExternalInputService([first, second]);
      final received = <ExternalInputBatch>[];
      final subscription = combined.inputs.listen(received.add);
      addTearDown(subscription.cancel);

      final live = ExternalInputBatch(
        source: ExternalInputSource.deepLink,
        items: [ExternalUrl(Uri.parse('https://example.com'))],
      );
      first.add(live);
      await Future<void>.delayed(Duration.zero);

      final pending = ExternalInputBatch(
        source: ExternalInputSource.share,
        items: [const ExternalText('Saved by the Share Extension')],
      );
      second.pending.add(pending);

      expect(received, [live]);
      expect(await combined.takePending(), [pending]);
    },
  );
}

final class _TestExternalInputService implements ExternalInputService {
  final controller = StreamController<ExternalInputBatch>.broadcast();
  final pending = <ExternalInputBatch>[];

  @override
  Stream<ExternalInputBatch> get inputs => controller.stream;

  void add(ExternalInputBatch batch) => controller.add(batch);

  @override
  Future<List<ExternalInputBatch>> takePending() async {
    final result = List<ExternalInputBatch>.from(pending);
    pending.clear();
    return result;
  }
}
