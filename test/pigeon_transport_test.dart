import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pengion/features/messaging/attachment_chunks.dart';
import 'package:pengion/features/messaging/message_connection.dart';
import 'package:pengion/features/messaging/messaging_packet.dart';
import 'package:pengion/features/messaging/packet_crypto.dart';
import 'package:pengion/features/pigeon_core/pigeon_models.dart';
import 'package:pengion/features/pigeon_core/pigeon_store.dart';
import 'package:pengion/features/pigeon_core/pigeon_router.dart';
import 'package:pengion/features/pigeon_core/pigeon_transport.dart';
import 'package:pengion/features/work/work_runner.dart';

void main() {
  test('encrypts a routed payload and falls back from LAN to relay', () async {
    final local = await PacketIdentity.generate();
    final remote = await PacketIdentity.generate();
    final repository = PigeonRepository(MemoryPigeonJsonStore());
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
    final service = PigeonTransportService(
      deviceId: 'local-device',
      identity: local,
      repository: repository,
      relay: PigeonRelaySettings(
        server: Uri.parse('https://relay.example'),
        topic: 'local-topic',
      ),
      relayPublisherFor: (_) => publisher,
    );

    await service.send(
      recipientId: remoteId,
      payload: const <String, Object?>{
        'type': 'workRequest',
        'schemaVersion': pigeonSchemaVersion,
      },
    );

    expect(publisher.topic, 'remote-topic');
    final packet = MessagingPacket.decode(publisher.body!);
    final plaintext = await PacketCrypto().decrypt(
      recipient: remote,
      senderPublicKey: local.publicKey,
      packet: packet,
    );
    expect(jsonDecode(utf8.decode(plaintext)), {
      'type': 'workRequest',
      'schemaVersion': pigeonSchemaVersion,
    });
  });

  test(
    'rejects an authenticated packet whose request source is forged',
    () async {
      final repository = PigeonRepository(MemoryPigeonJsonStore());
      final work = Work(
        id: 'work',
        revision: 1,
        name: 'Work',
        ownerDeviceId: 'target',
        acceptedContentTypes: const {PigeonContentType.text},
      );
      await repository.saveWork(work);
      final queue = WorkQueueCoordinator(repository: repository)
        ..register(work.id, const NullWorkRunner());
      final router = PigeonRouter(
        deviceId: 'target',
        repository: repository,
        connection: FakeMessageConnection(),
        queue: queue,
      );
      final message = PigeonMessage(
        id: 'message',
        traceId: 'trace',
        createdAt: DateTime.now().toUtc(),
        source: const PigeonSource(kind: 'test'),
        content: PigeonContent(
          type: PigeonContentType.text,
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
          'schemaVersion': pigeonSchemaVersion,
          'request': request.toJson(),
        }, authenticatedSenderId: 'actual-source'),
        throwsA(isA<PigeonValidationException>()),
      );
    },
  );

  test(
    'packages private attachments as authenticated manifest chunks',
    () async {
      final root = await Directory.systemTemp.createTemp('pigeon-transport-');
      addTearDown(() => root.delete(recursive: true));
      final attachmentDirectory = Directory('${root.path}/message/attachment')
        ..createSync(recursive: true);
      final file = File('${attachmentDirectory.path}/payload')
        ..writeAsBytesSync(utf8.encode('private attachment'));
      final local = await PacketIdentity.generate();
      final remote = await PacketIdentity.generate();
      final repository = PigeonRepository(MemoryPigeonJsonStore());
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
      final service = PigeonTransportService(
        deviceId: 'local',
        identity: local,
        repository: repository,
        relay: PigeonRelaySettings(
          server: Uri.parse('https://relay.example'),
          topic: 'local-topic',
        ),
        attachmentRoot: root,
        relayPublisherFor: (_) => publisher,
      );
      final message = PigeonMessage(
        id: 'message',
        traceId: 'trace',
        createdAt: DateTime.now().toUtc(),
        source: const PigeonSource(kind: 'test'),
        content: PigeonContent(
          type: PigeonContentType.file,
          data: const {'name': 'payload'},
        ),
        attachments: [
          PigeonAttachment(
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
          'schemaVersion': pigeonSchemaVersion,
          'request': request.toJson(),
        },
      );
      final packet = MessagingPacket.decode(publisher.body!);
      final plaintext = await PacketCrypto().decrypt(
        recipient: remote,
        senderPublicKey: local.publicKey,
        packet: packet,
      );
      final decoded = Map<String, Object?>.from(
        jsonDecode(utf8.decode(plaintext)) as Map,
      );
      final transfers = decoded['attachmentTransfers'] as List;
      final transfer = Map<String, Object?>.from(transfers.single as Map);
      final manifest = AttachmentManifest.fromJson(transfer['manifest']);
      final transferKey = SecretKey(
        base64Url.decode(transfer['key'] as String),
      );
      final reassembler = AttachmentReassembler(manifest);
      for (final chunk in transfer['chunks'] as List) {
        reassembler.add(AttachmentChunk.fromJson(chunk));
      }
      expect(
        utf8.decode(await reassembler.decryptAndAssemble(key: transferKey)),
        'private attachment',
      );
      final decodedRequest = Map<String, Object?>.from(
        decoded['request'] as Map,
      );
      final decodedMessage = Map<String, Object?>.from(
        decodedRequest['message'] as Map,
      );
      final decodedAttachment = Map<String, Object?>.from(
        (decodedMessage['attachments'] as List).single as Map,
      );
      expect(decodedAttachment['handle'], startsWith('pigeon-transfer://'));
    },
  );
}

class _CapturePublisher implements RelayPublisher {
  String? topic;
  String? body;

  @override
  Future<void> publish(
    String topic,
    String body, {
    String? authorization,
  }) async {
    this.topic = topic;
    this.body = body;
  }
}
