import 'dart:typed_data';

import 'package:dartloom_settings/dartloom_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pengion/features/pigeon_core/device_identity.dart';
import 'package:pengion/features/pigeon_core/secret_repository.dart';

void main() {
  test('stores secret bytes only in the secure settings contract', () async {
    final settings = MemorySettingsStore();
    final repository = PigeonSecretRepository(settings);
    final bytes = Uint8List.fromList([1, 2, 3, 4]);

    await repository.writeBytes('private-key', bytes);

    expect(await repository.readBytes('private-key'), bytes);
    expect(await settings.read('pigeon.secret.private-key'), isA<String>());
    await repository.remove('private-key');
    expect(await repository.read('private-key'), isNull);
  });

  test('keeps a stable device identity in secure settings', () async {
    final settings = MemorySettingsStore();
    final repository = DeviceIdentityRepository(
      PigeonSecretRepository(settings),
    );

    final first = await repository.loadOrCreate();
    final second = await repository.loadOrCreate();

    expect(second.deviceId, first.deviceId);
    expect(second.publicKey, first.publicKey);
    expect(
      await settings.read('pigeon.secret.device.x25519.private'),
      isA<String>(),
    );
  });
}
