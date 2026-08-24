import 'dart:async';
import 'dart:convert';

import 'package:actent/features/actent_core/actent_models.dart';
import 'package:actent/features/actent_core/actent_router.dart';
import 'package:actent/features/actent_core/actent_store.dart';
import 'package:actent/features/actent_core/actent_transport.dart';
import 'package:actent/features/messaging/message_connection.dart';
import 'package:actent/features/messaging/messaging_packet.dart';
import 'package:actent/features/messaging/packet_crypto.dart';
import 'package:actent/features/work/work_runner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('transport startup does not wait for ntfy cache polling', () async {
    final identity = await PacketIdentity.generate();
    final repository = ActentRepository(MemoryActentJsonStore());
    final poller = _HangingPacketPoller();
    final service = ActentTransportService(
      deviceId: 'local-device',
      identity: identity,
      repository: repository,
      relay: ActentRelaySettings(
        server: Uri.parse('https://relay.example'),
        controlTopic: 'local-topic',
        blobTopic: 'local-blob-topic',
        token: 'tk_test',
      ),
      subscriptionFor: (_, _, token) => _IdlePacketSubscription(token),
      pollerFor: (_, _, _) => poller,
      presenceInterval: const Duration(days: 1),
      relayReconnectDelay: const Duration(days: 1),
      relayPollInterval: const Duration(days: 1),
    );
    final router = ActentRouter(
      deviceId: 'local-device',
      repository: repository,
      connection: service,
      queue: WorkQueueCoordinator(repository: repository),
    );

    await service.start(router).timeout(const Duration(seconds: 1));

    expect(poller.started, isTrue);
    await service.stop();
  });

  test('transport starts ntfy anonymously when token is absent', () async {
    final identity = await PacketIdentity.generate();
    final repository = ActentRepository(MemoryActentJsonStore());
    final poller = _HangingPacketPoller();
    String? subscriptionToken = 'not-called';
    String? pollerToken = 'not-called';
    final service = ActentTransportService(
      deviceId: 'local-device',
      identity: identity,
      repository: repository,
      relay: ActentRelaySettings(
        server: Uri.parse('https://relay.example'),
        controlTopic: 'local-topic',
        blobTopic: 'local-blob-topic',
      ),
      subscriptionFor: (_, _, token) {
        subscriptionToken = token;
        return _IdlePacketSubscription(token);
      },
      pollerFor: (_, _, token) {
        pollerToken = token;
        return poller;
      },
      presenceInterval: const Duration(days: 1),
      relayReconnectDelay: const Duration(days: 1),
      relayPollInterval: const Duration(days: 1),
    );
    final router = ActentRouter(
      deviceId: 'local-device',
      repository: repository,
      connection: service,
      queue: WorkQueueCoordinator(repository: repository),
    );

    await service.start(router).timeout(const Duration(seconds: 1));

    expect(subscriptionToken, isNull);
    expect(pollerToken, isNull);
    expect(poller.started, isTrue);
    await service.stop();
  });

  test('transport publishes anonymously when token is absent', () async {
    final local = await PacketIdentity.generate();
    final remote = await PacketIdentity.generate();
    final repository = ActentRepository(MemoryActentJsonStore());
    await repository.saveDevice(
      Device(
        id: 'remote-device',
        displayName: 'Remote',
        platform: 'ios',
        publicKey: base64UrlEncode(remote.publicKey.bytes),
        endpoint: const {
          'relayUrl': 'https://relay.example',
          'relayTopic': 'remote-topic',
          'relayBlobTopic': 'remote-blob-topic',
        },
      ),
    );
    final publisher = _CapturePublisher();
    String? publisherToken = 'not-called';
    final service = ActentTransportService(
      deviceId: 'local-device',
      identity: local,
      repository: repository,
      relay: ActentRelaySettings(
        server: Uri.parse('https://relay.example'),
        controlTopic: 'local-topic',
        blobTopic: 'local-blob-topic',
      ),
      relayPublisherFor: (_, token) {
        publisherToken = token;
        return publisher;
      },
    );

    await service.send(
      recipientId: 'remote-device',
      payload: const {'type': 'presencePing', 'schemaVersion': 1},
    );

    expect(publisherToken, isNull);
    expect(publisher.topics, ['remote-topic']);
  });
}

class _IdlePacketSubscription extends NtfyPacketSubscription {
  _IdlePacketSubscription([String? token])
    : super(
        server: Uri.parse('https://relay.example'),
        channel: 'local-topic',
        credentials: token == null ? null : NtfyCredentials(token),
      );

  @override
  Stream<MessagingPacket> listen() => const Stream<MessagingPacket>.empty();
}

class _HangingPacketPoller extends NtfyPacketPoller {
  _HangingPacketPoller()
    : super(
        server: Uri.parse('https://relay.example'),
        channel: 'local-topic',
        credentials: NtfyCredentials('tk_test'),
      );

  bool started = false;
  final Completer<List<MessagingPacket>> _result =
      Completer<List<MessagingPacket>>();

  @override
  Future<List<MessagingPacket>> poll({required DateTime since}) {
    started = true;
    return _result.future;
  }
}

class _CapturePublisher implements RelayPublisher {
  final List<String> topics = [];

  @override
  Future<void> publish(String topic, String body) async {
    topics.add(topic);
  }
}
