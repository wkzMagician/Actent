import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pengion/features/messaging/attachment_chunks.dart';
import 'package:pengion/features/messaging/attachment_transfer_store.dart';
import 'package:pengion/features/messaging/message_connection.dart';
import 'package:pengion/features/messaging/messaging_packet.dart';
import 'package:pengion/features/messaging/packet_crypto.dart';
import 'package:pengion/features/messaging/seen_packet_store.dart';
import 'package:pengion/features/pigeon_core/pigeon_models.dart';
import 'package:pengion/features/pigeon_core/pigeon_router.dart';

void main() {
  test('encrypts and authenticates packets with X25519 and AES-GCM', () async {
    final sender = await PacketIdentity.generate();
    final recipient = await PacketIdentity.generate();
    final crypto = PacketCrypto();
    final packet = await crypto.encrypt(
      sender: sender,
      recipientPublicKey: recipient.publicKey,
      packetId: 'packet-1',
      senderId: 'sender',
      recipientId: 'recipient',
      plaintext: utf8.encode('secret payload'),
      createdAt: DateTime.utc(2026, 1, 1),
    );

    const validator = PacketValidator(recipientId: 'recipient');
    validator.validate(packet);
    expect(
      utf8.decode(
        await crypto.decrypt(
          recipient: recipient,
          senderPublicKey: sender.publicKey,
          packet: packet,
        ),
      ),
      'secret payload',
    );

    final tampered = MessagingPacket(
      packetId: packet.packetId,
      senderId: packet.senderId,
      recipientId: packet.recipientId,
      createdAt: packet.createdAt,
      ciphertext: packet.ciphertext,
      nonce: packet.nonce,
      mac: Uint8List.fromList([...packet.mac]..[0] ^= 1),
    );
    expect(
      () => crypto.decrypt(
        recipient: recipient,
        senderPublicKey: sender.publicKey,
        packet: tampered,
      ),
      throwsA(isA<PacketValidationException>()),
    );
  });

  test('deduplicates packets for the configured retention window', () {
    var now = DateTime.utc(2026, 1, 1);
    final store = SeenPacketStore(
      retention: const Duration(days: 7),
      clock: () => now,
    );
    expect(store.remember('packet-1'), isTrue);
    expect(store.remember('packet-1'), isFalse);
    now = now.add(const Duration(days: 8));
    expect(store.remember('packet-1'), isTrue);
  });

  test('reassembles only complete and intact attachment chunks', () {
    final bytes = Uint8List.fromList(
      List<int>.generate(701, (index) => index % 251),
    );
    const chunker = AttachmentChunker(chunkSize: 100);
    final manifest = chunker.manifest(
      messageId: 'message-1',
      attachmentId: 'attachment-1',
      name: 'payload.bin',
      mimeType: 'application/octet-stream',
      plaintext: bytes,
    );
    final chunks = chunker.split(manifest: manifest, encryptedBytes: bytes);
    final reassembler = AttachmentReassembler(manifest);
    for (final chunk in chunks.reversed) {
      reassembler.add(chunk);
    }
    expect(reassembler.isComplete, isTrue);
    expect(reassembler.assemble(), bytes);

    final incomplete = AttachmentReassembler(manifest);
    for (final chunk in chunks.take(chunks.length - 1)) {
      incomplete.add(chunk);
    }
    expect(incomplete.isComplete, isFalse);
    expect(incomplete.assemble, throwsStateError);
  });

  test('encrypts and authenticates every attachment chunk', () async {
    final bytes = Uint8List.fromList(List<int>.generate(333, (index) => index));
    const chunker = AttachmentChunker(chunkSize: 64);
    final manifest = chunker.manifest(
      messageId: 'message-2',
      attachmentId: 'attachment-2',
      name: 'secret.bin',
      mimeType: 'application/octet-stream',
      plaintext: bytes,
    );
    final key = SecretKey(List<int>.filled(32, 7));
    final chunks = await chunker.encryptAndSplit(
      manifest: manifest,
      plaintext: bytes,
      key: key,
    );
    final reassembler = AttachmentReassembler(manifest);
    for (final chunk in chunks.reversed) {
      reassembler.add(chunk);
    }
    expect(await reassembler.decryptAndAssemble(key: key), bytes);
    chunks.first.ciphertext[0] ^= 1;
    expect(() async {
      final bad = AttachmentReassembler(manifest);
      for (final chunk in chunks) {
        bad.add(chunk);
      }
      await bad.decryptAndAssemble(key: key);
    }, throwsStateError);
  });

  test('expires incomplete attachment transfers after 24 hours', () {
    var now = DateTime.utc(2026, 1, 1);
    final store = MemoryAttachmentTransferStore(clock: () => now);
    const chunker = AttachmentChunker(chunkSize: 4);
    final manifest = chunker.manifest(
      messageId: 'message-3',
      attachmentId: 'attachment-3',
      name: 'partial.txt',
      mimeType: 'text/plain',
      plaintext: Uint8List.fromList([1, 2, 3, 4, 5]),
    );
    store.begin(manifest);
    final first = chunker
        .split(
          manifest: manifest,
          encryptedBytes: Uint8List.fromList([1, 2, 3, 4, 5]),
        )
        .first;
    store.add(first);
    expect(store.pendingCount, 1);
    now = now.add(const Duration(hours: 24, minutes: 1));
    expect(store.purgeExpired(), 1);
    expect(store.pendingCount, 0);
  });

  test('uses LAN first and retries relay after a LAN failure', () async {
    final lan = _FakeConnection()..fail = true;
    final relay = _FakeRelay(failuresBeforeSuccess: 2);
    final packet = _packet();
    final sender = RoutedPacketSender(
      lan: lan,
      relay: relay,
      relayTopic: 'topic',
      policy: const RetryPolicy(maxAttempts: 3),
      wait: (_) async {},
    );

    await sender.send(packet);

    expect(lan.attempts, 1);
    expect(relay.attempts, 3);
  });

  test('frames LAN packets with an exact length prefix', () {
    final packet = _packet();
    final frame = LanPacketFrame.encode(packet);

    expect(LanPacketFrame.decode(frame).packetId, packet.packetId);
    expect(
      () => LanPacketFrame.decode(frame.sublist(0, frame.length - 1)),
      throwsA(isA<PacketValidationException>()),
    );
  });

  test(
    'publishes ntfy packets with auth and exposes retry-after errors',
    () async {
      final client = _FakeHttpClient(statusCode: 202);
      final publisher = NtfyRelayPublisher(
        Uri.parse('https://relay.example/base'),
        client: client,
      );
      await publisher.publish(
        'private-topic',
        '{"packet":1}',
        authorization: 'Bearer secret',
      );
      expect(
        client.lastRequest!.url.toString(),
        'https://relay.example/base/private-topic',
      );
      expect(client.lastRequest!.headers['authorization'], 'Bearer secret');

      client.statusCode = 429;
      client.responseHeaders = const {'retry-after': '4'};
      try {
        await publisher.publish('private-topic', '{}');
        fail('expected relay error');
      } on RelayPublishException catch (error) {
        expect(error.isRetryable, isTrue);
        expect(error.retryAfter, const Duration(seconds: 4));
      }
    },
  );

  test(
    'Pigeon protocol payloads are encrypted before generic packet transport',
    () async {
      final senderIdentity = await PacketIdentity.generate();
      final recipientIdentity = await PacketIdentity.generate();
      final transport = MemoryPacketConnection();
      final sender = EncryptedMessageConnection(
        transport: transport,
        localIdentity: senderIdentity,
        remotePublicKey: recipientIdentity.publicKey,
        senderId: 'sender',
        recipientId: 'recipient',
      );
      final recipient = EncryptedMessageConnection(
        transport: MemoryPacketConnection(),
        localIdentity: recipientIdentity,
        remotePublicKey: senderIdentity.publicKey,
        senderId: 'recipient',
        recipientId: 'recipient',
      );

      await sender.send(
        recipientId: 'recipient',
        payload: const <String, Object?>{
          'schemaVersion': pigeonSchemaVersion,
          'type': 'workRequest',
        },
      );
      final payload = await recipient.receive(
        transport.sent.single,
        expectedSenderId: 'sender',
      );

      expect(payload['type'], 'workRequest');
      expect(
        transport.sent.single.ciphertext,
        isNot(utf8.encode('workRequest')),
      );
      expect(
        () => recipient.receive(
          transport.sent.single,
          expectedSenderId: 'sender',
        ),
        throwsA(isA<DuplicatePigeonPacketException>()),
      );
    },
  );
}

