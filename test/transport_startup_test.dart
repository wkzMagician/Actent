import 'dart:async';

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
      subscriptionFor: (_, _, _) => _IdlePacketSubscription(),
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
}

class _IdlePacketSubscription extends NtfyPacketSubscription {
  _IdlePacketSubscription()
    : super(
        server: Uri.parse('https://relay.example'),
        channel: 'local-topic',
        credentials: NtfyCredentials('tk_test'),
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
