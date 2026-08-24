import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:dartloom_storage/dartloom_storage.dart';

import '../messaging/message_connection.dart';
import '../messaging/attachment_chunks.dart';
import '../messaging/messaging_packet.dart';
import '../messaging/packet_crypto.dart';
import '../messaging/seen_packet_store.dart';
import 'actent_models.dart';
import 'actent_attachment_transfer.dart';
import 'actent_router.dart';
import 'actent_store.dart';
import 'actent_transport_state.dart';
import 'secret_repository.dart';

enum PeerConnectionState { connected, disconnected }

class PeerConnectionStatus {
  const PeerConnectionStatus({
    required this.deviceId,
    required this.state,
    this.lastSeen,
  });

  final String deviceId;
  final PeerConnectionState state;
  final DateTime? lastSeen;
}

/// Settings shared by the relay publisher and the local subscription.
/// Authentication is intentionally kept outside the JSON repository.
class ActentRelaySettings {
  const ActentRelaySettings({
    required this.server,
    required this.controlTopic,
    required this.blobTopic,
    this.token,
  });

  final Uri server;
  final String controlTopic;
  final String blobTopic;
  final String? token;

  static Future<ActentRelaySettings> load(
    ActentSecretRepository secrets,
  ) async {
    if (await secrets.read('relay.protocol.version') != '2') {
      await secrets.remove('relay.inbox.topic');
      await secrets.remove('relay.authorization');
      await secrets.remove('relay.server');
      await secrets.write('relay.protocol.version', '2');
    }
    var controlTopic = await secrets.read('relay.v2.controlTopic');
    if (controlTopic == null || controlTopic.length < 24) {
      controlTopic = _newTopic();
      await secrets.write('relay.v2.controlTopic', controlTopic);
    }
    var blobTopic = await secrets.read('relay.v2.blobTopic');
    if (blobTopic == null || blobTopic.length < 24) {
      blobTopic = _newTopic();
      await secrets.write('relay.v2.blobTopic', blobTopic);
    }
    final serverText =
        await secrets.read('relay.v2.server') ??
        'https://actent.wkzmagician.top';
    final server = Uri.tryParse(serverText);
    if (server == null || !server.hasScheme || server.host.isEmpty) {
      throw StateError('invalid relay.v2.server setting');
    }
    return ActentRelaySettings(
      server: server,
      controlTopic: controlTopic,
      blobTopic: blobTopic,
      token: await secrets.read('relay.v2.token'),
    );
  }
}

/// Application-owned connection that turns a Actent payload into an encrypted
/// generic Packet and chooses LAN before relay for a paired device.
///
/// The router remains unaware of HTTP, WebSocket, TLS, or device endpoint
/// formats; those details are kept here at the composition boundary.
class ActentTransportService implements MessageConnection {
  ActentTransportService({
    required this.deviceId,
    required this.identity,
    required this.repository,
    required this.relay,
    this.attachmentRoot,
    this.attachmentStore,
    this.maxMessageBytes,
    this.seenPacketRetention = const Duration(days: 7),
    this.lanServerConfig,
    SeenPacketStore? seenPackets,
    this.lanConnectionFor,
    this.lanBlobStoreFor,
    this.relayPublisherFor,
    this.subscriptionFor,
    this.pollerFor,
    this.blobStoreFor,
    this.readAttachment,
    this.writeAttachment,
    this.presenceInterval = const Duration(seconds: 30),
    this.presenceTimeout = const Duration(seconds: 75),
    ActentTransportStateStore? stateStore,
  }) : _seenPackets =
           seenPackets ?? SeenPacketStore(retention: seenPacketRetention),
       _stateStore =
           stateStore ??
           ActentTransportStateStore(
             repository.store,
             retention: seenPacketRetention,
           );

  final String deviceId;
  final PacketIdentity identity;
  final ActentRepository repository;
  final ActentRelaySettings relay;
  final Directory? attachmentRoot;
  final ObjectStore? attachmentStore;

  /// Optional application policy. A null value means that Actent does not
  /// impose an arbitrary whole-message limit; the transport may still reject
  /// a packet when its selected relay or LAN implementation cannot carry it.
  final int? maxMessageBytes;
  final Duration seenPacketRetention;
  final ActentLanServerConfig? lanServerConfig;
  final PacketConnection Function(Device device)? lanConnectionFor;
  final BlobStore Function(Device device)? lanBlobStoreFor;
  final RelayPublisher Function(Uri server, String token)? relayPublisherFor;
  final NtfyPacketSubscription Function(Uri server, String topic, String token)?
  subscriptionFor;
  final NtfyPacketPoller Function(Uri server, String topic, String token)?
  pollerFor;
  final BlobStore Function(Uri server, String token)? blobStoreFor;
  final Future<Uint8List?> Function(String handle)? readAttachment;
  final Future<String> Function(
    String messageId,
    String attachmentId,
    Uint8List bytes,
  )?
  writeAttachment;
  final SeenPacketStore _seenPackets;
  final ActentTransportStateStore _stateStore;
  final Duration presenceInterval;
  final Duration presenceTimeout;
  final StreamController<PeerConnectionStatus> _peerConnectionStatuses =
      StreamController<PeerConnectionStatus>.broadcast();
  final Map<String, PeerConnectionStatus> _peerStatuses = {};

