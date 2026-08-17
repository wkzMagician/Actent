import 'dart:convert';
import 'dart:typed_data';

import 'package:dartloom_settings/dartloom_settings.dart';

import '../pairing/pairing_identity.dart';

/// Secret values are deliberately kept behind the secure-settings capability;
/// this repository never writes them to the JSON business store.
class ActentSecretRepository implements PairingIdentityStore {
  ActentSecretRepository(this.settings, {this.prefix = 'actent.secret.'});

  final SettingsStore settings;
  final String prefix;

  @override
  Future<String?> read(String name) async {
    final value = await settings.read('$prefix$name');
    return value is String ? value : null;
  }

  @override
  Future<void> write(String name, String value) =>
      settings.write('$prefix$name', value);

  Future<void> remove(String name) => settings.remove('$prefix$name');

  Future<Uint8List?> readBytes(String name) async {
    final value = await read(name);
    return value == null ? null : Uint8List.fromList(base64Url.decode(value));
  }

  Future<void> writeBytes(String name, Uint8List value) =>
      write(name, base64UrlEncode(value));
}