MessagingPacket _packet() => MessagingPacket(
  packetId: 'packet-1',
  senderId: 'sender',
  recipientId: 'recipient',
  createdAt: DateTime.utc(2026, 1, 1),
  ciphertext: Uint8List.fromList([1]),
  nonce: Uint8List(12),
  mac: Uint8List(16),
);

class _FakeConnection implements PacketConnection {
  var attempts = 0;
  var fail = false;

  @override
  Future<void> send(MessagingPacket packet) async {
    attempts++;
    if (fail) throw StateError('LAN unavailable');
  }
}

class _FakeHttpClient extends http.BaseClient {
  _FakeHttpClient({required this.statusCode});

  int statusCode;
  Map<String, String> responseHeaders = const {};
  http.BaseRequest? lastRequest;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    lastRequest = request;
    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode('response')),
      statusCode,
      headers: responseHeaders,
      request: request,
    );
  }
}

class _FakeRelay implements RelayPublisher {
  _FakeRelay({required this.failuresBeforeSuccess});

  final int failuresBeforeSuccess;
  var attempts = 0;

  @override
  Future<void> publish(
    String topic,
    String body, {
    String? authorization,
  }) async {
    attempts++;
    if (attempts <= failuresBeforeSuccess) {
      throw const RelayPublishException('temporary', statusCode: 500);
    }
  }
}
