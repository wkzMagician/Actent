import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:actent/features/messaging/attachment_chunks.dart';
import 'package:actent/features/messaging/message_connection.dart';
import 'package:actent/features/messaging/messaging_packet.dart';
import 'package:actent/features/messaging/packet_crypto.dart';
import 'package:actent/features/actent_core/actent_models.dart';
import 'package:actent/features/actent_core/actent_store.dart';
import 'package:actent/features/actent_core/actent_router.dart';
import 'package:actent/features/actent_core/actent_transport.dart';
import 'package:actent/features/work/work_runner.dart';

void main() {
  test('encrypts a routed payload and falls back from LAN to relay', () async {
    final local = await PacketIdentity.generate();
    final remote = await PacketIdentity.generate();
    final repository = ActentRepository(MemoryActentJsonStore());
    final remoteId = 'remote-device';
    await repository.saveDevice(
      Device(
        id: remoteId,
        displayName: 'Remote',
        platform: 'windows',
        publicKey: base64UrlEncode(remote.publicKey.bytes),
        endpoint: {
          'relayUrl': 'https://relay.example',
          'relayTopic': 'remote-topic',
        },
      ),
    );
    final publisher = _CapturePublisher();
    final service = ActentTransportService(
      deviceId: 'local-device',
      identity: local,
      repository: repository,
      relay: ActentRelaySettings(
        server: Uri.parse('https://relay.example'),
        topic: 'local-topic',
      ),
      relayPublisherFor: (_) => publisher,
    );

    await service.send(
      recipientId: remoteId,
      payload: const <String, Object?>{
        'type': 'workRequest',
        'schemaVersion': actentSchemaVersion,
      },
    );

    expect(publisher.topic, 'remote-topic');
    expect(
      (await _decodePublishedPayloads(
        publisher,
        remote: remote,
        senderPublicKey: local.publicKey,
      )).single,
      {'type': 'workRequest', 'schemaVersion': actentSchemaVersion},
    );
  });

  test(
    'rejects an authenticated packet whose request source is forged',
    () async {
      final repository = ActentRepository(MemoryActentJsonStore());
      final work = Work(
        id: 'work',
        revision: 1,
        name: 'Work',
        ownerDeviceId: 'target',
        acceptedContentTypes: const {ActentContentType.text},
      );
      await repository.saveWork(work);
      final queue = WorkQueueCoordinator(repository: repository)
        ..register(work.id, const NullWorkRunner());
      final router = ActentRouter(
        deviceId: 'target',
        repository: repository,
        connection: FakeMessageConnection(),
        queue: queue,
      );
      final message = ActentMessage(
        id: 'message',
        traceId: 'trace',
        createdAt: DateTime.now().toUtc(),
        source: const ActentSource(kind: 'test'),
        content: ActentContent(
          type: ActentContentType.text,
          data: const {'text': 'hello'},
        ),
      );
      final request = WorkRequest(
        requestId: 'request',
        message: message,
        workId: work.id,
        workRevision: work.revision,
        sourceDeviceId: 'claimed-source',
        targetDeviceId: 'target',
        createdAt: DateTime.now().toUtc(),
        expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 1)),
      );
      expect(
        () => router.receive({
          'type': 'workRequest',
          'schemaVersion': actentSchemaVersion,
          'request': request.toJson(),
        }, authenticatedSenderId: 'actual-source'),
        throwsA(isA<ActentValidationException>()),
      );
    },
  );

  test(
    'packages private attachments as authenticated manifest chunks',
    () async {
      final root = await Directory.systemTemp.createTemp('actent-transport-');
      addTearDown(() => root.delete(recursive: true));
      final attachmentDirectory = Directory('${root.path}/message/attachment')
        ..createSync(recursive: true);
      final file = File('${attachmentDirectory.path}/payload')
        ..writeAsBytesSync(utf8.encode('private attachment'));
      final local = await PacketIdentity.generate();
      final remote = await PacketIdentity.generate();
      final repository = ActentRepository(MemoryActentJsonStore());
      await repository.saveDevice(
        Device(
          id: 'remote',
          displayName: 'Remote',
          platform: 'windows',
          publicKey: base64UrlEncode(remote.publicKey.bytes),
          endpoint: {
            'relayUrl': 'https://relay.example',
            'relayTopic': 'remote-topic',
          },
        ),
      );
      final publisher = _CapturePublisher();
      final service = ActentTransportService(
        deviceId: 'local',
        identity: local,
        repository: repository,
        relay: ActentRelaySettings(
          server: Uri.parse('https://relay.example'),
          topic: 'local-topic',
        ),
        attachmentRoot: root,
        relayPublisherFor: (_) => publisher,
      );
      final message = ActentMessage(
        id: 'message',
        traceId: 'trace',
        createdAt: DateTime.now().toUtc(),
        source: const ActentSource(kind: 'test'),
        content: ActentContent(
          type: ActentContentType.file,
          data: const {'name': 'payload'},
        ),
        attachments: [
          ActentAttachment(
            id: 'attachment',
            name: 'payload',
            mimeType: 'text/plain',
            byteLength: file.lengthSync(),
            handle: file.path,
          ),
        ],
      );
      final request = WorkRequest(
        requestId: 'request',
        message: message,
        workId: 'work',
        workRevision: 1,
        sourceDeviceId: 'local',
        targetDeviceId: 'remote',
        createdAt: DateTime.now().toUtc(),
        expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 1)),
      );
      await service.send(
        recipientId: 'remote',
        payload: {
          'type': 'workRequest',
          'schemaVersion': actentSchemaVersion,
          'request': request.toJson(),
        },
      );
      final decoded = await _decodePublishedPayloads(
        publisher,
        remote: remote,
        senderPublicKey: local.publicKey,
      );
      final offer = decoded.firstWhere(
        (payload) => payload['type'] == 'workRequest',
      );
      final transfers = offer['attachmentTransfers'] as List;
      final transfer = Map<String, Object?>.from(transfers.single as Map);
      final manifest = AttachmentManifest.fromJson(transfer['manifest']);
      final transferKey = SecretKey(
        base64Url.decode(transfer['key'] as String),
      );
      final reassembler = AttachmentReassembler(manifest);
      for (final payload in decoded) {
        if (payload['type'] != 'attachmentChunk') continue;
        reassembler.add(AttachmentChunk.fromJson(payload['chunk']));
      }
      expect(
        utf8.decode(await reassembler.decryptAndAssemble(key: transferKey)),
        'private attachment',
      );
      final decodedRequest = Map<String, Object?>.from(offer['request'] as Map);
      final decodedMessage = Map<String, Object?>.from(
        decodedRequest['message'] as Map,
      );
      final decodedPayload = Map<String, Object?>.from(
        decodedMessage['payload'] as Map,
      );
      final decodedAttachment = Map<String, Object?>.from(
        (decodedPayload['attachments'] as List).single as Map,
      );
      expect(decodedAttachment['handle'], startsWith('actent-transfer://'));
    },
  );
}

class _CapturePublisher implements RelayPublisher {
  String? topic;
  final List<String> bodies = [];

  String? get body => bodies.isEmpty ? null : bodies.last;

  @override
  Future<void> publish(
    String topic,
    String body, {
    String? authorization,
  }) async {
    this.topic = topic;
    bodies.add(body);
  }
}

Future<List<Map<String, Object?>>> _decodePublishedPayloads(
  _CapturePublisher publisher, {
  required PacketIdentity remote,
  required SimplePublicKey senderPublicKey,
}) async {
  final values = <Map<String, Object?>>[];
  for (final body in publisher.bodies) {
    final plaintext = await PacketCrypto().decrypt(
      recipient: remote,
      senderPublicKey: senderPublicKey,
      packet: MessagingPacket.decode(body),
    );
    values.add(
      Map<String, Object?>.from(jsonDecode(utf8.decode(plaintext)) as Map),
    );
  }
  return values;
}
