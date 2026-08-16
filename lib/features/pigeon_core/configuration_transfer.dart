import 'pigeon_models.dart';
import 'pigeon_store.dart';

const _configurationVersion = 1;

class PigeonConfigurationTransfer {
  const PigeonConfigurationTransfer(this.repository);

  final PigeonRepository repository;

  Future<Map<String, Object?>> export() async => <String, Object?>{
    'version': _configurationVersion,
    'works': [
      for (final work in await repository.listWorks()) _sanitize(work.toJson()),
    ],
    'devices': [
      for (final device in await repository.listDevices())
        _sanitize(device.toJson()),
    ],
  };

  Future<void> import(Object? value) async {
    if (value is! Map) {
      throw const PigeonValidationException(
        'configuration',
        'must be an object',
      );
    }
    final json = Map<String, Object?>.from(value);
    if (json['version'] != _configurationVersion) {
      throw PigeonValidationException(
        'configuration.version',
        'unsupported version ${json['version']}',
      );
    }
    final works = _documents(json['works'], 'works').map(Work.fromJson);
    final devices = _documents(json['devices'], 'devices').map(Device.fromJson);
    for (final work in works) {
      await repository.saveWork(work);
    }
    for (final device in devices) {
      // Endpoint configuration can be restored, but a restored installation
      // must re-pair before it can authorize a remote device.
      await repository.saveDevice(
        Device(
          id: device.id,
          displayName: device.displayName,
          platform: device.platform,
          publicKey: device.publicKey,
          endpoint: device.endpoint,
          pairedAt: device.pairedAt,
          authorized: false,
        ),
      );
    }
  }
}

List<Map<String, Object?>> _documents(Object? value, String field) {
  if (value is! List || value.any((item) => item is! Map)) {
    throw PigeonValidationException(field, 'must be an array of objects');
  }
  return [for (final item in value) Map<String, Object?>.from(item as Map)];
}

Object? _sanitize(Object? value, [String? key]) {
  if (key != null && _isSensitiveKey(key)) return null;
  if (value is Map) {
    return <String, Object?>{
      for (final entry in value.entries)
        if (entry.key is String && !_isSensitiveKey(entry.key as String))
          entry.key as String: _sanitize(entry.value, entry.key as String),
    };
  }
  if (value is List) {
    return [for (final item in value) _sanitize(item)];
  }
  return value;
}

bool _isSensitiveKey(String key) {
  final normalized = key.toLowerCase();
  return normalized == 'environment' ||
      normalized.contains('secret') ||
      normalized.contains('token') ||
      normalized.contains('password') ||
      normalized.contains('private') ||
      normalized.contains('credential') ||
      normalized == 'authorization';
}
