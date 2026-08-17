import 'package:dartloom_storage/dartloom_storage.dart';

import '../features/actent_core/actent_store.dart';
import '../features/actent_core/secret_repository.dart';
import '../features/work/desktop/desktop_script_runner.dart';

/// Application composition root for Actent Core storage.
///
/// Feature services receive [ActentRepository] and remain independent of the
/// concrete Dartloom storage adapter.
ActentRepository createActentRepository(ObjectStore store) =>
    ActentRepository(ReplicaActentJsonStore(store));

class SettingsDesktopSecretResolver implements DesktopSecretResolver {
  const SettingsDesktopSecretResolver(this.secrets);

  final ActentSecretRepository secrets;

  @override
  Future<String?> resolve(String name) => secrets.read(name);
}