  ActentRouter? _router;
  StreamSubscription<MessagingPacket>? _subscription;
  LanTlsPacketServer? _lanServer;
  bool _started = false;
  Timer? _presenceTimer;
  final Map<String, _IncomingAttachmentTransfer> _incomingTransfers = {};
  final Map<String, Completer<Map<String, Set<int>>>> _resumeWaiters = {};
  final Set<String> _activeOutgoingTransfers = <String>{};
  final Set<String> _processingPackets = <String>{};
  final MemoryLanBlobStore _lanBlobStore = MemoryLanBlobStore();

  String? get lanHost => lanServerConfig?.host;
  int? get lanPort => _lanServer?.boundPort;
  String? get lanCertificateSha256 => lanServerConfig?.certificateSha256;
  Stream<PeerConnectionStatus> get peerConnectionStatuses =>
      _peerConnectionStatuses.stream;

  Future<void> start(ActentRouter router) async {
    if (_started) return;
    _router = router;
    final expiredIncoming = await _stateStore.purgeExpired();
    for (final state in expiredIncoming) {
      await _discardIncomingTransfer(state);
    }
    final seenPackets = await _stateStore.loadSeenPackets();
    for (final entry in seenPackets.entries) {
      _seenPackets.remember(entry.key, seenAt: entry.value);
    }
    final lanConfig = lanServerConfig;
    if (lanConfig != null) {
      final server = LanTlsPacketServer(
        securityContext: lanConfig.securityContext,
        onPacket: _receive,
        blobStore: _lanBlobStore,
        host: lanConfig.bindAddress,
        port: lanConfig.port,
      );
      try {
        await server.start();
        _lanServer = server;
      } on Object {
        _router = null;
        rethrow;
      }
    }
    await _restoreIncomingTransfers();
    try {
      final token = relay.token;
      if (token != null) {
        final subscription =
            subscriptionFor?.call(relay.server, relay.controlTopic, token) ??
            NtfyPacketSubscription(
              server: relay.server,
              channel: relay.controlTopic,
              credentials: NtfyCredentials(token),
            );
        _subscription = subscription.listen().listen(
          (packet) => unawaited(_receive(packet)),
          onError: (_) {
            // Relay streams are best effort. Startup catch-up and durable
            // transfer state recover delivery after reconnect.
          },
        );
        try {
          final poller =
              pollerFor?.call(relay.server, relay.controlTopic, token) ??
              NtfyPacketPoller(
                server: relay.server,
                channel: relay.controlTopic,
                credentials: NtfyCredentials(token),
              );
          final cached = await poller.poll(
            since: DateTime.now().toUtc().subtract(seenPacketRetention),
          );
          for (final packet in cached) {
            await _receive(packet);
          }
        } on Object {
          // A failed cache poll must not prevent the live subscription from
          // starting. The next launch retries the same seven-day window.
        }
      }
      _started = true;
      _presenceTimer = Timer.periodic(
        presenceInterval,
        (_) => unawaited(probePeers()),
      );
      unawaited(_resumeOutgoingTransfers());
    } on Object {
      await _lanServer?.close();
      _lanServer = null;
      _router = null;
      rethrow;
    }
  }

  @override
  Future<void> send({
    required String recipientId,
    required Map<String, Object?> payload,
  }) async {
    final device = await repository.getDevice(recipientId);
    if (device == null || !device.authorized) {
      throw StateError('paired device is unavailable: $recipientId');
    }
    final prepared = await _prepareStreamingPayload(payload);
    if (prepared.transfers.isEmpty) {
      await _sendTransportPayload(recipientId, prepared.control);
      return;
    }
    final durableTransfers = <Map<String, Object?>>[];
    for (final transfer in prepared.transfers) {
      durableTransfers.add(<String, Object?>{
        'attachmentId': transfer.attachmentId,
        'sourceHandle': transfer.sourceHandle,
        'manifest': transfer.manifest.toJson(),
        'key': base64UrlEncode(await transfer.key.extractBytes()),
      });
    }
    await _stateStore.saveOutgoing(
      OutgoingTransportState(
        requestId: prepared.requestId,
        recipientId: recipientId,
        control: prepared.control,
        transfers: durableTransfers,
        createdAt: DateTime.now().toUtc(),
      ),
    );
    final requestId = prepared.requestId;
    final resumeWaiter = Completer<Map<String, Set<int>>>();
    // Register before publishing the offer: a LAN receiver can answer before
    // the publish call returns.
    _resumeWaiters[requestId] = resumeWaiter;
    try {
      await _sendTransportPayload(recipientId, prepared.control);
    } on Object {
      _resumeWaiters.remove(requestId);
      rethrow;
    }
    final resume = await resumeWaiter.future.timeout(
      const Duration(seconds: 2),
      onTimeout: () => <String, Set<int>>{},
    );
    _resumeWaiters.remove(requestId);
    for (final transfer in prepared.transfers) {
      final received = resume[transfer.attachmentId] ?? const <int>{};
      for (var index = 0; index < transfer.manifest.totalChunks; index++) {
        if (received.contains(index)) continue;
        final offset = index * transfer.manifest.chunkSize;
        final length = min(
          transfer.manifest.chunkSize,
          transfer.manifest.byteLength - offset,
        );
        final bytes = await transfer.source.read(offset, length);
        final chunk = await const AttachmentChunker().encryptChunk(
          manifest: transfer.manifest,
          plaintext: bytes,
          index: index,
          key: transfer.key,
        );
        final endpoint = _endpoint(device);
        final blobTopic = endpoint.relayBlobTopic;
        if (blobTopic == null || blobTopic.isEmpty) {
          throw StateError('paired device has no relay blob topic');
        }
        final blob = await _putAttachmentBlob(
          device,
          blobTopic,
          const AttachmentChunkBinaryCodec().encode(chunk),
        );
        await _sendTransportPayload(recipientId, {
          'type': 'attachmentChunkRef',
          'schemaVersion': actentSchemaVersion,
          'attachmentProtocol': AttachmentChunkReference(
            transferId: requestId,
            attachmentId: transfer.attachmentId,
            index: index,
            blob: blob,
          ).toJson(),
        });
      }
    }
    await _sendTransportPayload(recipientId, {
      'type': 'attachmentCommit',
      'schemaVersion': actentSchemaVersion,
      'requestId': requestId,
    });
    await _stateStore.deleteOutgoing(requestId);
  }

