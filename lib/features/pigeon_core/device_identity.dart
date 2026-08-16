import 'dart:convert';
import 'dart:math';

import '../messaging/packet_crypto.dart';
import '../pairing/pairing_identity.dart';
import 'secret_repository.dart';

class DeviceIdentity {
  const DeviceIdentity({required this.deviceId, required this.packetIdentity});

  final String deviceId;
  final PacketIdentity packetIdentity;

  String get publicKey => base64UrlEncode(packetIdentity.publicKey.bytes);
}

/// Loads a stable device ID and X25519 private key from Secure Settings.
///
/// The public key can be published in a Device record, but the private key is
/// never returned to the JSON repository or included in an invitation.
class DeviceIdentityRepository {
  DeviceIdentityRepository(
    this.secrets, {
    Random? random,
    this.deviceIdKey = 'device.id',
    this.privateKeyKey = 'device.x25519.private',
  }) : _pairingRepository = PairingIdentityRepository(
         secrets,
         random: random,
         deviceIdKey: deviceIdKey,
         privateKeyKey: privateKeyKey,
       );

  final PigeonSecretRepository secrets;
  final String deviceIdKey;
  final String privateKeyKey;
  final PairingIdentityRepository _pairingRepository;

  Future<DeviceIdentity> loadOrCreate() async {
    final pairingIdentity = await _pairingRepository.loadOrCreate();
    return DeviceIdentity(
      deviceId: pairingIdentity.deviceId,
      packetIdentity: await PacketIdentity.fromPrivateKeyBytes(
        pairingIdentity.privateKeyBytes,
      ),
    );
  }
}
