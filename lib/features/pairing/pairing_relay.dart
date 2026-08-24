import '../messaging/message_connection.dart';
import 'pairing.dart';
import 'pairing_relay_contracts.dart' as capability;

/// Wires the generic pairing relay handshake to the application's ntfy
/// publisher and JSON WebSocket subscription adapters.
class PairingRelayHandshake {
  PairingRelayHandshake({
    required this.server,
    required this.token,
    RelayPublisher? publisher,
    this.subscriptionFactory,
  }) : _publisher =
           publisher ??
           NtfyRelayPublisher(
             server: server,
             credentials: NtfyCredentials(token),
           ),
       _subscriptionFactory =
           subscriptionFactory ??
           ((server, topic, authorization) => NtfyJsonSubscription(
             server: server,
             channel: topic,
             credentials: NtfyCredentials(token),
           )) {
    _delegate = capability.PairingRelayHandshake(
      server: server,
      authorization: null,
      publisher: _RelayPublisherAdapter(_publisher),
      subscriptionFactory: (relayServer, topic, relayAuthorization) =>
          _SubscriptionAdapter(
            _subscriptionFactory(relayServer, topic, relayAuthorization),
          ),
    );
  }

  final Uri server;
  final String token;
  final NtfyJsonSubscription Function(Uri server, String topic, String? auth)?
  subscriptionFactory;
  final RelayPublisher _publisher;
  final NtfyJsonSubscription Function(Uri server, String topic, String? auth)
  _subscriptionFactory;
  late final capability.PairingRelayHandshake _delegate;

  Future<PairingAcceptance> sendAcceptance({
    required PairingInvite invite,
    required String deviceId,
    required String publicKey,
    required String displayName,
    required String platform,
    required String relayUrl,
    required String controlTopic,
    required String blobTopic,
    String? lanHost,
    int? lanPort,
    String? certificateSha256,
  }) => _delegate.sendAcceptance(
    invite: invite,
    deviceId: deviceId,
    publicKey: publicKey,
    displayName: displayName,
    platform: platform,
    relayUrl: relayUrl,
    controlTopic: controlTopic,
    blobTopic: blobTopic,
    lanHost: lanHost,
    lanPort: lanPort,
    certificateSha256: certificateSha256,
  );

  Stream<PairingAcceptance> listenForAcceptance(PairingInvite invite) =>
      _delegate.listenForAcceptance(invite);

  Future<void> sendConfirmation({
    required PairingAcceptance acceptance,
    required String issuerDeviceId,
  }) => _delegate.sendConfirmation(
    acceptance: acceptance,
    issuerDeviceId: issuerDeviceId,
  );

  Stream<PairingConfirmation> listenForConfirmation(
    PairingInvite invite, {
    required String localRelayTopic,
  }) =>
      _delegate.listenForConfirmation(invite, localRelayTopic: localRelayTopic);
}

class _RelayPublisherAdapter implements capability.PairingRelayPublisher {
  const _RelayPublisherAdapter(this.delegate);

  final RelayPublisher delegate;

  @override
  Future<void> publish(String topic, String body, {String? authorization}) =>
      delegate.publish(topic, body);
}

class _SubscriptionAdapter implements capability.PairingRelaySubscription {
  const _SubscriptionAdapter(this.delegate);

  final NtfyJsonSubscription delegate;

  @override
  Stream<Map<String, Object?>> listen() => delegate.listen();
}