  Future<void> _sendTransportPayload(
    String recipientId,
    Map<String, Object?> transportPayload,
  ) async {
    final device = await repository.getDevice(recipientId);
    if (device == null || !device.authorized) {
      throw StateError('paired device is unavailable: $recipientId');
    }
    final remoteKey = _decodePublicKey(device.publicKey);
    final packet = await PacketCrypto().encrypt(
      sender: identity,
      recipientPublicKey: remoteKey,
      packetId: 'packet-${DateTime.now().microsecondsSinceEpoch}',
      senderId: deviceId,
      recipientId: recipientId,
      plaintext: utf8.encode(jsonEncode(transportPayload)),
    );
    final endpoint = _endpoint(device);
    final relayTopic = endpoint.relayTopic;
    if (relayTopic == null || relayTopic.isEmpty) {
      throw StateError('paired device has no relay inbox topic');
    }
    final token = relay.token;
    if (token == null) {
      throw StateError('ntfy token is not configured');
    }
    final server = endpoint.relayServer ?? relay.server;
    final sender = RoutedPacketSender(
      lan: lanConnectionFor?.call(device) ?? _defaultLanConnection(device),
      relay:
          relayPublisherFor?.call(server, token) ??
          NtfyRelayPublisher(
            server: server,
            credentials: NtfyCredentials(token),
          ),
      relayChannel: relayTopic,
    );
    await sender.send(packet);
  }

  Future<void> _resumeOutgoingTransfers() async {
    for (final state in await _stateStore.listOutgoing()) {
      if (!_activeOutgoingTransfers.add(state.requestId)) continue;
      try {
        final device = await repository.getDevice(state.recipientId);
        if (device == null || !device.authorized) continue;
        final transfers = <_PreparedAttachmentTransfer>[];
        for (final value in state.transfers) {
          final sourceHandle = _requiredPayloadString(value, 'sourceHandle');
          transfers.add(
            _PreparedAttachmentTransfer(
              attachmentId: _requiredPayloadString(value, 'attachmentId'),
              sourceHandle: sourceHandle,
              source: await _attachmentSource(sourceHandle),
              manifest: AttachmentManifest.fromJson(value['manifest']),
              key: _decodeTransferKey(_requiredPayloadString(value, 'key')),
            ),
          );
        }
        final prepared = _PreparedAttachmentPayload(
          control: state.control,
          requestId: state.requestId,
          transfers: transfers,
        );
        await _transmitRestoredAttachments(state.recipientId, device, prepared);
        await _stateStore.deleteOutgoing(state.requestId);
      } on Object {
        // The durable outbox remains available for the next launch.
      } finally {
        _activeOutgoingTransfers.remove(state.requestId);
      }
    }
  }

  Future<void> _transmitRestoredAttachments(
    String recipientId,
    Device device,
    _PreparedAttachmentPayload prepared,
  ) async {
    final requestId = prepared.requestId;
    final resumeWaiter = Completer<Map<String, Set<int>>>();
    _resumeWaiters[requestId] = resumeWaiter;
    try {
      await _sendTransportPayload(recipientId, prepared.control);
      final resume = await resumeWaiter.future.timeout(
        const Duration(seconds: 2),
        onTimeout: () => <String, Set<int>>{},
      );
      for (final transfer in prepared.transfers) {
        final received = resume[transfer.attachmentId] ?? const <int>{};
        for (var index = 0; index < transfer.manifest.totalChunks; index++) {
          if (received.contains(index)) continue;
          final offset = index * transfer.manifest.chunkSize;
          final length = min(
            transfer.manifest.chunkSize,
            transfer.manifest.byteLength - offset,
          );
          final plaintext = await transfer.source.read(offset, length);
          final chunk = await const AttachmentChunker().encryptChunk(
            manifest: transfer.manifest,
            plaintext: plaintext,
            index: index,
            key: transfer.key,
          );
          final endpoint = _endpoint(device);
          final blobTopic = endpoint.relayBlobTopic;
          if (blobTopic == null || blobTopic.isEmpty) {
            throw StateError('paired device ntfy blob endpoint is unavailable');
          }
          final blob = await _preferredBlobStore(device).put(
            channel: blobTopic,
            objectId: _newOpaqueId(),
            bytes: const AttachmentChunkBinaryCodec().encode(chunk),
          );
          await _sendTransportPayload(recipientId, <String, Object?>{
            'type': 'attachmentChunkRef',
            'schemaVersion': actentSchemaVersion,
            'attachmentProtocol': AttachmentChunkReference(
              transferId: requestId,
              attachmentId: transfer.attachmentId,
              index: index,
              blob: blob,
            ).toJson(),
          });
        }
      }
      await _sendTransportPayload(recipientId, <String, Object?>{
        'type': 'attachmentCommit',
        'schemaVersion': actentSchemaVersion,
        'requestId': requestId,
      });
    } finally {
      _resumeWaiters.remove(requestId);
    }
  }

