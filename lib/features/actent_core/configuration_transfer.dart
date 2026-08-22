import 'actent_models.dart';
import 'actent_store.dart';

const _configurationVersion = 1;

class ActentConfigurationTransfer {
  const ActentConfigurationTransfer(this.repository);

  final ActentRepository repository;

  Future<Map<String, Object?>> export() async => <String, Object?>{
    'version': _configurationVersion,
    'works': [for (final work in await repository.listWorks()) work.toJson()],
    'devices': [
      for (final device in await repository.listDevices()) device.toJson(),
    ],
  };

  Future<void> import(Object? value) async {
    if (value is! Map) {
      throw const ActentValidationException(
        'configuration',
        'must be an object',
      );
    }
    final json = Map<String, Object?>.from(value);
    if (json['version'] != _configurationVersion) {
      throw ActentValidationException(
        'configuration.version',
        'unsupported version ${json['version']}',
      );
    }
    final works = _documents(json['works'], 'works').map(Work.fromJson);
    final devices = _documents(json['devices'], 'devices').map(Device.fromJson);
    for (final work in works) {
      if (await repository.getWork(work.id) != null) continue;
      await repository.saveWork(work);
    }
    for (final device in devices) {
      if (await repository.getDevice(device.id) != null) continue;
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
    throw ActentValidationException(field, 'must be an array of objects');
  }
  return [for (final item in value) Map<String, Object?>.from(item as Map)];
}
