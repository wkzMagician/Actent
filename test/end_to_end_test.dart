import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:actent/features/messaging/message_connection.dart';
import 'package:actent/features/messaging/messaging_packet.dart';
import 'package:actent/features/messaging/packet_crypto.dart';
import 'package:actent/features/actent_core/actent_models.dart';
import 'package:actent/features/actent_core/actent_router.dart';
import 'package:actent/features/actent_core/actent_store.dart';
import 'package:actent/features/work/desktop/desktop_script_runner.dart';
import 'package:actent/features/work/work_runner.dart';

void main() {
  test(
    'routes a shared message through encrypted remote Script Work',
    () async {
      final phoneRepository = ActentRepository(MemoryActentJsonStore());
      final desktopRepository = ActentRepository(MemoryActentJsonStore());
      final phoneIdentity = await PacketIdentity.generate();
      final desktopIdentity = await PacketIdentity.generate();
      final phoneToDesktopTransport = _DeliveringTransport();
      final desktopToPhoneTransport = _DeliveringTransport();
      final phoneConnection = EncryptedMessageConnection(
        transport: phoneToDesktopTransport,
        localIdentity: phoneIdentity,
        remotePublicKey: desktopIdentity.publicKey,
        senderId: 'phone',
        recipientId: 'desktop',
      );
      final desktopConnection = EncryptedMessageConnection(
        transport: desktopToPhoneTransport,
        localIdentity: desktopIdentity,
        remotePublicKey: phoneIdentity.publicKey,
        senderId: 'desktop',
        recipientId: 'phone',
      );
      final phoneInbound = EncryptedMessageConnection(
        transport: _DeliveringTransport(),
        localIdentity: phoneIdentity,
        remotePublicKey: desktopIdentity.publicKey,
        senderId: 'phone',
        recipientId: 'phone',
      );
      final desktopInbound = EncryptedMessageConnection(
        transport: _DeliveringTransport(),
        localIdentity: desktopIdentity,
        remotePublicKey: phoneIdentity.publicKey,
        senderId: 'desktop',
        recipientId: 'desktop',
      );
      phoneToDesktopTransport.connect(desktopInbound);
      desktopToPhoneTransport.connect(phoneInbound);
      final phoneQueue = WorkQueueCoordinator(repository: phoneRepository);
      final desktopQueue = WorkQueueCoordinator(repository: desktopRepository)
        ..register(
          'remote-script',
          DesktopScriptRunner(
            config: DesktopScriptConfig(executable: 'fake-worker'),
            launcher: _E2eScriptLauncher(),
          ),
        );
      final phoneRouter = ActentRouter(
        deviceId: 'phone',
        repository: phoneRepository,
        connection: phoneConnection,
        queue: phoneQueue,
      );
      final desktopRouter = ActentRouter(
        deviceId: 'desktop',
        repository: desktopRepository,
        connection: desktopConnection,
        queue: desktopQueue,
      );
      phoneToDesktopTransport.deliver = (payload) async {
        await desktopRouter.receive(payload);
      };
      desktopToPhoneTransport.deliver = (payload) async {
        await phoneRouter.receive(payload);
      };

      final work = Work(
        id: 'remote-script',
        revision: 1,
        name: 'Remote Script',
        ownerDeviceId: 'desktop',
        acceptedContentTypes: ActentContentType.values.toSet(),
        platformBindings: const {
          'kind': 'desktop-script',
          'executable': 'fake-worker',
          'arguments': <String>[],
          'environment': <String, String>{},
        },
      );
      await desktopRepository.saveWork(work);
      final message = ActentMessage(
        id: 'shared-1',
        traceId: 'trace-1',
        createdAt: DateTime.now().toUtc(),
        source: const ActentSource(kind: 'share', deviceId: 'phone'),
        content: ActentContent(
          type: ActentContentType.text,
          data: const {'text': 'hello desktop'},
        ),
      );

      await phoneRouter.route(message, work, targetDeviceId: 'desktop');
      await _pumpUntil(() async {
        final receipts = await phoneRepository.listReceipts();
        return receipts.any(
          (receipt) =>
              receipt.requestId.startsWith('request-') &&
              receipt.status == WorkReceiptStatus.succeeded,
        );
      });

      expect(phoneToDesktopTransport.sent.single.ciphertext, isNotEmpty);
      expect(
        phoneToDesktopTransport.sent.single.encode(),
        isNot(contains('hello desktop')),
      );
      final scriptInput = jsonDecode(
        utf8.decode(_E2eScriptLauncher.input),
      ) as Map<String, Object?>;
      expect(scriptInput['type'], 'text');
      expect(scriptInput['data'], {'text': 'hello desktop'});
      expect(scriptInput, isNot(contains('id')));
      expect((await desktopRepository.listMessages()).single.id, 'shared-1');
      expect(
        (await desktopRepository.listReceipts()).single.status,
        WorkReceiptStatus.succeeded,
      );
      expect(
        (await phoneRepository.listReceipts()).single.status,
        WorkReceiptStatus.succeeded,
      );
    },
  );
}

class _DeliveringTransport implements PacketConnection {
  Future<void> Function(Map<String, Object?> payload)? deliver;
  final List<MessagingPacket> sent = [];

  @override
  Future<void> send(MessagingPacket packet) async {
    sent.add(packet);
    final handler = deliver;
    if (handler == null) {
      throw StateError('loopback delivery is not configured');
    }
    final connection = _lastConnection;
    if (connection == null) {
      throw StateError('loopback receiver is not configured');
    }
    await handler(
      await connection.receive(packet, expectedSenderId: packet.senderId),
    );
  }

  EncryptedMessageConnection? _lastConnection;

  void connect(EncryptedMessageConnection connection) =>
      _lastConnection = connection;
}

class _E2eScriptLauncher implements ScriptProcessLauncher {
  static final List<int> input = [];

  @override
  Future<ScriptProcess> start(DesktopScriptConfig config) async =>
      _E2eScriptProcess();
}

class _E2eScriptProcess implements ScriptProcess {
  @override
  Stream<List<int>> get stdout => const Stream<List<int>>.empty();

  @override
  Stream<List<int>> get stderr => const Stream<List<int>>.empty();

  @override
  Future<int> get exitCode => Future<int>.value(0);

  @override
  Future<void> writeStdin(List<int> bytes) async {
    _E2eScriptLauncher.input
      ..clear()
      ..addAll(bytes);
  }

  @override
  Future<void> closeStdin() async {}

  @override
  Future<void> terminateTree() async {}
}

Future<void> _pumpUntil(Future<bool> Function() condition) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    if (await condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('timed out waiting for end-to-end receipt');
}
