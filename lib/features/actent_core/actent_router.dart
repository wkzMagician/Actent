import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import '../messaging/message_connection.dart';
import '../messaging/messaging_packet.dart';
import '../messaging/packet_crypto.dart';
import '../messaging/seen_packet_store.dart';
import 'actent_models.dart';
import 'actent_store.dart';
import 'work_catalog.dart';
import '../work/work_runner.dart';
import 'workflow_engine.dart';

abstract interface class MessageConnection {
  Future<void> send({
    required String recipientId,
    required Map<String, Object?> payload,
  });
}

class DuplicateActentPacketException implements Exception {
  const DuplicateActentPacketException(this.packetId);

  final String packetId;

  @override
  String toString() => 'Actent packet already processed: $packetId';
}

/// Encrypts Actent protocol payloads before handing them to the generic
/// messaging capability. The capability never sees Work or Actent payload
/// types; it only transports [MessagingPacket].
class EncryptedMessageConnection implements MessageConnection {
  EncryptedMessageConnection({
    required this.transport,
    required this.localIdentity,
    required this.remotePublicKey,
    required this.senderId,
    required this.recipientId,
    PacketCrypto? crypto,
    SeenPacketStore? seenPackets,
  }) : _crypto = crypto ?? PacketCrypto(),
       _seenPackets = seenPackets ?? SeenPacketStore();

  final PacketConnection transport;
  final PacketIdentity localIdentity;
  final SimplePublicKey remotePublicKey;
  final String senderId;
  final String recipientId;
  final PacketCrypto _crypto;
  final SeenPacketStore _seenPackets;

  @override
  Future<void> send({
    required String recipientId,
    required Map<String, Object?> payload,
  }) async {
    if (recipientId != this.recipientId) {
      throw ArgumentError.value(
        recipientId,
        'recipientId',
        'connection recipient mismatch',
      );
    }
    final packet = await _crypto.encrypt(
      sender: localIdentity,
      recipientPublicKey: remotePublicKey,
      packetId: 'packet-${DateTime.now().microsecondsSinceEpoch}',
      senderId: senderId,
      recipientId: recipientId,
      plaintext: utf8.encode(jsonEncode(payload)),
    );
    await transport.send(packet);
  }

  Future<Map<String, Object?>> receive(
    MessagingPacket packet, {
    required String expectedSenderId,
  }) async {
    if (packet.recipientId != recipientId ||
        packet.senderId != expectedSenderId) {
      throw const PacketValidationException('packet endpoint mismatch');
    }
    PacketValidator(recipientId: recipientId).validate(packet);
    if (_seenPackets.contains(packet.packetId)) {
      throw DuplicateActentPacketException(packet.packetId);
    }
    final plaintext = await _crypto.decrypt(
      recipient: localIdentity,
      senderPublicKey: remotePublicKey,
      packet: packet,
    );
    final decoded = jsonDecode(utf8.decode(plaintext));
    if (decoded is! Map) {
      throw const PacketValidationException('Actent payload must be an object');
    }
    if (decoded['schemaVersion'] != actentSchemaVersion) {
      throw const PacketValidationException(
        'unsupported Actent payload version',
      );
    }
    _seenPackets.remember(packet.packetId);
    return Map<String, Object?>.from(decoded);
  }
}

class SentMessage {
  const SentMessage({required this.recipientId, required this.payload});

  final String recipientId;
  final Map<String, Object?> payload;
}

class FakeMessageConnection implements MessageConnection {
  final List<SentMessage> sent = [];

  @override
  Future<void> send({
    required String recipientId,
    required Map<String, Object?> payload,
  }) async {
    sent.add(SentMessage(recipientId: recipientId, payload: payload));
  }
}

class ActentRouter {
  ActentRouter({
    required this.deviceId,
    required this.repository,
    required this.connection,
    required this.queue,
    this.catalog,
  }) {
    queue.addReceiptListener(_forwardReceipt);
  }