  Future<void> _receive(MessagingPacket packet) async {
    if (packet.recipientId != deviceId) return;
    final device = await repository.getDevice(packet.senderId);
    if (device == null || !device.authorized) return;
    if (_seenPackets.contains(packet.packetId) ||
        !_processingPackets.add(packet.packetId)) {
      return;
    }
    try {
      final connection = EncryptedMessageConnection(
        transport: const _UnavailablePacketConnection(),
        localIdentity: identity,
        remotePublicKey: _decodePublicKey(device.publicKey),
        senderId: packet.senderId,
        recipientId: deviceId,
        seenPackets: SeenPacketStore(retention: seenPacketRetention),
      );
      final payload = await connection.receive(
        packet,
        expectedSenderId: packet.senderId,
      );
      _markPeerConnected(packet.senderId);
      final router = _router;
      if (router == null) return;
      switch (payload['type']) {
        case 'presencePing':
          await _sendTransportPayload(packet.senderId, {
            'type': 'presencePong',
            'schemaVersion': actentSchemaVersion,
          });
        case 'presencePong':
          break;
        case 'catalogSnapshot':
          await router.receiveCatalogSnapshot(
            payload['catalog'],
            ownerDeviceId: packet.senderId,
          );
        case 'catalogDelta':
          await router.receiveCatalogDelta(
            payload['catalog'],
            ownerDeviceId: packet.senderId,
          );
        case 'deviceUpdate':
          await router.receiveDeviceUpdate(
            payload['device'],
            authenticatedSenderId: packet.senderId,
          );
        case 'pairingRemoved':
          await router.receivePairingRemoved(packet.senderId);
        case 'workRequest':
          if (payload['attachmentTransfers'] is List) {
            await _beginIncomingAttachmentTransfer(payload, packet.senderId);
          } else {
            await router.receive(
              payload,
              authenticatedSenderId: packet.senderId,
            );
          }
        case 'attachmentChunkRef':
          await _receiveAttachmentChunkReference(payload);
        case 'attachmentCommit':
          await _commitIncomingAttachmentTransfer(payload, router);
        case 'attachmentResume':
          _receiveAttachmentResume(payload);
        case 'workReceipt':
          await router.receive(payload, authenticatedSenderId: packet.senderId);
        case 'workCancel':
          await router.receive(payload, authenticatedSenderId: packet.senderId);
      }
      _seenPackets.remember(packet.packetId, seenAt: packet.createdAt);
      await _stateStore.rememberPacket(packet.packetId);
    } on Object {
      // Invalid packets are deliberately dropped before Inbox/queue access.
    } finally {
      _processingPackets.remove(packet.packetId);
    }
  }

  /// Entry point used by a platform-owned LAN listener. Keeping this method
  /// on the transport means the listener never needs to understand Actent
  /// payloads or its authorization rules.
  Future<void> receivePacket(MessagingPacket packet) => _receive(packet);

  Future<void> probePeers() async {
    if (!_started) return;
    final now = DateTime.now().toUtc();
    final peers = (await repository.listDevices()).where(
      (device) => device.authorized && device.id != deviceId,
    );
    for (final peer in peers) {
      final current = _peerStatuses[peer.id];
      final lastSeen = current?.lastSeen;
      if (current == null ||
          (lastSeen != null && now.difference(lastSeen) > presenceTimeout)) {
        _setPeerStatus(
          PeerConnectionStatus(
            deviceId: peer.id,
            state: PeerConnectionState.disconnected,
            lastSeen: lastSeen,
          ),
        );
      }
      try {
        await _sendTransportPayload(peer.id, {
          'type': 'presencePing',
          'schemaVersion': actentSchemaVersion,
        });
      } on Object {
        _setPeerStatus(
          PeerConnectionStatus(
            deviceId: peer.id,
            state: PeerConnectionState.disconnected,
            lastSeen: lastSeen,
          ),
        );
      }
    }
  }

  void _markPeerConnected(String peerDeviceId) {
    _setPeerStatus(
      PeerConnectionStatus(
        deviceId: peerDeviceId,
        state: PeerConnectionState.connected,
        lastSeen: DateTime.now().toUtc(),
      ),
    );
  }

  void _setPeerStatus(PeerConnectionStatus status) {
    final previous = _peerStatuses[status.deviceId];
    _peerStatuses[status.deviceId] = status;
    if (previous?.state != status.state ||
        previous?.lastSeen != status.lastSeen) {
      _peerConnectionStatuses.add(status);
    }
  }

