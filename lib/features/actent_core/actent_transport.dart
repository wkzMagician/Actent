import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';

import '../messaging/message_connection.dart';
import '../messaging/attachment_chunks.dart';
import '../messaging/messaging_packet.dart';
import '../messaging/packet_crypto.dart';
import '../messaging/seen_packet_store.dart';
import 'actent_models.dart';
import 'actent_router.dart';
import 'actent_store.dart';
import 'secret_repository.dart';

/// Settings shared by the relay publisher and the local subscription.
/// Authentication is intentionally kept outside the JSON repository.
class ActentRelaySettings {
  const ActentRelaySettings({
    required this.server,
    required this.topic,
    this.authorization,
  });

  final Uri server;
  final String topic;
  final String? authorization;

  static Future<ActentRelaySettings> load(
    ActentSecretRepository secrets,
  ) async {
    var topic = await secrets.read('relay.inbox.topic');
    if (topic == null || topic.length < 24) {
      topic = _newTopic();
      await secrets.write('relay.inbox.topic', topic);
    }
    final serverText = await secrets.read('relay.server') ?? 'https://ntfy.sh';
    final server = Uri.tryParse(serverText);
    if (server == null || !server.hasScheme || server.host.isEmpty) {
      throw StateError('invalid relay.server setting');
    }
    return ActentRelaySettings(
      server: server,
      topic: topic,
      authorization: await secrets.read('relay.authorization'),
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
    this.maxMessageBytes,
    this.seenPacketRetention = const Duration(days: 7),
    this.lanServerConfig,
    SeenPacketStore? seenPackets,
    this.lanConnectionFor,
    this.relayPublisherFor,
    this.subscriptionFor,
    this.readAttachment,
    this.writeAttachment,
  }) : _seenPackets =
           seenPackets ?? SeenPacketStore(retention: seenPacketRetention);

  final String deviceId;
  final PacketIdentity identity;
  final ActentRepository repository;
  final ActentRelaySettings relay;
  final Directory? attachmentRoot;

  /// Optional application policy. A null value means that Actent does not
  /// impose an arbitrary whole-message limit; the transport may still reject
  /// a packet when its selected relay or LAN implementation cannot carry it.
  final int? maxMessageBytes;
  final Duration seenPacketRetention;
  final ActentLanServerConfig? lanServerConfig;
  final PacketConnection Function(Device device)? lanConnectionFor;
  final RelayPublisher Function(Uri server)? relayPublisherFor;
  final NtfyPacketSubscription Function(Uri server, String topic, String? auth)?
  subscriptionFor;
  final Future<Uint8List?> Function(String handle)? readAttachment;
  final Future<String> Function(
    String messageId,
    String attachmentId,
    Uint8List bytes,
  )?
  writeAttachment;
  final SeenPacketStore _seenPackets;

  ActentRouter? _router;
  StreamSubscription<MessagingPacket>? _subscription;
  LanTlsPacketServer? _lanServer;
  bool _started = false;

  String? get lanHost => lanServerConfig?.host;
  int? get lanPort => _lanServer?.boundPort;
  String? get lanCertificateSha256 => lanServerConfig?.certificateSha256;

