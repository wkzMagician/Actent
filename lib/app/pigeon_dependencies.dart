import 'package:dartloom_storage/dartloom_storage.dart';

import '../features/pigeon_core/pigeon_store.dart';
import '../features/pigeon_core/secret_repository.dart';
import '../features/work/desktop/desktop_script_runner.dart';

/// Application composition root for Pigeon Core storage.
///
/// Feature services receive [PigeonRepository] and remain independent of the
/// concrete Dartloom storage adapter.
PigeonRepository createPigeonRepository(ObjectStore store) =>
    PigeonRepository(ReplicaPigeonJsonStore(store));

class SettingsDesktopSecretResolver implements DesktopSecretResolver {
  const SettingsDesktopSecretResolver(this.secrets);

  final PigeonSecretRepository secrets;

  @override
  Future<String?> resolve(String name) => secrets.read(name);
}
