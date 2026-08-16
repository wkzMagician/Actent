import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:dartloom_runtime/dartloom_runtime.dart';
import 'package:dartloom_settings/dartloom_settings.dart';

import 'app/app.dart';
import 'app/pigeon_dependencies.dart';
import 'app/resident_configuration.dart';
import 'capabilities/bootstrap.dart';
import 'app/dartloom_replica_factory.dart';
import 'features/pigeon_core/attachment_retention.dart';
import 'features/pigeon_core/device_identity.dart';
import 'features/pigeon_core/pigeon_models.dart';
import 'features/pigeon_core/pigeon_router.dart';
import 'features/pigeon_core/pigeon_transport.dart';
import 'features/pairing/pairing_relay.dart';
import 'features/pairing/pairing.dart';
import 'features/pigeon_core/secret_repository.dart';
import 'features/pigeon_platform/android_share_bridge.dart';
import 'features/work/work_runner.dart';
import 'l10n/app_localizations.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _StartupGate());
}

Future<DartloomApp> _createApplication() async {
  await bootstrapDartloom(customFactories: dartloomApplicationFactories);
  final appSettings = Dartloom.get<SettingsStore>(name: 'default');
  final savedLocale = await appSettings.read('app.locale');
  final initialLocale = _localeFromCode(
    savedLocale is String ? savedLocale : null,
  );
  final repository = createPigeonRepository();
  final secretRepository = PigeonSecretRepository(
    Dartloom.get<SettingsStore>(name: 'sync_secrets'),
  );
  final identity = await DeviceIdentityRepository(secretRepository)
      .loadOrCreate();
  final relay = await PigeonRelaySettings.load(secretRepository);
  final attachmentRoot = await resolvePigeonAttachmentDirectory();
  final lanServerConfig = await PigeonLanServerConfig.fromEnvironment();
  final retentionPreferences = AttachmentRetentionPreferences(secretRepository);
  final attachmentRetention = await retentionPreferences.load();
  final dedupPreferences = PacketDedupRetentionPreferences(secretRepository);
  final packetDedupRetention = await dedupPreferences.load();
  final queue = WorkQueueCoordinator(repository: repository);
  final transport = PigeonTransportService(
    deviceId: identity.deviceId,
    identity: identity.packetIdentity,
    repository: repository,
    relay: relay,
    attachmentRoot: attachmentRoot,
    seenPacketRetention: packetDedupRetention,
    lanServerConfig: lanServerConfig,
  );
  final router = PigeonRouter(
    deviceId: identity.deviceId,
    repository: repository,
    connection: transport,
    queue: queue,
  );
  await transport.start(router);
  await repository.saveDevice(
    Device(
      id: identity.deviceId,
      displayName: 'Pigeon ${defaultTargetPlatform.name}',
      platform: defaultTargetPlatform.name,
      publicKey: identity.publicKey,
      endpoint: {
        'relayUrl': relay.server.toString(),
        'relayTopic': relay.topic,
        if (transport.lanHost != null) 'lanHost': transport.lanHost,
        if (transport.lanPort != null) 'lanPort': transport.lanPort,
        if (transport.lanCertificateSha256 != null)
          'certificateSha256': transport.lanCertificateSha256,
      },
    ),
  );
  await configureResidentMenu(
    onExitRequested: () async {
      try {
        await transport.stop().timeout(const Duration(milliseconds: 600));
      } on Object {
        // Exit must remain responsive even if a network subscription is slow.
      }
      return true;
    },
  );
  return DartloomApp(
    locale: initialLocale,
    onLocaleChanged: (locale) =>
        appSettings.write('app.locale', locale.languageCode),
    repository: repository,
    deviceId: identity.deviceId,
    publicKey: identity.publicKey,
    relayTopic: relay.topic,
    relayServer: relay.server,
    relayAuthorizationConfigured: relay.authorization != null,
    onRelaySettingsChanged: (server, authorization) async {
      await secretRepository.write('relay.server', server.toString());
      if (authorization == null || authorization.isEmpty) {
        await secretRepository.remove('relay.authorization');
      } else {
        await secretRepository.write('relay.authorization', authorization);
      }
    },
    lanHost: transport.lanHost,
    lanPort: transport.lanPort,
    lanCertificateSha256: transport.lanCertificateSha256,
    lanServerConfig: lanServerConfig,
    pairingDiscovery: MdnsPairingDiscovery(),
    pairingHandshake: PairingRelayHandshake(
      server: relay.server,
      authorization: relay.authorization,
    ),
    attachmentRetention: AttachmentRetentionManager(
      repository: repository,
      root: attachmentRoot,
    ),
    initialAttachmentRetention: attachmentRetention,
    onAttachmentRetentionChanged: retentionPreferences.save,
    initialPacketDedupRetention: packetDedupRetention,
    onPacketDedupRetentionChanged: dedupPreferences.save,
    router: router,
    queue: queue,
    desktopSecrets: SettingsDesktopSecretResolver(secretRepository),
    shareBridge: defaultTargetPlatform == TargetPlatform.android
        ? AndroidShareBridge()
        : null,
  );
}

Locale? _localeFromCode(String? code) {
  if (code == null) return null;
  return AppLocalizations.supportedLocales.cast<Locale?>().firstWhere(
    (locale) => locale?.languageCode == code,
    orElse: () => null,
  );
}

class _StartupGate extends StatefulWidget {
  const _StartupGate();

  @override
  State<_StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<_StartupGate> {
  late final Future<DartloomApp> _application;

  @override
  void initState() {
    super.initState();
    _application = _createApplication();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<DartloomApp>(
    future: _application,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return _StartupError(error: snapshot.error!);
      }
      if (snapshot.hasData) return snapshot.data!;
      return const _StartupLoading();
    },
  );
}

class _StartupLoading extends StatelessWidget {
  const _StartupLoading();

  @override
  Widget build(BuildContext context) => MaterialApp(
    onGenerateTitle: (context) => AppLocalizations.of(context)!.appTitle,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 24),
            Text(
              AppLocalizations.of(context)!.startupLoading,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              AppLocalizations.of(context)!.startupPreparing,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    ),
  );
}

class _StartupError extends StatelessWidget {
  const _StartupError({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) => MaterialApp(
    onGenerateTitle: (context) => AppLocalizations.of(context)!.appTitle,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 56),
              const SizedBox(height: 16),
              Text(
                AppLocalizations.of(context)!.startupFailed,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              Text(error.toString(), textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    ),
  );
}