  Future<void> start(ActentRouter router) async {
    if (_started) return;
    _router = router;
    final lanConfig = lanServerConfig;
    if (lanConfig != null) {
      final server = LanTlsPacketServer(
        securityContext: lanConfig.securityContext,
        onPacket: _receive,
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
    try {
      final subscription =
          subscriptionFor?.call(
            relay.server,
            relay.topic,
            relay.authorization,
          ) ??
          NtfyPacketSubscription(
            relay.server,
            relay.topic,
            authorization: relay.authorization,
          );
      _subscription = subscription.listen().listen(
        (packet) => unawaited(_receive(packet)),
        onError: (_) {
          // Relay streams are best effort. The next app start reconnects and
          // durable requests remain in the repository until then.
        },
      );
      _started = true;
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
    final remoteKey = _decodePublicKey(device.publicKey);
    final transportPayload = await _preparePayload(payload);
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
    final sender = RoutedPacketSender(
      lan: lanConnectionFor?.call(device) ?? _defaultLanConnection(device),
      relay:
          relayPublisherFor?.call(endpoint.relayServer ?? relay.server) ??
          NtfyRelayPublisher(endpoint.relayServer ?? relay.server),
      relayTopic: relayTopic,
      relayAuthorization: endpoint.relayAuthorization,
    );
    await sender.send(packet);
  }

  Future<void> _receive(MessagingPacket packet) async {
    if (packet.recipientId != deviceId) return;
    final device = await repository.getDevice(packet.senderId);
    if (device == null || !device.authorized) return;
    try {
      final connection = EncryptedMessageConnection(
        transport: const _UnavailablePacketConnection(),
        localIdentity: identity,
        remotePublicKey: _decodePublicKey(device.publicKey),
        senderId: packet.senderId,
        recipientId: deviceId,
        seenPackets: _seenPackets,
      );
      final payload = await connection.receive(
        packet,
        expectedSenderId: packet.senderId,
      );
      final router = _router;
      if (router == null) return;
      final materialized = await _materializeAttachments(payload);
      switch (payload['type']) {
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
        case 'workRequest':
        case 'workReceipt':
          await router.receive(
            materialized,
            authenticatedSenderId: packet.senderId,
          );
        case 'workCancel':
          await router.receive(
            materialized,
            authenticatedSenderId: packet.senderId,
          );
      }
    } on Object {
      // Invalid packets are deliberately dropped before Inbox/queue access.
    }
  }

  /// Entry point used by a platform-owned LAN listener. Keeping this method
  /// on the transport means the listener never needs to understand Actent
  /// payloads or its authorization rules.
  Future<void> receivePacket(MessagingPacket packet) => _receive(packet);

  Future<Map<String, Object?>> _preparePayload(
    Map<String, Object?> payload,
  ) async {
    if (payload['type'] != 'workRequest') return payload;
    final copy = Map<String, Object?>.from(
      jsonDecode(jsonEncode(payload)) as Map,
    );
    final rawRequest = copy['request'];
    if (rawRequest is! Map) return copy;
    final request = Map<String, Object?>.from(rawRequest);
    final rawMessage = request['message'];
    if (rawMessage is! Map) return copy;
    final message = Map<String, Object?>.from(rawMessage);
    final rawAttachments = message['attachments'];
    if (rawAttachments is! List || rawAttachments.isEmpty) return copy;
    final chunker = const AttachmentChunker();
    final transfers = <Map<String, Object?>>[];
    var totalBytes = 0;
    final rewritten = <Map<String, Object?>>[];
    for (final rawAttachment in rawAttachments) {
      if (rawAttachment is! Map) {
        throw const FormatException('attachment must be an object');
      }
      final attachment = Map<String, Object?>.from(rawAttachment);
      final handle = attachment['handle'];
      if (handle is! String || handle.isEmpty) {
        throw const FormatException('attachment handle is missing');
      }
      if (readAttachment == null && !_isOwnedAttachment(handle)) {
        throw const FormatException(
          'attachment handle is outside Actent storage',
        );
      }
      final bytes = await _readAttachment(handle);
      totalBytes += bytes.length;
      final configuredLimit = maxMessageBytes;
      if (configuredLimit != null && totalBytes > configuredLimit) {
        throw StateError(
          'message attachments exceed the configured transport limit',
        );
      }
      final attachmentId = attachment['id'];
      final messageId = message['id'];
      if (attachmentId is! String || messageId is! String) {
        throw const FormatException('attachment identity is missing');
      }
      final manifest = chunker.manifest(
        messageId: messageId,
        attachmentId: attachmentId,
        name: '${attachment['name']}',
        mimeType: '${attachment['mimeType']}',
        plaintext: Uint8List.fromList(bytes),
      );
      // The outer Packet is encrypted as well, but each attachment chunk is
      // independently authenticated so a partial transfer cannot be
      // mistaken for an opaque, trusted byte stream. The transfer key is
      // carried inside the already authenticated Packet payload.
      final transferKeyBytes = List<int>.generate(
        32,
        (_) => Random.secure().nextInt(256),
      );
      final chunks = await chunker.encryptAndSplit(
        manifest: manifest,
        plaintext: Uint8List.fromList(bytes),
        key: SecretKey(transferKeyBytes),
      );
      transfers.add({
        'manifest': manifest.toJson(),
        'chunks': chunks.map((chunk) => chunk.toJson()).toList(),
        'key': base64UrlEncode(transferKeyBytes),
      });
      attachment['handle'] = 'actent-transfer://$messageId/$attachmentId';
      rewritten.add(attachment);
    }
    message['attachments'] = rewritten;
    request['message'] = message;
    copy['request'] = request;
    copy['attachmentTransfers'] = transfers;
    return copy;
  }

  Future<Map<String, Object?>> _materializeAttachments(
    Map<String, Object?> payload,
  ) async {
    final rawTransfers = payload['attachmentTransfers'];
    if (rawTransfers == null) return payload;
    if (rawTransfers is! List ||
        (attachmentRoot == null && writeAttachment == null)) {
      throw const FormatException('attachment transfer is unavailable');
    }
    final request = payload['request'];
    if (request is! Map || request['message'] is! Map) {
      throw const FormatException('attachment transfer has no message');
    }
    final message = Map<String, Object?>.from(request['message'] as Map);
    final attachments = message['attachments'];
    if (attachments is! List) {
      throw const FormatException('attachment list is invalid');
    }
    final byId = <String, Map<String, Object?>>{
      for (final item in attachments)
        if (item is Map && item['id'] is String)
          item['id'] as String: Map<String, Object?>.from(item),
    };
    final createdFiles = <File>[];
    try {
      for (final rawTransfer in rawTransfers) {
        if (rawTransfer is! Map) {
          throw const FormatException('attachment transfer must be an object');
        }
        final transfer = Map<String, Object?>.from(rawTransfer);
        final manifest = AttachmentManifest.fromJson(transfer['manifest']);
        final attachment = byId[manifest.attachmentId];
        if (attachment == null ||
            attachment['name'] != manifest.name ||
            attachment['mimeType'] != manifest.mimeType ||
            attachment['byteLength'] != manifest.byteLength) {
          throw const FormatException(
            'attachment manifest does not match message',
          );
        }
        final chunks = transfer['chunks'];
        if (chunks is! List) {
          throw const FormatException('attachment chunks must be an array');
        }
        final keyValue = transfer['key'];
        if (keyValue is! String) {
          throw const FormatException('attachment transfer key is missing');
        }
        final transferKey = _decodeTransferKey(keyValue);
        final reassembler = AttachmentReassembler(manifest);
        for (final rawChunk in chunks) {
          reassembler.add(AttachmentChunk.fromJson(rawChunk));
        }
        final bytes = await reassembler.decryptAndAssemble(key: transferKey);
        final messageId = message['id'];
        if (messageId is! String ||
            !_safePathComponent(messageId) ||
            !_safePathComponent(manifest.attachmentId)) {
          throw const FormatException('unsafe attachment path');
        }
        final targetRoot = attachmentRoot;
        if (targetRoot != null) {
          final directory = Directory(
            '${targetRoot.path}${Platform.pathSeparator}$messageId${Platform.pathSeparator}${manifest.attachmentId}',
          );
          await directory.create(recursive: true);
          final file = File(
            '${directory.path}${Platform.pathSeparator}payload',
          );
          await file.writeAsBytes(bytes, flush: true);
          createdFiles.add(file);
          attachment['handle'] = file.path;
        } else {
          final handle = await writeAttachment!(
            messageId,
            manifest.attachmentId,
            bytes,
          );
          attachment['handle'] = handle;
        }
      }
      final copy = Map<String, Object?>.from(payload);
      final copyRequest = Map<String, Object?>.from(request);
      message['attachments'] = byId.values.toList(growable: false);
      copyRequest['message'] = message;
      copy['request'] = copyRequest;
      copy.remove('attachmentTransfers');
      return copy;
    } on Object {
      for (final file in createdFiles) {
        try {
          await file.delete();
        } on Object {
          // Best-effort cleanup after a failed authenticated transfer.
        }
      }
      rethrow;
    }
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
    this.relayAuthorization,
    this.lanHost,
    this.lanPort,
    this.certificateSha256,
  });

  final Uri? relayServer;
  final String? relayTopic;
  final String? relayAuthorization;
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
    relayAuthorization: endpoint['relayAuthorization'] as String?,
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

class _UnavailablePacketConnection implements PacketConnection {
  const _UnavailablePacketConnection();

  @override
  Future<void> send(MessagingPacket packet) =>
      Future<void>.error(const SocketException('LAN endpoint unavailable'));
}

String _newTopic() =>
    'actent-${base64UrlEncode(List<int>.generate(32, (_) => Random.secure().nextInt(256))).replaceAll('=', '')}';

bool _safePathComponent(String value) =>
    value.isNotEmpty &&
    value != '.' &&
    value != '..' &&
    !value.contains('/') &&
    !value.contains('\\');

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