  Future<_PreparedAttachmentPayload> _prepareStreamingPayload(
    Map<String, Object?> payload,
  ) async {
    final copy = Map<String, Object?>.from(
      jsonDecode(jsonEncode(payload)) as Map,
    );
    final rawRequest = copy['request'];
    if (rawRequest is! Map) {
      return _PreparedAttachmentPayload(control: copy);
    }
    final request = Map<String, Object?>.from(rawRequest);
    final requestId = request['requestId'];
    final rawMessage = request['message'];
    if (requestId is! String || rawMessage is! Map) {
      return _PreparedAttachmentPayload(control: copy);
    }
    final message = Map<String, Object?>.from(rawMessage);
    final rawPayload = message['payload'];
    if (rawPayload is! Map) {
      return _PreparedAttachmentPayload(control: copy, requestId: requestId);
    }
    final messagePayload = Map<String, Object?>.from(rawPayload);
    final rawAttachments = messagePayload['attachments'];
    if (rawAttachments is! List || rawAttachments.isEmpty) {
      return _PreparedAttachmentPayload(control: copy, requestId: requestId);
    }
    final messageId = message['id'];
    if (messageId is! String || messageId.isEmpty) {
      throw const FormatException('attachment message identity is missing');
    }
    const chunker = AttachmentChunker(chunkSize: 8 * 1024 * 1024);
    final transfers = <_PreparedAttachmentTransfer>[];
    final descriptors = <Map<String, Object?>>[];
    final rewritten = <Map<String, Object?>>[];
    var totalBytes = 0;
    for (final rawAttachment in rawAttachments) {
      if (rawAttachment is! Map) {
        throw const FormatException('attachment must be an object');
      }
      final attachment = Map<String, Object?>.from(rawAttachment);
      final attachmentId = attachment['id'];
      final handle = attachment['handle'];
      if (attachmentId is! String || attachmentId.isEmpty) {
        throw const FormatException('attachment identity is missing');
      }
      if (handle is! String || handle.isEmpty) {
        throw const FormatException('attachment handle is missing');
      }
      if (readAttachment == null && !_isOwnedAttachment(handle)) {
        throw const FormatException(
          'attachment handle is outside Actent storage',
        );
      }
      final source = await _attachmentSource(handle);
      if (source.byteLength > 2 * 1024 * 1024 * 1024) {
        throw StateError('single attachment exceeds the 2 GiB limit');
      }
      totalBytes += source.byteLength;
      if (maxMessageBytes != null && totalBytes > maxMessageBytes!) {
        throw StateError(
          'message attachments exceed the configured transport limit',
        );
      }
      final manifest = await manifestForSource(
        messageId: messageId,
        attachmentId: attachmentId,
        source: source,
        chunkSize: chunker.chunkSize,
        name: '${attachment['name']}',
        mimeType: '${attachment['mimeType']}',
      );
      final keyBytes = List<int>.generate(
        32,
        (_) => Random.secure().nextInt(256),
      );
      final key = SecretKey(keyBytes);
      transfers.add(
        _PreparedAttachmentTransfer(
          attachmentId: attachmentId,
          sourceHandle: handle,
          source: source,
          manifest: manifest,
          key: key,
        ),
      );
      descriptors.add({
        'manifest': manifest.toJson(),
        'key': base64UrlEncode(keyBytes),
      });
      attachment['handle'] = 'actent-transfer://$messageId/$attachmentId';
      rewritten.add(attachment);
    }
    messagePayload['attachments'] = rewritten;
    message['payload'] = messagePayload;
    request['message'] = message;
    copy['request'] = request;
    copy['attachmentTransfers'] = descriptors;
    return _PreparedAttachmentPayload(
      control: copy,
      requestId: requestId,
      transfers: transfers,
    );
  }

  Future<AttachmentSource> _attachmentSource(String handle) async {
    if (_isOwnedAttachment(handle)) {
      return ActentFileAttachmentSource(File(handle));
    }
    final bytes = await _readAttachment(handle);
    return MemoryAttachmentSource(bytes);
  }

  Future<void> _beginIncomingAttachmentTransfer(
    Map<String, Object?> payload,
    String senderId, {
    DateTime? createdAt,
  }) async {
    final requestId = _requestIdFromPayload(payload);
    final rawTransfers = payload['attachmentTransfers'];
    final request = payload['request'];
    if (rawTransfers is! List || request is! Map) {
      throw const FormatException('attachment offer is invalid');
    }
    final rawMessage = request['message'];
    final rawPayload = rawMessage is Map ? rawMessage['payload'] : null;
    final rawAttachments = rawPayload is Map ? rawPayload['attachments'] : null;
    if (rawAttachments is! List ||
        rawAttachments.length != rawTransfers.length) {
      throw const FormatException(
        'attachment offer does not match the request',
      );
    }
    final expected = <String, Map<String, Object?>>{};
    for (final rawAttachment in rawAttachments) {
      if (rawAttachment is! Map || rawAttachment['id'] is! String) {
        throw const FormatException('request attachment is invalid');
      }
      final attachment = Map<String, Object?>.from(rawAttachment);
      final attachmentId = attachment['id'] as String;
      if (expected.containsKey(attachmentId)) {
        throw const FormatException('request attachment IDs are duplicated');
      }
      expected[attachmentId] = attachment;
    }
    final receivers = <String, ResumableAttachmentReceiver>{};
    final sinks = <String, ActentAttachmentSinkHandle>{};
    for (final rawTransfer in rawTransfers) {
      if (rawTransfer is! Map) {
        throw const FormatException('attachment offer entry is invalid');
      }
      final transfer = Map<String, Object?>.from(rawTransfer);
      final manifest = AttachmentManifest.fromJson(transfer['manifest']);
      final attachment = expected[manifest.attachmentId];
      if (attachment == null ||
          attachment['byteLength'] != manifest.byteLength ||
          attachment['name'] != manifest.name ||
          attachment['mimeType'] != manifest.mimeType) {
        throw const FormatException(
          'attachment manifest does not match request',
        );
      }
      if (receivers.containsKey(manifest.attachmentId)) {
        throw const FormatException('attachment IDs are duplicated');
      }
      final keyValue = transfer['key'];
      if (keyValue is! String) {
        throw const FormatException('attachment transfer key is missing');
      }
      final sink = _newAttachmentSink();
      if (sink == null) {
        throw const FormatException('attachment storage is unavailable');
      }
      final handleSink = sink as ActentAttachmentSinkHandle;
      final receiver = ResumableAttachmentReceiver(
        manifest: manifest,
        sink: sink,
        key: _decodeTransferKey(keyValue),
      );
      await receiver.begin();
      receivers[manifest.attachmentId] = receiver;
      sinks[manifest.attachmentId] = handleSink;
    }
    await _stateStore.saveIncoming(
      IncomingTransportState(
        requestId: requestId,
        senderId: senderId,
        payload: payload,
        createdAt: createdAt ?? DateTime.now().toUtc(),
      ),
    );
    _incomingTransfers[requestId] = _IncomingAttachmentTransfer(
      payload: payload,
      receivers: receivers,
      sinks: sinks,
      senderId: senderId,
    );
    await _sendTransportPayload(senderId, {
      'type': 'attachmentResume',
      'schemaVersion': actentSchemaVersion,
      'requestId': requestId,
      'transfers': [
        for (final entry in receivers.entries)
          <String, Object?>{
            'attachmentId': entry.key,
            'received': (await entry.value.receivedChunkIndexes()).toList()
              ..sort(),
          },
      ],
    });
  }

