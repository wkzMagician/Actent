import 'dart:async';

import 'package:actent/app/app.dart';
import 'package:actent/features/actent_core/actent_repository.dart';
import 'package:actent/features/actent_core/actent_store.dart';
import 'package:actent/features/incoming/incoming_content_service.dart';
import 'package:actent/features/work/work_runner.dart';
import 'package:dartloom_external_input/dartloom_external_input.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows Actent app shell', (tester) async {
    await tester.pumpWidget(const DartloomApp());
    await tester.pumpAndSettle();

    expect(find.text('Activity'), findsNWidgets(2));
    expect(
      find.text('Inputs and Work execution history will appear here.'),
      findsOneWidget,
    );
  });

  testWidgets('does not create an activity when external input is discarded', (
    tester,
  ) async {
    final repository = ActentRepository(MemoryActentJsonStore());
    final queue = WorkQueueCoordinator(repository: repository);
    final external = _TestExternalInputService();
    addTearDown(external.dispose);

    await tester.pumpWidget(
      DartloomApp(
        repository: repository,
        queue: queue,
        externalInputService: external,
        incomingContentService: IncomingContentService(
          deviceId: 'test-device',
          importFiles: (_) async => null,
        ),
      ),
    );
    await tester.pumpAndSettle();

    external.add(
      const ExternalInputBatch(
        source: ExternalInputSource.share,
        items: [ExternalText('discard me')],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Choose Work or Workflow'), findsOneWidget);
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();

    expect(await repository.listMessages(), isEmpty);
    expect(find.text('Sending'), findsNothing);
  });
}

final class _TestExternalInputService implements ExternalInputService {
  final StreamController<ExternalInputBatch> _controller =
      StreamController<ExternalInputBatch>.broadcast();

  @override
  Stream<ExternalInputBatch> get inputs => _controller.stream;

  void add(ExternalInputBatch batch) => _controller.add(batch);

  @override
  Future<List<ExternalInputBatch>> takePending() async => const [];

  Future<void> dispose() => _controller.close();
}
