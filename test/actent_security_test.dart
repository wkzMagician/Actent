import 'package:flutter_test/flutter_test.dart';
import 'package:actent/features/actent_core/actent_models.dart';
import 'package:actent/features/actent_core/actent_repository.dart';
import 'package:actent/features/actent_core/actent_router.dart';
import 'package:actent/features/actent_core/actent_store.dart';
import 'package:actent/features/actent_core/work_catalog.dart';
import 'package:actent/features/work/work_runner.dart';

void main() {
  test(
    'rejects a receipt from a device that did not execute the request',
    () async {
      final repository = ActentRepository(MemoryActentJsonStore());
      final request = WorkRequest(
        requestId: 'request-1',
        message: ActentMessage(
          id: 'message-1',
          traceId: 'trace-1',
          createdAt: DateTime.now().toUtc(),
          source: const ActentSource(kind: 'test', deviceId: 'local'),
          content: ActentContent(type: ActentContentType.text),
        ),
        workId: 'work-1',
        workRevision: 1,
        sourceDeviceId: 'local',
        targetDeviceId: 'remote',
        createdAt: DateTime.now().toUtc(),
        expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 1)),
      );
      await repository.saveRequest(request);
      final receipt = WorkReceipt(
        requestId: 'request-1',
        workId: 'work-1',
        status: WorkReceiptStatus.succeeded,
        createdAt: DateTime.now().toUtc(),
      );
      final router = ActentRouter(
        deviceId: 'local',
        repository: repository,
        connection: FakeMessageConnection(),
        queue: WorkQueueCoordinator(repository: repository),
      );

      expect(
        () => router.receive({
          'type': 'workReceipt',
          'schemaVersion': actentSchemaVersion,
          'receipt': receipt.toJson(),
        }, authenticatedSenderId: 'unexpected-device'),
        throwsA(isA<ActentValidationException>()),
      );
    },
  );

  test(
    'rejects catalog entries whose owner is not the authenticated peer',
    () async {
      final repository = ActentRepository(MemoryActentJsonStore());
      final router = ActentRouter(
        deviceId: 'local',
        repository: repository,
        connection: FakeMessageConnection(),
        queue: WorkQueueCoordinator(repository: repository),
      );
      final work = Work.nullWork(id: 'forged', ownerDeviceId: 'other');
      expect(
        () => router.receiveCatalogSnapshot({
          'revision': 1,
          'works': [work.toJson()],
        }, ownerDeviceId: 'remote'),
        throwsA(isA<WorkCatalogException>()),
      );
    },
  );
}