  final String deviceId;
  final ActentRepository repository;
  final MessageConnection connection;
  final WorkQueueCoordinator queue;
  final WorkCatalog? catalog;
  final Map<String, WorkCatalog> _receivedCatalogs = {};
  final Map<String, _PublishedCatalog> _publishedCatalogs = {};
  final StreamController<void> _repositoryUpdates =
      StreamController<void>.broadcast();

  Stream<void> get repositoryUpdates => _repositoryUpdates.stream;

  Future<void> _forwardReceipt(WorkReceipt receipt) async {
    final request = await repository.getRequest(receipt.requestId);
    if (request == null || request.sourceDeviceId == deviceId) return;
    await connection.send(
      recipientId: request.sourceDeviceId,
      payload: <String, Object?>{
        'type': 'workReceipt',
        'schemaVersion': actentSchemaVersion,
        'receipt': receipt.toJson(),
      },
    );
  }

  Future<WorkRequest> route(
    ActentMessage message,
    Work work, {
    String? targetDeviceId,
    String? workflowExecutionId,
    String? workflowStepId,
    String? workflowOwnerDeviceId,
  }) async {
    if (!work.enabled) throw WorkUnavailableException(work.id, 'disabled');
    if (!work.accepts(message)) {
      throw WorkUnavailableException(work.id, 'content type is not accepted');
    }
    await repository.saveMessage(message);
    final target = targetDeviceId ?? work.ownerDeviceId;
    if (target == deviceId) {
      final request = _request(
        message,
        work,
        sourceDeviceId: deviceId,
        workflowExecutionId: workflowExecutionId,
        workflowStepId: workflowStepId,
        workflowOwnerDeviceId: workflowOwnerDeviceId,
      );
      await queue.enqueue(work, request);
      return request;
    }
    final request = _request(
      message,
      work,
      sourceDeviceId: deviceId,
      targetDeviceId: target,
      workflowExecutionId: workflowExecutionId,
      workflowStepId: workflowStepId,
      workflowOwnerDeviceId: workflowOwnerDeviceId,
    );
    await repository.saveRequest(request);
    await connection.send(
      recipientId: target,
      payload: <String, Object?>{
        'type': 'workRequest',
        'schemaVersion': actentSchemaVersion,
        'request': request.toJson(),
      },
    );
    return request;
  }

  /// Executes a linear Workflow through the same paired Work route used by
  /// individual tasks. Only the owner coordinates; no temporary authorization
  /// channel is introduced between devices.
  Future<WorkflowExecution> runWorkflow(
    ActentMessage message,
    Workflow workflow,
  ) async {
    final runner = WorkflowRunner(
      repository: repository,
      validator: WorkflowValidator(
        repository: repository,
        localDeviceId: deviceId,
      ),
    );
    return runner.start(
      workflow: workflow,
      input: message.payload,
      sourceDeviceId: deviceId,
      executeStep:
          ({
            required step,
            required work,
            required input,
            required executionId,
          }) async {
            final stepMessage = _workflowMessage(message, input, step.id);
            final request = await route(
              stepMessage,
              work,
              targetDeviceId: step.deviceId,
              workflowExecutionId: executionId,
              workflowStepId: step.id,
              workflowOwnerDeviceId: workflow.ownerDeviceId,
            );
            return _waitForTerminalReceipt(request.requestId);
          },
    );
  }

  /// Reruns only the failed step using the output persisted by the preceding
  /// successful step. A new Workflow execution is not created.
  Future<WorkflowExecution> continueWorkflow(
    Workflow workflow,
    WorkflowExecution execution,
  ) async {
    final runner = WorkflowRunner(
      repository: repository,
      validator: WorkflowValidator(
        repository: repository,
        localDeviceId: deviceId,
      ),
    );
    final seed = ActentMessage(
      id: 'workflow-continue-${execution.id}',
      traceId: execution.id,
      createdAt: execution.createdAt,
      source: ActentSource(kind: 'workflow', deviceId: deviceId),
      payload: execution.output ?? ActentPayload(type: ActentContentType.none),
    );
    return runner.continueFailed(
      workflow: workflow,
      execution: execution,
      executeStep:
          ({
            required step,
            required work,
            required input,
            required executionId,
          }) async {
            final request = await route(
              _workflowMessage(seed, input, step.id),
              work,
              targetDeviceId: step.deviceId,
              workflowExecutionId: executionId,
              workflowStepId: step.id,
              workflowOwnerDeviceId: workflow.ownerDeviceId,
            );
            return _waitForTerminalReceipt(request.requestId);
          },
    );
  }

