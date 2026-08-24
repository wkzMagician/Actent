import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:actent/features/pairing/pairing.dart';
import 'package:actent/features/pairing/lan_pairing.dart';

void main() {
  test('encodes an invite as a portable URI without private credentials', () {
    final coordinator = PairingCoordinator(random: Random(1));
    final session = coordinator.createInvite(
      uriScheme: 'actent',
      issuerDeviceId: 'desktop',
      issuerPublicKey: 'public-key',
      relayUrl: 'https://ntfy.example',
      temporaryTopic: 'temporary-topic',
      issuerControlTopic: 'desktop-control',
      issuerBlobTopic: 'desktop-blob',
      issuerLanHost: '192.168.1.10',
      issuerLanPort: 43100,
      issuerPairingLanPort: 43101,
      issuerCertificateSha256: 'certificate-fingerprint',
    );

    final decoded = PairingInvite.fromUri(
      session.invite.toUri(),
      uriScheme: 'actent',
    );
    expect(decoded.nonce, session.invite.nonce);
    expect(decoded.issuerLanHost, '192.168.1.10');
    expect(decoded.issuerLanPort, 43100);
    expect(decoded.issuerPairingLanPort, 43101);
    expect(decoded.issuerCertificateSha256, 'certificate-fingerprint');
    expect(decoded.shortCode, matches(RegExp(r'^\d{6}$')));
    expect(session.invite.toUri(), isNot(contains('private')));
  });

  test('requires both acceptance and matching short-code confirmation', () {
    final coordinator = PairingCoordinator(random: Random(2));
    final session = coordinator.createInvite(
      uriScheme: 'actent',
      issuerDeviceId: 'desktop',
      issuerPublicKey: 'public-key',
      relayUrl: 'https://ntfy.example',
      temporaryTopic: 'temporary-topic',
      issuerControlTopic: 'desktop-control',
      issuerBlobTopic: 'desktop-blob',
    );

    session.accept(remoteDeviceId: 'phone', remotePublicKey: 'phone-key');
    expect(
      () => session.confirm('000000'),
      throwsA(isA<PairingValidationException>()),
    );
    session.confirm(session.invite.shortCode);
    expect(session.status, PairingStatus.confirmed);
    expect(() => session.cancel(), throwsStateError);
  });

  test('expires invitations and emits LAN discovery advertisements', () async {
    var now = DateTime.utc(2026, 1, 1);
    final coordinator = PairingCoordinator(clock: () => now, random: Random(3));
    final session = coordinator.createInvite(
      uriScheme: 'actent',
      issuerDeviceId: 'desktop',
      issuerPublicKey: 'public-key',
      relayUrl: 'https://ntfy.example',
      temporaryTopic: 'temporary-topic',
      issuerControlTopic: 'desktop-control',
      issuerBlobTopic: 'desktop-blob',
      lifetime: const Duration(minutes: 10),
    );
    now = now.add(const Duration(minutes: 11));
    coordinator.expireAll();
    expect(session.status, PairingStatus.expired);

    final discovery = FakePairingDiscovery();
    final future = discovery.discover().first;
    discovery.advertise(
      const PairingAdvertisement(
        deviceId: 'desktop',
        displayName: 'Desk',
        platform: 'windows',
        fingerprint: 'abcd',
      ),
    );
    expect((await future).deviceId, 'desktop');
    await discovery.close();
  });

  test('relay acceptance proof round-trips and rejects a different invite', () {
    final coordinator = PairingCoordinator(random: Random(4));
    final session = coordinator.createInvite(
      uriScheme: 'actent',
      issuerDeviceId: 'desktop',
      issuerPublicKey: 'desktop-key',
      relayUrl: 'https://ntfy.example',
      temporaryTopic: 'temporary-topic',
      issuerControlTopic: 'desktop-control',
      issuerBlobTopic: 'desktop-blob',
    );
    final acceptance = PairingAcceptance(
      nonce: session.invite.nonce,
      shortCode: session.invite.shortCode,
      deviceId: 'phone',
      publicKey: 'phone-key',
      displayName: 'Phone',
      platform: 'android',
      relayUrl: 'https://ntfy.example',
      controlTopic: 'phone-control',
      blobTopic: 'phone-blob',
      proof: pairingProof(
        nonce: session.invite.nonce,
        shortCode: session.invite.shortCode,
        deviceId: 'phone',
        publicKey: 'phone-key',
      ),
      createdAt: DateTime.now().toUtc(),
    );
    final decoded = PairingAcceptance.fromJson(acceptance.toJson());
    expect(decoded.verify(session.invite), isTrue);
    expect(
      PairingAcceptance.fromJson(<String, Object?>{
        ...acceptance.toJson(),
        'relayUrl': 'https://other-relay.example',
      }).verify(session.invite),
      isFalse,
    );
    final other = coordinator.createInvite(
      uriScheme: 'actent',
      issuerDeviceId: 'other',
      issuerPublicKey: 'other-key',
      relayUrl: 'https://ntfy.example',
      temporaryTopic: 'other-topic',
      issuerControlTopic: 'other-control',
      issuerBlobTopic: 'other-blob',
    );
    expect(decoded.verify(other.invite), isFalse);
  });

  test('LAN pairing handler verifies acceptance before confirming', () async {
    final coordinator = PairingCoordinator(random: Random(5));
    final session = coordinator.createInvite(
      uriScheme: 'actent',
      issuerDeviceId: 'desktop',
      issuerPublicKey: 'desktop-key',
      relayUrl: 'https://ntfy.example',
      temporaryTopic: 'temporary-topic',
      issuerControlTopic: 'desktop-control',
      issuerBlobTopic: 'desktop-blob',
    );
    PairingAcceptance? accepted;
    final handler = LanPairingRequestHandler(
      invite: session.invite,
      issuerDeviceId: 'desktop',
      onAccepted: (value) async {
        accepted = value;
        return true;
      },
    );
    final inviteResponse = await handler.handle(const {
      'type': 'pairingHello',
      'version': 1,
    });
    expect(
      PairingInvite.fromUri(
        inviteResponse['inviteUri'] as String,
        uriScheme: 'actent',
      ).nonce,
      session.invite.nonce,
    );
    final request = PairingAcceptance(
      nonce: session.invite.nonce,
      shortCode: session.invite.shortCode,
      deviceId: 'phone',
      publicKey: 'phone-key',
      displayName: 'Phone',
      platform: 'android',
      relayUrl: 'https://ntfy.example',
      controlTopic: 'phone-control',
      blobTopic: 'phone-blob',
      proof: pairingProof(
        nonce: session.invite.nonce,
        shortCode: session.invite.shortCode,
        deviceId: 'phone',
        publicKey: 'phone-key',
      ),
      createdAt: DateTime.now().toUtc(),
    );
    final confirmation = PairingConfirmation.fromJson(
      await handler.handle(request.toJson()),
    );
    expect(accepted?.deviceId, 'phone');
    expect(confirmation.issuerDeviceId, 'desktop');
    expect(confirmation.acceptorDeviceId, 'phone');
    expect(
      () => handler.handle({...request.toJson(), 'shortCode': '000000'}),
      throwsA(isA<PairingValidationException>()),
    );
  });
}
