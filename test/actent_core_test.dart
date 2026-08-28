import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:actent/features/actent_core/attachment_retention.dart';
import 'package:actent/features/actent_core/configuration_transfer.dart';
import 'package:actent/features/actent_core/actent_models.dart';
import 'package:actent/features/actent_core/actent_repository.dart';
import 'package:actent/features/actent_core/actent_router.dart';
import 'package:actent/features/actent_core/actent_store.dart';
import 'package:actent/features/actent_core/work_catalog.dart';
import 'package:actent/features/work/work_runner.dart';

void main() {
  group('Actent schema', () {
    test('classifies a file batch conservatively by MIME type', () {
      expect(
        classifyAttachmentContentTypes(['image/png', 'image/jpeg']),
        ActentContentType.image,
      );
      expect(
        classifyAttachmentContentTypes([
          'application/json',
          'application/vnd.example+json',
        ]),
        ActentContentType.json,
      );
      expect(
        classifyAttachmentContentTypes(['image/png', 'application/pdf']),
        ActentContentType.file,
      );
    });

    test('round trips a versioned message', () {
      final message = ActentMessage(
        id: 'message-1',
        traceId: 'trace-1',
        createdAt: DateTime.utc(2026, 1, 1),
        source: const ActentSource(kind: 'share', deviceId: 'phone'),
        content: ActentContent(
          type: ActentContentType.text,
          data: const {'text': 'hello'},
        ),
        attachments: const [
          ActentAttachment(
            id: 'attachment-1',
            name: 'note.txt',
            mimeType: 'text/plain',
            byteLength: 5,
            handle: 'attachments/attachment-1/note.txt',
          ),
        ],
      );

      final decoded = ActentMessage.fromJson(message.toJson());
      expect(decoded.id, message.id);
      expect(decoded.content.data['text'], 'hello');
      expect(decoded.attachments.single.byteLength, 5);
    });

    test('Null Work accepts every content type without a platform binding', () {
      final work = Work.nullWork(id: 'null', ownerDeviceId: 'desktop');

      expect(
        ActentContentType.values.every(
          (type) => work.accepts(
            ActentMessage(
              id: 'message-${type.name}',
              traceId: 'trace-${type.name}',
              createdAt: DateTime.utc(2026),
              source: const ActentSource(kind: 'test'),
              content: ActentContent(type: type),
            ),
          ),
        ),
        isTrue,
      );
    });

    test('rejects an unsupported schema version before accepting content', () {
      expect(
        () => ActentMessage.fromJson(<String, Object?>{
          'id': 'message-1',
          'traceId': 'trace-1',
          'schemaVersion': 2,
        }),
        throwsA(isA<ActentValidationException>()),
      );
    });

    test('rejects unknown envelope and attachment fields', () {
      final message = ActentMessage(
        id: 'message-1',
        traceId: 'trace-1',
        createdAt: DateTime.utc(2026, 1, 1),
        source: const ActentSource(kind: 'share'),
        content: ActentContent(
          type: ActentContentType.text,
          data: const {'text': 'hello'},
        ),
        attachments: const [
          ActentAttachment(
            id: 'attachment-1',
            name: 'note.txt',
            mimeType: 'text/plain',
            byteLength: 5,
            handle: 'attachments/attachment-1/note.txt',
          ),
        ],
      );
      final unknownEnvelope = message.toJson()..['unexpected'] = true;
      expect(
        () => ActentMessage.fromJson(unknownEnvelope),
        throwsA(isA<ActentValidationException>()),
      );

      final unknownAttachment = message.toJson();
      final attachments =
          ((unknownAttachment['payload'] as Map)['attachments'] as List)
              .cast<Object?>();
      attachments[0] = Map<String, Object?>.from(attachments[0] as Map)
        ..['unexpected'] = true;
      expect(
        () => ActentMessage.fromJson(unknownAttachment),
        throwsA(isA<ActentValidationException>()),
      );
    });
  });

  group('Actent repository and routing', () {
    late MemoryActentJsonStore store;
    late ActentRepository repository;
    late Work work;
    late ActentMessage message;

    setUp(() {
      store = MemoryActentJsonStore();
      repository = ActentRepository(store);
      work = Work(
        id: 'work-1',
        revision: 1,
        name: 'Store text',
        ownerDeviceId: 'desktop',
        acceptedContentTypes: const {ActentContentType.text},
      );
      message = ActentMessage(
        id: 'message-1',
        traceId: 'trace-1',
        createdAt: DateTime.utc(2026, 1, 1),
        source: const ActentSource(kind: 'share', deviceId: 'phone'),
        content: ActentContent(type: ActentContentType.text),
      );
    });

    test('persists entities as separate JSON documents', () async {
      await repository.saveMessage(message);
      await repository.saveWork(work);

      expect((await repository.listMessages()).single.id, 'message-1');
      expect((await repository.getWork('work-1'))!.revision, 1);
      expect((await store.list(prefix: 'messages/')), [
        'messages/message-1.json',
      ]);
    });

    test('allows duplicate Work names only across different devices', () async {
      await repository.saveWork(work);

      await expectLater(
        repository.saveWork(
          Work(
            id: 'work-duplicate',
            revision: 1,
            name: '  Store text  ',
            ownerDeviceId: 'desktop',
            acceptedContentTypes: const {ActentContentType.text},
          ),
        ),
        throwsA(isA<StateError>()),
      );

      await repository.saveWork(
        Work(
          id: 'work-phone',
          revision: 1,
          name: 'Store text',
          ownerDeviceId: 'phone',
          acceptedContentTypes: const {ActentContentType.text},
        ),
      );
      expect((await repository.listWorks()).length, 2);
    });

    test('remembers an owned Work deletion across startup repair', () async {
      await repository.saveWork(work);

      await repository.deleteOwnedWork(work.id);

      expect(await repository.getWork(work.id), isNull);
      expect(await repository.wasOwnedWorkDeleted(work.id), isTrue);
    });

    test(
      'deleting a message removes only its unreferenced attachment files',
      () async {
        final root = await Directory.systemTemp.createTemp('actent-retention-');
        try {
          final file = File('${root.path}${Platform.pathSeparator}payload.txt');
          await file.writeAsString('payload');
          final attachmentMessage = ActentMessage(
            id: 'message-with-file',
            traceId: 'trace-file',
            createdAt: DateTime.now().toUtc(),
            source: const ActentSource(kind: 'share'),
            content: ActentContent(type: ActentContentType.file),
            attachments: [
              ActentAttachment(
                id: 'attachment-file',
                name: 'payload.txt',
                mimeType: 'text/plain',
                byteLength: 7,
                handle: file.path,
              ),
            ],
          );
          await repository.saveMessage(attachmentMessage);

          await AttachmentRetentionManager(
            repository: repository,
            root: root,
          ).deleteMessage(attachmentMessage.id);

          expect(await repository.getMessage(attachmentMessage.id), isNull);
          expect(await file.exists(), isFalse);
        } finally {
          if (await root.exists()) await root.delete(recursive: true);
        }
      },
    );

    test(
      'exports complete Work and device configuration without history',
      () async {
        await repository.saveMessage(message);
        await repository.saveWork(
          Work(
            id: 'export-work',
            revision: 1,
            name: 'Export me',
            ownerDeviceId: 'desktop',
            platformBindings: const {
              'kind': 'android-http',
              'environment': {'API_KEY': 'secret-value'},
              'token': 'secret-token',
            },
          ),
        );
        await repository.saveDevice(
          Device(
            id: 'export-device',
            displayName: 'Desk',
            platform: 'windows',
            publicKey: 'public',
            endpoint: const {'url': 'https://relay.example', 'token': 'secret'},
          ),
        );

        final exported = await ActentConfigurationTransfer(repository).export();
        final encoded = exported.toString();
        expect(encoded, contains('secret-value'));
        expect(encoded, contains('secret-token'));
        expect(exported['messages'], isNull);
        expect((exported['works'] as List).length, 1);
        expect((exported['devices'] as List).length, 1);

        final imported = ActentRepository(MemoryActentJsonStore());
        await ActentConfigurationTransfer(imported).import(exported);
        expect((await imported.getWork('export-work'))!.name, 'Export me');
        expect(await imported.getMessage(message.id), isNull);
        expect(
          (await imported.getDevice('export-device'))!.authorized,
          isFalse,
        );
      },
    );

    test('routes remote work through the connection contract', () async {
      final connection = FakeMessageConnection();
      final queue = WorkQueueCoordinator(repository: repository);
      final router = ActentRouter(
        deviceId: 'phone',
        repository: repository,
        connection: connection,
        queue: queue,
      );

      await router.route(message, work);

      expect(connection.sent.single.recipientId, 'desktop');
      expect(connection.sent.single.payload['type'], 'workRequest');
      final request = WorkRequest.fromJson(
        connection.sent.single.payload['request'],
      );
      expect(request.workId, work.id);
      expect(
        (await repository.getRequest(request.requestId))!.message.id,
        message.id,
      );
    });

    test('sends a durable stored receipt before remote work runs', () async {
      final connection = FakeMessageConnection();
      final queue = WorkQueueCoordinator(repository: repository)
        ..register(work.id, const NullWorkRunner());
      final router = ActentRouter(
        deviceId: 'desktop',
        repository: repository,
        connection: connection,
        queue: queue,
      );
      final request = WorkRequest(
        requestId: 'remote-request',
        message: message,
        workId: work.id,
        workRevision: work.revision,
        sourceDeviceId: 'phone',
        targetDeviceId: 'desktop',
        createdAt: DateTime.now().toUtc(),
        expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 1)),
      );
      await repository.saveWork(work);

      final receipt = await router.receive({
        'type': 'workRequest',
        'schemaVersion': actentSchemaVersion,
        'request': request.toJson(),
      });
      await pumpEventQueue();

      expect(receipt.status, WorkReceiptStatus.stored);
      expect(connection.sent.first.payload['type'], 'workReceipt');
      expect(connection.sent.first.payload['receipt'], isA<Map>());
    });

    test('applies catalog snapshots and deltas to repository state', () async {
      final connection = FakeMessageConnection();
      final catalog = WorkCatalog();
      final router = ActentRouter(
        deviceId: 'desktop',
        repository: repository,
        connection: connection,
        queue: WorkQueueCoordinator(repository: repository),
        catalog: catalog,
      );
      await router.receiveCatalogSnapshot({
        'revision': 1,
        'works': [work.toJson()],
      });
      expect(catalog.revision, 1);
      expect((await repository.getWork(work.id))!.name, work.name);
      final updated = Work(
        id: work.id,
        revision: 2,
        name: 'Updated',
        ownerDeviceId: work.ownerDeviceId,
        acceptedContentTypes: work.acceptedContentTypes,
      );
      await router.receiveCatalogDelta({
        'baseRevision': 1,
        'nextRevision': 2,
        'upserts': [updated.toJson()],
        'removedWorkIds': const <String>[],
      });
      expect((await repository.getWork(work.id))!.revision, 2);
    });

    test('unpairing notifies the peer and removes its catalog', () async {
      final connection = FakeMessageConnection();
      final router = ActentRouter(
        deviceId: 'desktop',
        repository: repository,
        connection: connection,
        queue: WorkQueueCoordinator(repository: repository),
      );
      final peerWork = Work(
        id: 'phone-work',
        revision: 1,
        name: 'Phone Work',
        ownerDeviceId: 'phone',
      );
      await repository.saveDevice(
        Device(
          id: 'phone',
          displayName: 'Phone',
          platform: 'ios',
          publicKey: 'phone-key',
        ),
      );
      await repository.saveWork(peerWork);

      await router.unpair('phone');

      expect(connection.sent.single.recipientId, 'phone');
      expect(connection.sent.single.payload['type'], 'pairingRemoved');
      expect(await repository.getDevice('phone'), isNull);
      expect(await repository.getWork(peerWork.id), isNull);
    });

    test(
      'publishes a catalog delta after establishing a snapshot baseline',
      () async {
        final connection = FakeMessageConnection();
        await repository.saveWork(
          Work(
            id: 'local-work',
            revision: 1,
            name: 'Local',
            ownerDeviceId: 'desktop',
            acceptedContentTypes: const {ActentContentType.text},
          ),
        );
        final router = ActentRouter(
          deviceId: 'desktop',
          repository: repository,
          connection: connection,
          queue: WorkQueueCoordinator(repository: repository),
        );
        await router.sendCatalogSnapshot('phone');
        final snapshot = connection.sent.single.payload['catalog'] as Map;
        final snapshotWork = (snapshot['works'] as List).single as Map;
        expect(snapshotWork['catalogOnly'], isTrue);
        expect(snapshotWork['platformBindings'], isNull);
        connection.sent.clear();
        await repository.saveWork(
          Work(
            id: 'local-work',
            revision: 2,
            name: 'Updated',
            ownerDeviceId: 'desktop',
            acceptedContentTypes: const {ActentContentType.text},
          ),
        );
        await router.sendCatalogDelta('phone');

        expect(connection.sent.single.payload['type'], 'catalogDelta');
        final catalog = connection.sent.single.payload['catalog'] as Map;
        expect(catalog['baseRevision'], 1);
        expect(catalog['nextRevision'], 2);
        expect(
          (catalog['upserts'] as List).single,
          containsPair('revision', 2),
        );
        connection.sent.clear();
        await router.sendCatalogDelta('phone');
        expect(connection.sent, isEmpty);
      },
    );

    test('Null Work stores and returns a receipt', () async {
      final receipts = <WorkReceipt>[];
      final queue = WorkQueueCoordinator(
        repository: repository,
        onReceipt: (receipt) async => receipts.add(receipt),
      )..register('work-1', const NullWorkRunner());
      final request = WorkRequest(
        requestId: 'request-1',
        message: message,
        workId: work.id,
        workRevision: work.revision,
        sourceDeviceId: 'phone',
        targetDeviceId: 'desktop',
        createdAt: DateTime.now().toUtc(),
        expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 1)),
      );

      await queue.enqueue(work, request);
      await pumpEventQueue();

      expect(receipts.map((receipt) => receipt.status), [
        WorkReceiptStatus.queued,
        WorkReceiptStatus.processing,
        WorkReceiptStatus.stored,
      ]);
      expect(
        (await repository.getReceipt('request-1'))!.status,
        WorkReceiptStatus.stored,
      );
    });

    test('routing ignores stale receipt sequences', () async {
      final connection = FakeMessageConnection();
      final router = ActentRouter(
        deviceId: 'phone',
        repository: repository,
        connection: connection,
        queue: WorkQueueCoordinator(repository: repository),
      );
      final now = DateTime.now().toUtc();
      final request = WorkRequest(
        requestId: 'receipt-sequence',
        message: message,
        workId: work.id,
        workRevision: work.revision,
        sourceDeviceId: 'phone',
        targetDeviceId: 'desktop',
        createdAt: now,
        expiresAt: now.add(const Duration(hours: 1)),
      );
      await repository.saveRequest(request);
      final newest = WorkReceipt(
        requestId: request.requestId,
        workId: work.id,
        status: WorkReceiptStatus.succeeded,
        sequence: 2,
        createdAt: now,
      );
      await router.receive({'type': 'workReceipt', 'receipt': newest.toJson()});
      final stale = WorkReceipt(
        requestId: request.requestId,
        workId: work.id,
        status: WorkReceiptStatus.processing,
        sequence: 1,
        createdAt: now,
      );
      final result = await router.receive({
        'type': 'workReceipt',
        'receipt': stale.toJson(),
      });
      expect(result.status, WorkReceiptStatus.succeeded);
      expect((await repository.getReceipt(request.requestId))!.sequence, 2);
    });

    test('restores a durable request after a queue restart', () async {
      final request = WorkRequest(
        requestId: 'request-recover',
        message: message,
        workId: work.id,
        workRevision: work.revision,
        sourceDeviceId: 'phone',
        targetDeviceId: 'desktop',
        createdAt: DateTime.now().toUtc(),
        expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 1)),
      );
      await repository.saveRequest(request);
      final runner = FakeWorkRunner();
      final queue = WorkQueueCoordinator(repository: repository)
        ..register(work.id, runner);

      await queue.restorePending([work]);
      await pumpEventQueue();

      expect(runner.requests, ['request-recover']);
      expect(
        (await repository.getReceipt('request-recover'))!.status,
        WorkReceiptStatus.succeeded,
      );
    });

    test(
      'does not execute a durable request against a changed Work revision',
      () async {
        final request = WorkRequest(
          requestId: 'request-changed',
          message: message,
          workId: work.id,
          workRevision: work.revision,
          sourceDeviceId: 'phone',
          targetDeviceId: 'desktop',
          createdAt: DateTime.now().toUtc(),
          expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 1)),
        );
        await repository.saveRequest(request);
        final runner = FakeWorkRunner();
        final queue = WorkQueueCoordinator(repository: repository)
          ..register(work.id, runner);
        final changed = Work(
          id: work.id,
          revision: 2,
          name: work.name,
          ownerDeviceId: work.ownerDeviceId,
          acceptedContentTypes: work.acceptedContentTypes,
        );

        await queue.restorePending([changed]);

        expect(runner.requests, isEmpty);
        expect(
          (await repository.getReceipt(request.requestId))!.errorCode,
          'work_changed',
        );
      },
    );

    test('restored requests over the queue limit receive queue_full', () async {
      final limited = Work(
        id: 'limited-work',
        revision: 1,
        name: 'Limited',
        ownerDeviceId: 'desktop',
        acceptedContentTypes: const {ActentContentType.text},
        queueLimit: 1,
      );
      final first = WorkRequest(
        requestId: 'request-limited-1',
        message: message,
        workId: limited.id,
        workRevision: limited.revision,
        sourceDeviceId: 'phone',
        targetDeviceId: 'desktop',
        createdAt: DateTime.now().toUtc(),
        expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 1)),
      );
      final second = WorkRequest(
        requestId: 'request-limited-2',
        message: message,
        workId: limited.id,
        workRevision: limited.revision,
        sourceDeviceId: 'phone',
        targetDeviceId: 'desktop',
        createdAt: DateTime.now().toUtc(),
        expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 1)),
      );
      await repository.saveRequest(first);
      await repository.saveRequest(second);
      final queue = WorkQueueCoordinator(repository: repository)
        ..register(limited.id, FakeWorkRunner());

      await queue.restorePending([limited]);
      await pumpEventQueue();

      expect(
        (await repository.getReceipt(second.requestId))!.errorCode,
        'queue_full',
      );
    });
  });

  test('applies Work catalog snapshots and deltas by revision', () {
    final work = Work(
      id: 'work-1',
      revision: 1,
      name: 'One',
      ownerDeviceId: 'desktop',
      acceptedContentTypes: const {ActentContentType.text},
    );
    final catalog = WorkCatalog(revision: 1, works: [work]);
    catalog.applyDelta(
      baseRevision: 1,
      nextRevision: 2,
      upserts: [
        Work(
          id: 'work-2',
          revision: 1,
          name: 'Two',
          ownerDeviceId: 'desktop',
          acceptedContentTypes: const {ActentContentType.url},
        ),
      ],
      removedWorkIds: const [],
    );
    expect(catalog.revision, 2);
    expect(catalog['work-2']!.name, 'Two');
    expect(
      () => catalog.applyDelta(
        baseRevision: 1,
        nextRevision: 3,
        upserts: const [],
        removedWorkIds: const [],
      ),
      throwsA(isA<WorkCatalogException>()),
    );
  });

  test(
    'router executes a local linear workflow and forwards step output',
    () async {
      final repository = ActentRepository(MemoryActentJsonStore());
      final first = Work(
        id: 'first',
        revision: 1,
        name: 'First',
        ownerDeviceId: 'phone',
        acceptedContentTypes: const {ActentContentType.text},
        outputType: ActentContentType.text,
      );
      final second = Work(
        id: 'second',
        revision: 1,
        name: 'Second',
        ownerDeviceId: 'phone',
        acceptedContentTypes: const {ActentContentType.text},
        outputType: ActentContentType.none,
      );
      await repository.saveWork(first);
      await repository.saveWork(second);
      final queue = WorkQueueCoordinator(repository: repository)
        ..register(
          first.id,
          FakeWorkRunner(
            result: WorkRunResult.success(
              output: ActentPayload(
                type: ActentContentType.text,
                data: const {'text': 'next'},
              ),
            ),
          ),
        )
        ..register(second.id, FakeWorkRunner());
      final router = ActentRouter(
        deviceId: 'phone',
        repository: repository,
        connection: FakeMessageConnection(),
        queue: queue,
      );
      final now = DateTime.now().toUtc();
      final message = ActentMessage(
        id: 'workflow-input',
        traceId: 'trace',
        createdAt: now,
        source: const ActentSource(kind: 'test', deviceId: 'phone'),
        payload: ActentPayload(
          type: ActentContentType.text,
          data: const {'text': 'input'},
        ),
      );
      final workflow = Workflow(
        id: 'workflow',
        revision: 1,
        name: 'Two steps',
        ownerDeviceId: 'phone',
        acceptedContentTypes: const {ActentContentType.text},
        steps: const [
          WorkflowStep(
            id: 'first-step',
            workId: 'first',
            workRevision: 1,
            deviceId: 'phone',
          ),
          WorkflowStep(
            id: 'second-step',
            workId: 'second',
            workRevision: 1,
            deviceId: 'phone',
          ),
        ],
      );
      final execution = await router.runWorkflow(message, workflow);
      expect(execution.status, WorkflowExecutionStatus.succeeded);
      expect(execution.currentStepIndex, 1);
      final requests = await repository.listRequests();
      expect(requests, hasLength(2));
      expect(
        requests.every((request) => request.workflowExecutionId != null),
        isTrue,
      );
    },
  );

  test('router rejects a workflow that crosses paired devices', () async {
    final sourceRepository = ActentRepository(MemoryActentJsonStore());
    final targetRepository = ActentRepository(MemoryActentJsonStore());
    final remoteWork = Work(
      id: 'remote',
      revision: 1,
      name: 'Remote step',
      ownerDeviceId: 'desktop',
      acceptedContentTypes: const {ActentContentType.text},
      outputType: ActentContentType.text,
    );
    final localWork = Work(
      id: 'local',
      revision: 1,
      name: 'Local step',
      ownerDeviceId: 'phone',
      acceptedContentTypes: const {ActentContentType.text},
      outputType: ActentContentType.none,
    );
    await sourceRepository.saveWork(remoteWork);
    await sourceRepository.saveWork(localWork);
    await targetRepository.saveWork(remoteWork);
    await targetRepository.saveDevice(
      Device(
        id: 'phone',
        displayName: 'Phone',
        platform: 'ios',
        publicKey: 'phone-key',
      ),
    );
    await sourceRepository.saveDevice(
      Device(
        id: 'desktop',
        displayName: 'Desktop',
        platform: 'windows',
        publicKey: 'desktop-key',
      ),
    );
    final sourceQueue = WorkQueueCoordinator(repository: sourceRepository)
      ..register(localWork.id, FakeWorkRunner());
    final targetQueue = WorkQueueCoordinator(repository: targetRepository)
      ..register(
        remoteWork.id,
        FakeWorkRunner(
          result: WorkRunResult.success(
            output: ActentPayload(
              type: ActentContentType.text,
              data: const {'text': 'remote output'},
            ),
          ),
        ),
      );
    late ActentRouter sourceRouter;
    late ActentRouter targetRouter;
    sourceRouter = ActentRouter(
      deviceId: 'phone',
      repository: sourceRepository,
      connection: _RouterBridge('phone', () => targetRouter),
      queue: sourceQueue,
    );
    targetRouter = ActentRouter(
      deviceId: 'desktop',
      repository: targetRepository,
      connection: _RouterBridge('desktop', () => sourceRouter),
      queue: targetQueue,
    );
    final now = DateTime.now().toUtc();
    final execution = await sourceRouter.runWorkflow(
      ActentMessage(
        id: 'cross-device-input',
        traceId: 'trace',
        createdAt: now,
        source: const ActentSource(kind: 'test', deviceId: 'phone'),
        payload: ActentPayload(
          type: ActentContentType.text,
          data: const {'text': 'input'},
        ),
      ),
      Workflow(
        id: 'cross-device',
        revision: 1,
        name: 'Remote then local',
        ownerDeviceId: 'phone',
        acceptedContentTypes: const {ActentContentType.text},
        steps: const [
          WorkflowStep(
            id: 'remote-step',
            workId: 'remote',
            workRevision: 1,
            deviceId: 'desktop',
          ),
          WorkflowStep(
            id: 'local-step',
            workId: 'local',
            workRevision: 1,
            deviceId: 'phone',
          ),
        ],
      ),
    );
    expect(execution.status, WorkflowExecutionStatus.invalid);
    expect(execution.error?.message, contains('workflow_local_only'));
    expect(await targetRepository.listRequests(), isEmpty);
    expect(await sourceRepository.listRequests(), isEmpty);
  });
}

class _RouterBridge implements MessageConnection {
  _RouterBridge(this.senderId, this.target);

  final String senderId;
  final ActentRouter Function() target;

  @override
  Future<void> send({
    required String recipientId,
    required Map<String, Object?> payload,
  }) => target().receive(payload, authenticatedSenderId: senderId).then((_) {});
}
