import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pengion/features/pigeon_core/attachment_retention.dart';
import 'package:pengion/features/pigeon_core/configuration_transfer.dart';
import 'package:pengion/features/pigeon_core/pigeon_models.dart';
import 'package:pengion/features/pigeon_core/pigeon_repository.dart';
import 'package:pengion/features/pigeon_core/pigeon_router.dart';
import 'package:pengion/features/pigeon_core/pigeon_store.dart';
import 'package:pengion/features/pigeon_core/work_catalog.dart';
import 'package:pengion/features/work/work_runner.dart';

void main() {
  group('Pigeon schema', () {
    test('round trips a versioned message', () {
      final message = PigeonMessage(
        id: 'message-1',
        traceId: 'trace-1',
        createdAt: DateTime.utc(2026, 1, 1),
        source: const PigeonSource(kind: 'share', deviceId: 'phone'),
        content: PigeonContent(
          type: PigeonContentType.text,
          data: const {'text': 'hello'},
        ),
        attachments: const [
          PigeonAttachment(
            id: 'attachment-1',
            name: 'note.txt',
            mimeType: 'text/plain',
            byteLength: 5,
            handle: 'attachments/attachment-1/note.txt',
          ),
        ],
      );

      final decoded = PigeonMessage.fromJson(message.toJson());
      expect(decoded.id, message.id);
      expect(decoded.content.data['text'], 'hello');
      expect(decoded.attachments.single.byteLength, 5);
    });

    test('Null Work accepts every content type without a platform binding', () {
      final work = Work.nullWork(id: 'null', ownerDeviceId: 'desktop');

      expect(
        PigeonContentType.values.every(
          (type) => work.accepts(
            PigeonMessage(
              id: 'message-${type.name}',
              traceId: 'trace-${type.name}',
              createdAt: DateTime.utc(2026),
              source: const PigeonSource(kind: 'test'),
              content: PigeonContent(type: type),
            ),
          ),
        ),
        isTrue,
      );
    });

    test('rejects an unsupported schema version before accepting content', () {
      expect(
        () => PigeonMessage.fromJson(<String, Object?>{
          'id': 'message-1',
          'traceId': 'trace-1',
          'schemaVersion': 2,
        }),
        throwsA(isA<PigeonValidationException>()),
      );
    });

    test('rejects unknown envelope and attachment fields', () {
      final message = PigeonMessage(
        id: 'message-1',
        traceId: 'trace-1',
        createdAt: DateTime.utc(2026, 1, 1),
        source: const PigeonSource(kind: 'share'),
        content: PigeonContent(
          type: PigeonContentType.text,
          data: const {'text': 'hello'},
        ),
        attachments: const [
          PigeonAttachment(
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
        () => PigeonMessage.fromJson(unknownEnvelope),
        throwsA(isA<PigeonValidationException>()),
      );

      final unknownAttachment = message.toJson();
      final attachments = (unknownAttachment['attachments'] as List)
          .cast<Object?>();
      attachments[0] = Map<String, Object?>.from(attachments[0] as Map)
        ..['unexpected'] = true;
      expect(
        () => PigeonMessage.fromJson(unknownAttachment),
        throwsA(isA<PigeonValidationException>()),
      );
    });
  });

  group('Pigeon repository and routing', () {
    late MemoryPigeonJsonStore store;
    late PigeonRepository repository;
    late Work work;
    late PigeonMessage message;

    setUp(() {
      store = MemoryPigeonJsonStore();
      repository = PigeonRepository(store);
      work = Work(
        id: 'work-1',
        revision: 1,
        name: 'Store text',
        ownerDeviceId: 'desktop',
        acceptedContentTypes: const {PigeonContentType.text},
      );
      message = PigeonMessage(
        id: 'message-1',
        traceId: 'trace-1',
        createdAt: DateTime.utc(2026, 1, 1),
        source: const PigeonSource(kind: 'share', deviceId: 'phone'),
        content: PigeonContent(type: PigeonContentType.text),
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

    test(
      'deleting a message removes only its unreferenced attachment files',
      () async {
        final root = await Directory.systemTemp.createTemp('pigeon-retention-');
        try {
          final file = File('${root.path}${Platform.pathSeparator}payload.txt');
          await file.writeAsString('payload');
          final attachmentMessage = PigeonMessage(
            id: 'message-with-file',
            traceId: 'trace-file',
            createdAt: DateTime.now().toUtc(),
            source: const PigeonSource(kind: 'share'),
            content: PigeonContent(type: PigeonContentType.file),
            attachments: [
              PigeonAttachment(
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
      'exports Work and device configuration without secrets or history',
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

        final exported = await PigeonConfigurationTransfer(repository).export();
        final encoded = exported.toString();
        expect(encoded, isNot(contains('secret')));
        expect(exported['messages'], isNull);
        expect((exported['works'] as List).length, 1);
        expect((exported['devices'] as List).length, 1);

        final imported = PigeonRepository(MemoryPigeonJsonStore());
        await PigeonConfigurationTransfer(imported).import(exported);
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
      final router = PigeonRouter(
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
      final router = PigeonRouter(
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
        'schemaVersion': pigeonSchemaVersion,
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
      final router = PigeonRouter(
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
            acceptedContentTypes: const {PigeonContentType.text},
          ),
        );
        final router = PigeonRouter(
          deviceId: 'desktop',
          repository: repository,
          connection: connection,
          queue: WorkQueueCoordinator(repository: repository),
        );
        await router.sendCatalogSnapshot('phone');
        connection.sent.clear();
        await repository.saveWork(
          Work(
            id: 'local-work',
            revision: 2,
            name: 'Updated',
            ownerDeviceId: 'desktop',
            acceptedContentTypes: const {PigeonContentType.text},
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

      expect(receipts.single.status, WorkReceiptStatus.stored);
      expect(
        (await repository.getReceipt('request-1'))!.status,
        WorkReceiptStatus.stored,
      );
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
        acceptedContentTypes: const {PigeonContentType.text},
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
      acceptedContentTypes: const {PigeonContentType.text},
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
          acceptedContentTypes: const {PigeonContentType.url},
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
}