  Future<void> _restoreIncomingTransfers() async {
    for (final state in await _stateStore.listIncoming()) {
      try {
        await _beginIncomingAttachmentTransfer(
          state.payload,
          state.senderId,
          createdAt: state.createdAt,
        );
      } on Object {
        // A transient network/storage error leaves the state for next launch.
      }
    }
  }

  Future<void> _discardIncomingTransfer(IncomingTransportState state) async {
    final rawTransfers = state.payload['attachmentTransfers'];
    if (rawTransfers is! List) return;
    for (final rawTransfer in rawTransfers) {
      if (rawTransfer is! Map) continue;
      try {
        final manifest = AttachmentManifest.fromJson(rawTransfer['manifest']);
        final sink = _newAttachmentSink();
        if (sink == null) continue;
        await sink.begin(manifest);
        await sink.abort(manifest);
      } on Object {
        // Expiry cleanup is best effort and never blocks transport startup.
      }
    }
  }

  AttachmentSink? _newAttachmentSink() => attachmentRoot != null
      ? ActentFileAttachmentSink(attachmentRoot!)
      : attachmentStore != null
      ? ActentObjectStoreAttachmentSink(attachmentStore!)
      : writeAttachment == null
      ? null
      : ActentCallbackAttachmentSink(writeAttachment!);

  Future<void> _receiveAttachmentChunkReference(
    Map<String, Object?> payload,
  ) async {
    final message = AttachmentProtocolMessage.fromJson(
      payload['attachmentProtocol'],
    );
    if (message is! AttachmentChunkReference) {
      throw const FormatException('attachment chunk reference is invalid');
    }
    final pending = _incomingTransfers[message.transferId];
    final receiver = pending?.receivers[message.attachmentId];
    if (receiver == null) {
      throw const FormatException('unknown attachment transfer');
    }
    final bytes = message.blob.provider == 'lan'
        ? await _lanBlobStore.get(message.blob)
        : await _getNtfyBlob(message.blob);
    final chunk = const AttachmentChunkBinaryCodec().decode(
      bytes,
      messageId: receiver.manifest.messageId,
      attachmentId: receiver.manifest.attachmentId,
    );
    if (chunk.index != message.index) {
      throw const FormatException('attachment chunk reference index mismatch');
    }
    await receiver.add(chunk);
  }

  BlobStore _blobStore(Uri server, String token) =>
      blobStoreFor?.call(server, token) ??
      NtfyBlobStore(server: server, credentials: NtfyCredentials(token));

  Future<Uint8List> _getNtfyBlob(BlobReference reference) {
    final token = relay.token;
    if (token == null) throw StateError('ntfy token is not configured');
    return _blobStore(relay.server, token).get(reference);
  }

  Future<BlobReference> _putAttachmentBlob(
    Device device,
    String channel,
    Uint8List bytes,
  ) =>
      _preferredBlobStore(device)
          .put(channel: channel, objectId: _newOpaqueId(), bytes: bytes);

  BlobStore _preferredBlobStore(Device device) {
    final endpoint = _endpoint(device);
    BlobStore? lanStore = lanBlobStoreFor?.call(device);
    final host = endpoint.lanHost;
    final port = endpoint.lanPort;
    if (lanStore == null &&
        host != null &&
        host.isNotEmpty &&
        port != null &&
        port > 0) {
      lanStore = LanTlsBlobStore(
        host: host,
        port: port,
        localStore: _lanBlobStore,
        certificateSha256: endpoint.certificateSha256,
      );
    }
    final token = relay.token;
    final ntfyStore = token == null
        ? null
        : _blobStore(endpoint.relayServer ?? relay.server, token);
    if (lanStore != null && ntfyStore != null) {
      return _FallbackBlobStore(lanStore, ntfyStore);
    }
    return lanStore ??
        ntfyStore ??
        (throw StateError('no LAN or ntfy blob transport is configured'));
  }