  Future<WorkReceipt> _waitForTerminalReceipt(String requestId) async {
    final deadline = DateTime.now().add(const Duration(hours: 24));
    while (DateTime.now().isBefore(deadline)) {
      final receipt = await repository.getReceipt(requestId);
      if (receipt != null && _isTerminalReceipt(receipt.status)) {
        return receipt;
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return WorkReceipt(
      requestId: requestId,
      workId: requestId,
      status: WorkReceiptStatus.failed,
      createdAt: DateTime.now().toUtc(),
      error: const WorkError(code: 'workflow_step_timeout'),
    );
  }

  bool _isTerminalReceipt(WorkReceiptStatus status) => switch (status) {
    WorkReceiptStatus.succeeded ||
    WorkReceiptStatus.failed ||
    WorkReceiptStatus.expired ||
    WorkReceiptStatus.cancelled ||
    WorkReceiptStatus.interrupted => true,
    _ => false,
  };

  ActentMessage _workflowMessage(
    ActentMessage original,
    ActentPayload payload,
    String stepId,
  ) => ActentMessage(
    id: '${original.id}-$stepId-${DateTime.now().microsecondsSinceEpoch}',
    traceId: original.traceId,
    createdAt: DateTime.now().toUtc(),
    source: original.source,
    payload: payload,
    metadata: <String, Object?>{...original.metadata, 'workflowStepId': stepId},
  );

  Future<WorkReceipt> receive(
    Map<String, Object?> payload, {
    String? authenticatedSenderId,
  }) async {
    final senderId = authenticatedSenderId;
    final type = payload['type'];
    if (type == 'workCancel') {
      return _receiveCancel(payload, authenticatedSenderId: senderId);
    }
    if (type == 'workReceipt') {
      final receipt = WorkReceipt.fromJson(payload['receipt']);
      if (authenticatedSenderId != null) {
        final request = await repository.getRequest(receipt.requestId);
        if (request == null ||
            request.sourceDeviceId != deviceId ||
            request.targetDeviceId != authenticatedSenderId) {
          throw const ActentValidationException(
            'receipt',
            'receipt is not authorized for the authenticated sender',
          );
        }
      }
      final existing = await repository.getReceipt(receipt.requestId);
      if (existing != null && existing.sequence >= receipt.sequence) {
        return existing;
      }
      await repository.saveReceipt(receipt);
      return receipt;
    }
    if (payload['type'] != 'workRequest') {
      throw const ActentValidationException(
        'type',
        'unsupported Actent payload type',
      );
    }
    final request = WorkRequest.fromJson(payload['request']);
    if (senderId != null && request.sourceDeviceId != senderId) {
      throw const ActentValidationException(
        'request.sourceDeviceId',
        'does not match authenticated packet sender',
      );
    }
    if (request.targetDeviceId != deviceId) {
      throw const ActentValidationException(
        'request.targetDeviceId',
        'packet recipient mismatch',
      );
    }
    final existingReceipt = await repository.getReceipt(request.requestId);
    if (existingReceipt != null) return existingReceipt;
    final work = await repository.getWork(request.workId);
    if (work == null) {
      return _sendFailure(
        request,
        WorkReceiptStatus.failed,
        'work_unavailable',
      );
    }
    if (request.workRevision != work.revision) {
      return _sendFailure(request, WorkReceiptStatus.failed, 'work_changed');
    }
    if (!work.isAuthorized(request.sourceDeviceId)) {
      return _sendFailure(
        request,
        WorkReceiptStatus.failed,
        'authorization_denied',
      );
    }
    if (request.isExpired) {
      return _sendFailure(request, WorkReceiptStatus.expired, 'expired');
    }
    try {
      await queue.enqueue(work, request);
      await repository.saveMessage(request.message);
    } on WorkQueueFullException {
      return _sendFailure(request, WorkReceiptStatus.failed, 'queue_full');
    } on WorkUnavailableException catch (error) {
      return _sendFailure(
        request,
        WorkReceiptStatus.failed,
        _errorCode(error.reason),
      );
    }
    final stored = WorkReceipt(
      requestId: request.requestId,
      workId: request.workId,
      status: WorkReceiptStatus.stored,
      createdAt: DateTime.now().toUtc(),
    );
    await _sendReceipt(request.sourceDeviceId, stored);
    return stored;
  }

  /// The source device can cancel its own request; the target device can
  /// always cancel locally. A third device cannot cancel either side's work.
  Future<bool> cancelRequest(String requestId) async {
    final request = await repository.getRequest(requestId);
    if (request == null ||
        (request.sourceDeviceId != deviceId &&
            request.targetDeviceId != deviceId)) {
      return false;
    }
    if (request.sourceDeviceId == deviceId &&
        request.targetDeviceId != deviceId) {
      await connection.send(
        recipientId: request.targetDeviceId,
        payload: <String, Object?>{
          'type': 'workCancel',
          'schemaVersion': actentSchemaVersion,
          'requestId': request.requestId,
          'sourceDeviceId': deviceId,
        },
      );
      return true;
    }
    return queue.cancel(requestId);
  }

  Future<WorkReceipt> _receiveCancel(
    Map<String, Object?> payload, {
    required String? authenticatedSenderId,
  }) async {
    final requestId = payload['requestId'];
    final sourceDeviceId = payload['sourceDeviceId'];
    if (requestId is! String || requestId.isEmpty) {
      throw const ActentValidationException(
        'requestId',
        'must be a non-empty string',
      );
    }
    if (sourceDeviceId is! String || sourceDeviceId.isEmpty) {
      throw const ActentValidationException(
        'sourceDeviceId',
        'must be a non-empty string',
      );
    }
    if (authenticatedSenderId != null &&
        authenticatedSenderId != sourceDeviceId) {
      throw const ActentValidationException(
        'sourceDeviceId',
        'does not match authenticated packet sender',
      );
    }
    final request = await repository.getRequest(requestId);
    if (request == null ||
        request.targetDeviceId != deviceId ||
        request.sourceDeviceId != sourceDeviceId) {
      throw const ActentValidationException(
        'requestId',
        'cancel request is not authorized',
      );
    }
    final existing = await repository.getReceipt(requestId);
    if (existing != null) return existing;
    await queue.cancel(requestId);
    return (await repository.getReceipt(requestId)) ??
        WorkReceipt(
          requestId: request.requestId,
          workId: request.workId,
          status: WorkReceiptStatus.cancelled,
          createdAt: DateTime.now().toUtc(),
          completedAt: DateTime.now().toUtc(),
        );
  }

  Future<WorkReceipt> _sendFailure(
    WorkRequest request,
    WorkReceiptStatus status,
    String errorCode,
  ) async {
    final receipt = WorkReceipt(
      requestId: request.requestId,
      workId: request.workId,
      status: status,
      createdAt: DateTime.now().toUtc(),
      completedAt: DateTime.now().toUtc(),
      errorCode: errorCode,
    );
    await repository.saveReceipt(receipt);
    await _sendReceipt(request.sourceDeviceId, receipt);
    return receipt;
  }

  Future<void> _sendReceipt(String recipientId, WorkReceipt receipt) =>
      connection.send(
        recipientId: recipientId,
        payload: <String, Object?>{
          'type': 'workReceipt',
          'schemaVersion': actentSchemaVersion,
          'receipt': receipt.toJson(),
        },
      );

  Future<void> receiveCatalogSnapshot(
    Object? value, {
    String? ownerDeviceId,
  }) async {
    final incoming = WorkCatalog.fromSnapshotJson(value);
    final snapshot = Map<String, Object?>.from(value as Map);
    final rawWorkflows = snapshot['workflows'];
    final incomingWorkflows = rawWorkflows is List
        ? rawWorkflows.map(Workflow.fromJson).toList()
        : const <Workflow>[];
    if (ownerDeviceId != null &&
        incomingWorkflows.any(
          (workflow) => workflow.ownerDeviceId != ownerDeviceId,
        )) {
      throw const WorkCatalogException(
        'catalog contains a Workflow owned by another device',
      );
    }
    if (ownerDeviceId != null &&
        incoming.works.any((work) => work.ownerDeviceId != ownerDeviceId)) {
      throw const WorkCatalogException(
        'catalog contains a Work owned by another device',
      );
    }
    final target = _catalogFor(ownerDeviceId);
    final previous = target.works.map((work) => work.id).toSet();
    target.replaceSnapshot(
      nextRevision: incoming.revision,
      works: incoming.works,
    );
    for (final work in target.works) {
      await repository.saveWork(work);
    }
    for (final workId in previous.difference(
      target.works.map((work) => work.id).toSet(),
    )) {
      final existing = await repository.getWork(workId);
      if (existing?.ownerDeviceId == ownerDeviceId) {
        await repository.deleteWork(workId);
      }
    }
    final existingWorkflows = await repository.listWorkflows();
    for (final workflow in incomingWorkflows) {
      await repository.saveWorkflow(workflow);
    }
    for (final workflow in existingWorkflows.where(
      (workflow) => workflow.ownerDeviceId == ownerDeviceId,
    )) {
      if (!incomingWorkflows.any((item) => item.id == workflow.id)) {
        await repository.deleteWorkflow(workflow.id);
      }
    }
    _repositoryUpdates.add(null);
  }

  Future<void> receiveCatalogDelta(
    Object? value, {
    String? ownerDeviceId,
  }) async {
    if (value is! Map) {
      throw const WorkCatalogException('delta must be an object');
    }
    final json = Map<String, Object?>.from(value);
    final rawUpserts = json['upserts'];
    final rawRemoved = json['removedWorkIds'];
    if (rawUpserts is! List || rawRemoved is! List) {
      throw const WorkCatalogException('delta upserts/removals are invalid');
    }
    final upserts = rawUpserts.map(Work.fromJson).toList();
    final rawWorkflowUpserts = json['workflowUpserts'];
    final workflowUpserts = rawWorkflowUpserts is List
        ? rawWorkflowUpserts.map(Workflow.fromJson).toList()
        : const <Workflow>[];
    if (ownerDeviceId != null &&
        upserts.any((work) => work.ownerDeviceId != ownerDeviceId)) {
      throw const WorkCatalogException(
        'catalog delta contains a Work owned by another device',
      );
    }
    final removed = rawRemoved.map((item) {
      if (item is! String || item.isEmpty) {
        throw const WorkCatalogException('removed work IDs must be strings');
      }
      return item;
    }).toList();
    final target = _catalogFor(ownerDeviceId);
    target.applyDelta(
      baseRevision: _requiredInt(json['baseRevision'], 'baseRevision'),
      nextRevision: _requiredInt(json['nextRevision'], 'nextRevision'),
      upserts: upserts,
      removedWorkIds: removed,
    );
    for (final work in upserts) {
      await repository.saveWork(work);
    }
    for (final workflow in workflowUpserts) {
      if (ownerDeviceId != null && workflow.ownerDeviceId != ownerDeviceId) {
        throw const WorkCatalogException(
          'catalog workflow is owned by another device',
        );
      }
      await repository.saveWorkflow(workflow);
    }
    final rawRemovedWorkflows = json['removedWorkflowIds'];
    if (rawRemovedWorkflows is List) {
      for (final id in rawRemovedWorkflows) {
        if (id is! String || id.isEmpty) {
          throw const WorkCatalogException(
            'removed workflow IDs must be strings',
          );
        }
        final workflow = await repository.getWorkflow(id);
        if (workflow?.ownerDeviceId == ownerDeviceId) {
          await repository.deleteWorkflow(id);
        }
      }
    }
    for (final workId in removed) {
      final existing = await repository.getWork(workId);
      if (existing?.ownerDeviceId == ownerDeviceId) {
        await repository.deleteWork(workId);
      }
    }
    _repositoryUpdates.add(null);
  }

  /// Sends the current non-local Work catalog to a newly paired device. The
  /// transport sees only a generic encrypted payload; Work remains a Actent
  /// concern inside this router.
  Future<void> sendCatalogSnapshot(String recipientId) async {
    final works = await _ownedWorks();
    final previous = _publishedCatalogs[recipientId];
    final revision = previous == null ? 1 : previous.revision + 1;
    await connection.send(
      recipientId: recipientId,
      payload: <String, Object?>{
        'type': 'catalogSnapshot',
        'schemaVersion': actentSchemaVersion,
        'catalog': <String, Object?>{
          'revision': revision,
          'works': works.map((work) => work.toCatalogJson()).toList(),
          'workflows': (await _ownedWorkflows())
              .map((workflow) => workflow.toJson())
              .toList(),
        },
      },
    );
    _publishedCatalogs[recipientId] = _PublishedCatalog(
      revision: revision,
      works: works,
      workflows: await _ownedWorkflows(),
    );
  }

  /// Shares the current device metadata with an already authenticated peer.
  /// Pairing invitations cannot be updated after they are issued, so this
  /// keeps device names and endpoints current after a rename or app update.
  Future<void> sendDeviceUpdate(String recipientId) async {
    final device = await repository.getDevice(deviceId);
    if (device == null) {
      throw StateError('local device is unavailable');
    }
    await connection.send(
      recipientId: recipientId,
      payload: <String, Object?>{
        'type': 'deviceUpdate',
        'schemaVersion': actentSchemaVersion,
        'device': device.toJson(),
      },
    );
  }

  Future<void> unpair(String recipientId) async {
    try {
      await connection.send(
        recipientId: recipientId,
        payload: <String, Object?>{
          'type': 'pairingRemoved',
          'schemaVersion': actentSchemaVersion,
        },
      );
    } on Object {
      // Local removal must still succeed when the peer is offline. Relay/LAN
      // delivery remains best effort.
    } finally {
      await _removePeer(recipientId);
    }
  }

  Future<void> receivePairingRemoved(String authenticatedSenderId) =>
      _removePeer(authenticatedSenderId);

  Future<void> _removePeer(String peerDeviceId) async {
    for (final work in await repository.listWorks()) {
      if (work.ownerDeviceId == peerDeviceId) {
        await repository.deleteWork(work.id);
      }
    }
    await repository.deleteDevice(peerDeviceId);
    _receivedCatalogs.remove(peerDeviceId);
    _publishedCatalogs.remove(peerDeviceId);
    _repositoryUpdates.add(null);
  }

  Future<void> receiveDeviceUpdate(
    Object? value, {
    required String authenticatedSenderId,
  }) async {
    final incoming = Device.fromJson(value);
    if (incoming.id != authenticatedSenderId) {
      throw const ActentValidationException(
        'device.id',
        'does not match authenticated packet sender',
      );
    }
    final existing = await repository.getDevice(authenticatedSenderId);
    if (existing == null ||
        !existing.authorized ||
        existing.publicKey != incoming.publicKey) {
      throw const ActentValidationException(
        'device',
        'update is not authorized for the authenticated sender',
      );
    }
    await repository.saveDevice(
      Device(
        id: incoming.id,
        displayName: incoming.displayName,
        platform: incoming.platform,
        publicKey: incoming.publicKey,
        endpoint: incoming.endpoint,
        pairedAt: existing.pairedAt,
        authorized: existing.authorized,
      ),
    );
    _repositoryUpdates.add(null);
  }

  /// Sends only changes since the last catalog delivered to [recipientId].
  /// A peer without an in-memory baseline receives a snapshot first.
  Future<void> sendCatalogDelta(String recipientId) async {
    final previous = _publishedCatalogs[recipientId];
    if (previous == null) {
      await sendCatalogSnapshot(recipientId);
      return;
    }
    final current = await _ownedWorks();
    final currentWorkflows = await _ownedWorkflows();
    final previousById = {for (final work in previous.works) work.id: work};
    final currentById = {for (final work in current) work.id: work};
    final upserts = current
        .where((work) {
          final old = previousById[work.id];
          return old == null ||
              jsonEncode(old.toJson()) != jsonEncode(work.toJson());
        })
        .toList(growable: false);
    final removed = previousById.keys
        .where((workId) => !currentById.containsKey(workId))
        .toList(growable: false);
    final previousWorkflowById = {
      for (final workflow in previous.workflows) workflow.id: workflow,
    };
    final currentWorkflowById = {
      for (final workflow in currentWorkflows) workflow.id: workflow,
    };
    final workflowUpserts = currentWorkflows
        .where((workflow) {
          final old = previousWorkflowById[workflow.id];
          return old == null ||
              jsonEncode(old.toJson()) != jsonEncode(workflow.toJson());
        })
        .toList(growable: false);
    final removedWorkflowIds = previousWorkflowById.keys
        .where((id) => !currentWorkflowById.containsKey(id))
        .toList(growable: false);
    if (upserts.isEmpty &&
        removed.isEmpty &&
        workflowUpserts.isEmpty &&
        removedWorkflowIds.isEmpty) {
      return;
    }
    final nextRevision = previous.revision + 1;
    await connection.send(
      recipientId: recipientId,
      payload: <String, Object?>{
        'type': 'catalogDelta',
        'schemaVersion': actentSchemaVersion,
        'catalog': <String, Object?>{
          'baseRevision': previous.revision,
          'nextRevision': nextRevision,
          'upserts': upserts.map((work) => work.toCatalogJson()).toList(),
          'removedWorkIds': removed,
          'workflowUpserts': workflowUpserts
              .map((item) => item.toJson())
              .toList(),
          'removedWorkflowIds': removedWorkflowIds,
        },
      },
    );
    _publishedCatalogs[recipientId] = _PublishedCatalog(
      revision: nextRevision,
      works: current,
      workflows: currentWorkflows,
    );
  }

  Future<List<Work>> _ownedWorks() async => (await repository.listWorks())
      .where((work) => work.ownerDeviceId == deviceId)
      .toList(growable: false);

  Future<List<Workflow>> _ownedWorkflows() async =>
      (await repository.listWorkflows())
          .where((workflow) => workflow.ownerDeviceId == deviceId)
          .toList(growable: false);

  WorkCatalog _catalogFor(String? ownerDeviceId) {
    final localCatalog = catalog;
    if (localCatalog != null) return localCatalog;
    return _receivedCatalogs.putIfAbsent(ownerDeviceId ?? '', WorkCatalog.new);
  }

  WorkRequest _request(
    ActentMessage message,
    Work work, {
    required String sourceDeviceId,
    String? targetDeviceId,
    String? workflowExecutionId,
    String? workflowStepId,
    String? workflowOwnerDeviceId,
  }) {
    final now = DateTime.now().toUtc();
    return WorkRequest(
      requestId: 'request-${now.microsecondsSinceEpoch}',
      message: message,
      workId: work.id,
      workRevision: work.revision,
      sourceDeviceId: sourceDeviceId,
      targetDeviceId: targetDeviceId ?? deviceId,
      createdAt: now,
      expiresAt: now.add(work.timeout),
      workflowExecutionId: workflowExecutionId,
      workflowStepId: workflowStepId,
      workflowOwnerDeviceId: workflowOwnerDeviceId,
    );
  }

  String _errorCode(String reason) => switch (reason) {
    'disabled' => 'work_unavailable',
    'revision changed' => 'work_changed',
    'content type is not accepted' => 'content_type_rejected',
    'no runner registered' => 'runner_unavailable',
    _ => 'work_unavailable',
  };
}

int _requiredInt(Object? value, String field) {
  if (value is! int) throw WorkCatalogException('$field must be an integer');
  return value;
}

class _PublishedCatalog {
  _PublishedCatalog({
    required this.revision,
    required Iterable<Work> works,
    required Iterable<Workflow> workflows,
  }) : works = List<Work>.unmodifiable(works),
       workflows = List<Workflow>.unmodifiable(workflows);

  final int revision;
  final List<Work> works;
  final List<Workflow> workflows;
}
