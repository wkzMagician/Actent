import 'dart:async';

import 'package:dartloom_resident/dartloom_resident.dart';
import 'package:dartloom_singleton/dartloom_singleton.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:dartloom_storage/dartloom_storage.dart';
import 'package:dartloom_settings_secure_storage/dartloom_settings_secure_storage.dart';
import 'package:dartloom_settings_shared_preferences/dartloom_settings_shared_preferences.dart';

import 'app/app.dart';
import 'app/attachment_directory.dart';
import 'app/object_store_factory.dart';
import 'app/platform_services.dart';
import 'app/actent_dependencies.dart';
import 'app/resident_configuration.dart';
import 'app/pairing_configuration.dart';
import 'features/actent_core/attachment_retention.dart';
import 'features/actent_core/device_identity.dart';
import 'features/actent_core/actent_models.dart';
import 'features/actent_core/actent_router.dart';
import 'features/actent_core/actent_transport.dart';
import 'features/pairing/pairing_relay.dart';
import 'features/pairing/pairing.dart';
import 'features/actent_core/secret_repository.dart';
import 'features/actent_platform/android_share_bridge.dart';
import 'features/work/work_runner.dart';
import 'l10n/app_localizations.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _StartupGate());
}

const _startupTimeout = Duration(seconds: 30);

Future<T> _startupStep<T>(Future<T> operation, String name) =>
    operation.timeout(
      _startupTimeout,
      onTimeout: () => throw TimeoutException(
        'Actent startup timed out while $name.',
        _startupTimeout,
      ),
    );

Future<void> _disposeStartupResources({
  required SingleInstanceService? singleInstance,
  required ActentTransportService? transport,
  required ResidentService? resident,
  required ObjectStore? objectStore,
}) async {
  try {
    await transport?.stop().timeout(const Duration(milliseconds: 600));
  } on Object {
    // Cleanup must not hide the original startup error.
  }
  try {
    await resident?.dispose();
  } on Object {
    // Cleanup must not hide the original startup error.
  }
  try {
    await singleInstance?.dispose();
  } on Object {
    // Cleanup must not hide the original startup error.
  }
  try {
    await objectStore?.close();
  } on Object {
    // Cleanup must not hide the original startup error.
  }
}

Future<DartloomApp> _createApplication() async {
  final singleInstance = createSingleInstanceService();
  ObjectStore? objectStore;
  ActentTransportService? transport;
  ResidentService? resident;
  try {
    if (singleInstance != null) {
      await _startupStep(
        singleInstance.ensureSingleInstance(),
        'claiming the single-instance lock',
      );
    }
    final appSettings = SharedPreferencesSettingsStore();
    final secretSettings = const SecureSettingsStore();
    final openedObjectStore = await _startupStep(
      openActentObjectStore(),
      'opening local storage',
    );
    objectStore = openedObjectStore;
    final savedLocale = await _startupStep(
      appSettings.read('app.locale'),
      'reading preferences',
    );
    final initialLocale = _localeFromCode(
      savedLocale is String ? savedLocale : null,
    );
    final repository = createActentRepository(openedObjectStore);
    final secretRepository = ActentSecretRepository(secretSettings);
    final identity = await _startupStep(
      DeviceIdentityRepository(secretRepository).loadOrCreate(),
      'loading device identity',
    );
    final relay = await _startupStep(
      ActentRelaySettings.load(secretRepository),
      'loading relay settings',
    );
    final attachmentRoot = await _startupStep(
      resolveActentAttachmentDirectory(),
      'preparing attachments',
    );
    final lanServerConfig = await _startupStep(
      ActentLanServerConfig.fromEnvironment(),
      'preparing LAN settings',
    );
    final retentionPreferences = AttachmentRetentionPreferences(
      secretRepository,
    );
    final attachmentRetention = await _startupStep(
      retentionPreferences.load(),
      'loading attachment retention settings',
    );
    final dedupPreferences = PacketDedupRetentionPreferences(secretRepository);
    final packetDedupRetention = await _startupStep(
      dedupPreferences.load(),
      'loading packet retention settings',
    );
    final queue = WorkQueueCoordinator(repository: repository);
    transport = ActentTransportService(
      deviceId: identity.deviceId,
      identity: identity.packetIdentity,
      repository: repository,
      relay: relay,
      attachmentRoot: attachmentRoot,
      seenPacketRetention: packetDedupRetention,
      lanServerConfig: lanServerConfig,
    );
    final router = ActentRouter(
      deviceId: identity.deviceId,
      repository: repository,
      connection: transport,
      queue: queue,
    );
    await _startupStep(transport.start(router), 'starting transport');
    await _startupStep(
      repository.saveDevice(
        Device(
          id: identity.deviceId,
          displayName: 'Actent ${defaultTargetPlatform.name}',
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
      ),
      'saving local device information',
    );
    resident = await _startupStep(
      createResidentService(),
      'initializing the resident service',
    );
    final activeTransport = transport;
    final activeObjectStore = openedObjectStore;
    final application = DartloomApp(
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
      pairingDiscovery: MdnsPairingDiscovery(
        serviceName: actentMdnsServiceName,
      ),
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
    // Resident/tray setup is optional. Do not hold the first Flutter frame on
    // a platform plugin; a tray failure must not make the app look blank.
    unawaited(
      configureResidentMenu(
        resident: resident,
        onExitRequested: () async {
          try {
            await activeTransport.stop().timeout(
              const Duration(milliseconds: 600),
            );
          } on Object {
            // Exit must remain responsive even if a network subscription is slow.
          }
          await singleInstance?.dispose();
          await resident?.dispose();
          await activeObjectStore.close();
          return true;
        },
      ).catchError((error, stackTrace) {
        debugPrint('Failed to configure the resident menu: $error');
        debugPrintStack(stackTrace: stackTrace);
      }),
    );
    return application;
  } on Object {
    await _disposeStartupResources(
      singleInstance: singleInstance,
      transport: transport,
      resident: resident,
      objectStore: objectStore,
    );
    rethrow;
  }
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
    title: 'Actent',
    home: Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 24),
            Text(
              'Starting Actent…',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Preparing local services',
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
    title: 'Actent',
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
                'Actent failed to start',
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