  Future<void> _commitIncomingAttachmentTransfer(
    Map<String, Object?> payload,
    ActentRouter router,
  ) async {
    final requestId = _requiredPayloadString(payload, 'requestId');
    final pending = _incomingTransfers[requestId];
    if (pending == null) {
      if (await _stateStore.isCompleted(requestId)) return;
      throw const FormatException('unknown attachment transfer');
    }
    try {
      for (final receiver in pending.receivers.values) {
        await receiver.commit();
      }
      final originalRequest = Map<String, Object?>.from(
        (pending.payload['request'] as Map),
      );
      final originalMessage = Map<String, Object?>.from(
        originalRequest['message'] as Map,
      );
      final originalPayload = Map<String, Object?>.from(
        originalMessage['payload'] as Map,
      );
      final attachments = <Map<String, Object?>>[];
      for (final rawAttachment in originalPayload['attachments'] as List) {
        final attachment = Map<String, Object?>.from(rawAttachment);
        final id = attachment['id'];
        final sink = pending.sinks[id];
        if (id is! String || sink == null || sink.completedHandle == null) {
          throw const FormatException('attachment commit handle is missing');
        }
        attachment['handle'] = sink.completedHandle;
        attachments.add(attachment);
      }
      originalPayload['attachments'] = attachments;
      originalMessage['payload'] = originalPayload;
      originalRequest['message'] = originalMessage;
      final materialized = Map<String, Object?>.from(pending.payload)
        ..['request'] = originalRequest
        ..remove('attachmentTransfers');
      await router.receive(
        materialized,
        authenticatedSenderId: pending.senderId,
      );
      await _stateStore.markCompleted(requestId);
      await _stateStore.deleteIncoming(requestId);
      _incomingTransfers.remove(requestId);
    } on Object {
      // Keep committed files and durable state. Replaying commit is idempotent
      // and lets a restart finish routing after a transient storage failure.
      rethrow;
    }
  }

  void _receiveAttachmentResume(Map<String, Object?> payload) {
    final requestId = _requiredPayloadString(payload, 'requestId');
    final waiter = _resumeWaiters[requestId];
    if (waiter == null || waiter.isCompleted) return;
    final rawTransfers = payload['transfers'];
    if (rawTransfers is! List) return;
    final received = <String, Set<int>>{};
    for (final rawTransfer in rawTransfers) {
      if (rawTransfer is! Map || rawTransfer['attachmentId'] is! String) {
        continue;
      }
      final values = rawTransfer['received'];
      if (values is List) {
        received[rawTransfer['attachmentId'] as String] = values
            .whereType<int>()
            .toSet();
      }
    }
    waiter.complete(received);
  }

  String _requestIdFromPayload(Map<String, Object?> payload) {
    final request = payload['request'];
    if (request is! Map || request['requestId'] is! String) {
      throw const FormatException('attachment request ID is missing');
    }
    return request['requestId'] as String;
  }

  String _requiredPayloadString(Map<String, Object?> payload, String key) {
    final value = payload[key];
    if (value is! String || value.isEmpty) {
      throw FormatException('$key must be a non-empty string');
    }
    return value;
  }

  bool _isOwnedAttachment(String value) {
    final root = attachmentRoot;
    if (root == null) return false;
    final filePath = File(value).absolute.path.replaceAll('\\', '/');
    final rootPath = root.absolute.path
        .replaceAll('\\', '/')
        .replaceFirst(RegExp(r'/$'), '');
    return filePath.toLowerCase().startsWith('${rootPath.toLowerCase()}/');
  }

  Future<Uint8List> _readAttachment(String handle) async {
    final reader = readAttachment;
    if (reader != null) {
      final bytes = await reader(handle);
      if (bytes == null) {
        throw const FormatException('attachment content is unavailable');
      }
      return bytes;
    }
    return File(handle).readAsBytes();
  }

  SecretKey _decodeTransferKey(String value) {
    try {
      final bytes = base64Url.decode(value);
      if (bytes.length != 32) {
        throw const FormatException('attachment transfer key must be 32 bytes');
      }
      return SecretKey(bytes);
    } on FormatException {
      throw const FormatException('attachment transfer key is invalid');
    }
  }

  Future<void> stop() async {
    _presenceTimer?.cancel();
    _presenceTimer = null;
    await _subscription?.cancel();
    _subscription = null;
    await _lanServer?.close();
    _lanServer = null;
    _router = null;
    _started = false;
  }
}

/// TLS configuration for the optional local LAN packet listener. The
/// certificate and private key are supplied by the application environment;
/// Actent never generates or persists private key material in its JSON store.
class ActentLanServerConfig {
  const ActentLanServerConfig({
    required this.securityContext,
    required this.host,
    this.bindAddress,
    this.port = 0,
    this.certificateSha256,
  });

  final SecurityContext securityContext;
  final String host;
  final InternetAddress? bindAddress;
  final int port;
  final String? certificateSha256;

  /// Loads a certificate/key pair provided through compile-time defines.
  /// Without both files the app remains relay-only, which is the safe default.
  static Future<ActentLanServerConfig?> fromEnvironment() async {
    final certificatePath = const String.fromEnvironment(
      'ACTENT_LAN_CERT_PATH',
    );
    final privateKeyPath = const String.fromEnvironment('ACTENT_LAN_KEY_PATH');
    if (certificatePath.isEmpty || privateKeyPath.isEmpty) return null;
    final certificateFile = File(certificatePath);
    final privateKeyFile = File(privateKeyPath);
    if (!await certificateFile.exists() || !await privateKeyFile.exists()) {
      throw StateError(
        'ACTENT_LAN_CERT_PATH and ACTENT_LAN_KEY_PATH must point to files',
      );
    }
    final securityContext = SecurityContext()
      ..useCertificateChain(certificatePath)
      ..usePrivateKey(privateKeyPath);
    final configuredHost = const String.fromEnvironment('ACTENT_LAN_HOST');
    final host = configuredHost.isNotEmpty
        ? configuredHost
        : await _firstLanIpv4();
    if (host == null || host.isEmpty) {
      throw StateError('no non-loopback IPv4 address is available');
    }
    return ActentLanServerConfig(
      securityContext: securityContext,
      host: host,
      certificateSha256: await _certificateSha256(certificateFile),
    );
  }
}

