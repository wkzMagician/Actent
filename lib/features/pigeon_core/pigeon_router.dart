import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import '../messaging/message_connection.dart';
import '../messaging/messaging_packet.dart';
import '../messaging/packet_crypto.dart';
import '../messaging/seen_packet_store.dart';
import 'pigeon_models.dart';
import 'pigeon_store.dart';
import 'work_catalog.dart';
import '../work/work_runner.dart';

abstract interface class MessageConnection {
  Future<void> send({
    required String recipientId,
    required Map<String, Object?> payload,
  });
}

class DuplicatePigeonPacketException implements Exception {
  const DuplicatePigeonPacketException(this.packetId);

  final String packetId;

  @override
  String toString() => 'Pigeon packet already processed: $packetId';
}

/// Encrypts Pigeon protocol payloads before handing them to the generic
/// messaging capability. The capability never sees Work or Pigeon payload
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
      throw DuplicatePigeonPacketException(packet.packetId);
    }
    final plaintext = await _crypto.decrypt(
      recipient: localIdentity,
      senderPublicKey: remotePublicKey,
      packet: packet,
    );
    final decoded = jsonDecode(utf8.decode(plaintext));
    if (decoded is! Map) {
      throw const PacketValidationException('Pigeon payload must be an object');
    }
    if (decoded['schemaVersion'] != pigeonSchemaVersion) {
      throw const PacketValidationException(
        'unsupported Pigeon payload version',
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

class PigeonRouter {
  PigeonRouter({
    required this.deviceId,
    required this.repository,
    required this.connection,
    required this.queue,
    this.catalog,
  }) {
    queue.addReceiptListener(_forwardReceipt);
  }

  final String deviceId;
  final PigeonRepository repository;
  final MessageConnection connection;
  final WorkQueueCoordinator queue;
  final WorkCatalog? catalog;
  final Map<String, WorkCatalog> _receivedCatalogs = {};
  final Map<String, _PublishedCatalog> _publishedCatalogs = {};

  Future<void> _forwardReceipt(WorkReceipt receipt) async {
    final request = await repository.getRequest(receipt.requestId);
    if (request == null || request.sourceDeviceId == deviceId) return;
    await connection.send(
      recipientId: request.sourceDeviceId,
      payload: <String, Object?>{
        'type': 'workReceipt',
        'schemaVersion': pigeonSchemaVersion,
        'receipt': receipt.toJson(),
      },
    );
  }

  Future<WorkRequest> route(
    PigeonMessage message,
    Work work, {
    String? targetDeviceId,
  }) async {
    if (!work.enabled) throw WorkUnavailableException(work.id, 'disabled');
    if (!work.accepts(message)) {
      throw WorkUnavailableException(work.id, 'content type is not accepted');
    }
    await repository.saveMessage(message);
    final target = targetDeviceId ?? work.ownerDeviceId;
    if (target == deviceId) {
      final request = _request(message, work, sourceDeviceId: deviceId);
      await queue.enqueue(work, request);
      return request;
    }
    final request = _request(
      message,
      work,
      sourceDeviceId: deviceId,
      targetDeviceId: target,
    );
    await repository.saveRequest(request);
    await connection.send(
      recipientId: target,
      payload: <String, Object?>{
        'type': 'workRequest',
        'schemaVersion': pigeonSchemaVersion,
        'request': request.toJson(),
      },
    );
    return request;
  }

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
          throw const PigeonValidationException(
            'receipt',
            'receipt is not authorized for the authenticated sender',
          );
        }
      }
      await repository.saveReceipt(receipt);
      return receipt;
    }
    if (payload['type'] != 'workRequest') {
      throw const PigeonValidationException(
        'type',
        'unsupported Pigeon payload type',
      );
    }
    final request = WorkRequest.fromJson(payload['request']);
    if (senderId != null && request.sourceDeviceId != senderId) {
      throw const PigeonValidationException(
        'request.sourceDeviceId',
        'does not match authenticated packet sender',
      );
    }
    if (request.targetDeviceId != deviceId) {
      throw const PigeonValidationException(
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
          'schemaVersion': pigeonSchemaVersion,
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
      throw const PigeonValidationException(
        'requestId',
        'must be a non-empty string',
      );
    }
    if (sourceDeviceId is! String || sourceDeviceId.isEmpty) {
      throw const PigeonValidationException(
        'sourceDeviceId',
        'must be a non-empty string',
      );
    }
    if (authenticatedSenderId != null &&
        authenticatedSenderId != sourceDeviceId) {
      throw const PigeonValidationException(
        'sourceDeviceId',
        'does not match authenticated packet sender',
      );
    }
    final request = await repository.getRequest(requestId);
    if (request == null ||
        request.targetDeviceId != deviceId ||
        request.sourceDeviceId != sourceDeviceId) {
      throw const PigeonValidationException(
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
          'schemaVersion': pigeonSchemaVersion,
          'receipt': receipt.toJson(),
        },
      );

  Future<void> receiveCatalogSnapshot(
    Object? value, {
    String? ownerDeviceId,
  }) async {
    final incoming = WorkCatalog.fromSnapshotJson(value);
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
      await repository.deleteWork(workId);
    }
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
    for (final workId in removed) {
      await repository.deleteWork(workId);
    }
  }

  /// Sends the current non-local Work catalog to a newly paired device. The
  /// transport sees only a generic encrypted payload; Work remains a Pigeon
  /// concern inside this router.
  Future<void> sendCatalogSnapshot(String recipientId) async {
    final works = await _ownedWorks();
    final previous = _publishedCatalogs[recipientId];
    final revision = previous == null ? 1 : previous.revision + 1;
    await connection.send(
      recipientId: recipientId,
      payload: <String, Object?>{
        'type': 'catalogSnapshot',
        'schemaVersion': pigeonSchemaVersion,
        'catalog': <String, Object?>{
          'revision': revision,
          'works': works.map((work) => work.toJson()).toList(),
        },
      },
    );
    _publishedCatalogs[recipientId] = _PublishedCatalog(
      revision: revision,
      works: works,
    );
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
    if (upserts.isEmpty && removed.isEmpty) return;
    final nextRevision = previous.revision + 1;
    await connection.send(
      recipientId: recipientId,
      payload: <String, Object?>{
        'type': 'catalogDelta',
        'schemaVersion': pigeonSchemaVersion,
        'catalog': <String, Object?>{
          'baseRevision': previous.revision,
          'nextRevision': nextRevision,
          'upserts': upserts.map((work) => work.toJson()).toList(),
          'removedWorkIds': removed,
        },
      },
    );
    _publishedCatalogs[recipientId] = _PublishedCatalog(
      revision: nextRevision,
      works: current,
    );
  }

  Future<List<Work>> _ownedWorks() async => (await repository.listWorks())
      .where((work) => work.ownerDeviceId == deviceId)
      .toList(growable: false);

  WorkCatalog _catalogFor(String? ownerDeviceId) {
    final localCatalog = catalog;
    if (localCatalog != null) return localCatalog;
    return _receivedCatalogs.putIfAbsent(ownerDeviceId ?? '', WorkCatalog.new);
  }

  WorkRequest _request(
    PigeonMessage message,
    Work work, {
    required String sourceDeviceId,
    String? targetDeviceId,
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
  _PublishedCatalog({required this.revision, required Iterable<Work> works})
    : works = List<Work>.unmodifiable(works);

  final int revision;
  final List<Work> works;
}