class ActentEndpoint {
  const ActentEndpoint({
    this.relayServer,
    this.relayTopic,
    this.relayBlobTopic,
    this.lanHost,
    this.lanPort,
    this.certificateSha256,
  });

  final Uri? relayServer;
  final String? relayTopic;
  final String? relayBlobTopic;
  final String? lanHost;
  final int? lanPort;
  final String? certificateSha256;
}

ActentEndpoint _endpoint(Device device) {
  final endpoint = device.endpoint;
  final relayServer = switch (endpoint['relayUrl']) {
    String value when Uri.tryParse(value)?.hasScheme == true => Uri.parse(
      value,
    ),
    _ => null,
  };
  final port = endpoint['lanPort'];
  return ActentEndpoint(
    relayServer: relayServer,
    relayTopic: endpoint['relayTopic'] as String?,
    relayBlobTopic: endpoint['relayBlobTopic'] as String?,
    lanHost: endpoint['lanHost'] as String?,
    lanPort: port is int ? port : int.tryParse('$port'),
    certificateSha256: endpoint['certificateSha256'] as String?,
  );
}

PacketConnection _defaultLanConnection(Device device) {
  final endpoint = _endpoint(device);
  final host = endpoint.lanHost;
  final port = endpoint.lanPort;
  if (host == null || host.isEmpty || port == null || port <= 0) {
    return const _UnavailablePacketConnection();
  }
  return LanTlsPacketConnection(
    host: host,
    port: port,
    certificateSha256: endpoint.certificateSha256,
  );
}

SimplePublicKey _decodePublicKey(String value) {
  try {
    return SimplePublicKey(base64Url.decode(value), type: KeyPairType.x25519);
  } on Object catch (error) {
    throw FormatException('invalid device public key: $error');
  }
}

class _PreparedAttachmentPayload {
  _PreparedAttachmentPayload({
    required this.control,
    this.requestId = '',
    this.transfers = const [],
  });

  final Map<String, Object?> control;
  final String requestId;
  final List<_PreparedAttachmentTransfer> transfers;
}

class _PreparedAttachmentTransfer {
  const _PreparedAttachmentTransfer({
    required this.attachmentId,
    required this.sourceHandle,
    required this.source,
    required this.manifest,
    required this.key,
  });

  final String attachmentId;
  final String sourceHandle;
  final AttachmentSource source;
  final AttachmentManifest manifest;
  final SecretKey key;
}

class _IncomingAttachmentTransfer {
  const _IncomingAttachmentTransfer({
    required this.payload,
    required this.receivers,
    required this.sinks,
    required this.senderId,
  });

  final Map<String, Object?> payload;
  final Map<String, ResumableAttachmentReceiver> receivers;
  final Map<String, ActentAttachmentSinkHandle> sinks;
  final String senderId;
}

class _FallbackBlobStore implements BlobStore {
  const _FallbackBlobStore(this.primary, this.fallback);

  final BlobStore primary;
  final BlobStore fallback;

  @override
  Future<BlobReference> put({
    required String channel,
    required String objectId,
    required Uint8List bytes,
  }) async {
    try {
      return await primary.put(
        channel: channel,
        objectId: objectId,
        bytes: bytes,
      );
    } on Object {
      return fallback.put(channel: channel, objectId: objectId, bytes: bytes);
    }
  }

  @override
  Future<Uint8List> get(BlobReference reference) async {
    try {
      return await primary.get(reference);
    } on Object {
      return fallback.get(reference);
    }
  }
}

class _UnavailablePacketConnection implements PacketConnection {
  const _UnavailablePacketConnection();

  @override
  Future<void> send(MessagingPacket packet) =>
      Future<void>.error(const SocketException('LAN endpoint unavailable'));
}

String _newTopic() =>
    'actent-${base64UrlEncode(List<int>.generate(32, (_) => Random.secure().nextInt(256))).replaceAll('=', '')}';

String _newOpaqueId() =>
    base64UrlEncode(List<int>.generate(24, (_) => Random.secure().nextInt(256)))
        .replaceAll('=', '');

Future<String?> _firstLanIpv4() async {
  final interfaces = await NetworkInterface.list(
    includeLoopback: false,
    type: InternetAddressType.IPv4,
  );
  for (final interface in interfaces) {
    for (final address in interface.addresses) {
      if (!address.isLoopback && address.type == InternetAddressType.IPv4) {
        return address.address;
      }
    }
  }
  return null;
}

Future<String?> _certificateSha256(File certificateFile) async {
  final bytes = await certificateFile.readAsBytes();
  final text = utf8.decode(bytes, allowMalformed: true);
  final match = RegExp(
    r'-----BEGIN CERTIFICATE-----(.*?)-----END CERTIFICATE-----',
    dotAll: true,
  ).firstMatch(text);
  if (match == null) return null;
  try {
    final der = base64.decode(match.group(1)!.replaceAll(RegExp(r'\s+'), ''));
    return sha256.convert(der).toString();
  } on FormatException {
    return null;
  }
}
