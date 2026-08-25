import 'dart:async';

import 'package:dartloom_resident/dartloom_resident.dart';
import 'package:dartloom_singleton/dartloom_singleton.dart';
import 'package:dartloom_external_input_android/dartloom_external_input_android.dart';
import 'package:dartloom_external_input_ios/dartloom_external_input_ios.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:dartloom_storage/dartloom_storage.dart';
import 'package:dartloom_messaging_ntfy/dartloom_messaging_ntfy.dart';
import 'package:dartloom_settings_secure_storage/dartloom_settings_secure_storage.dart';
import 'package:dartloom_settings_shared_preferences/dartloom_settings_shared_preferences.dart';

import 'app/app.dart';
import 'app/actent_logging.dart';
import 'app/attachment_directory.dart';
import 'app/actent_ios_clipboard_external_input_reader.dart';
import 'app/clipboard_external_input_service.dart';
import 'app/combined_external_input_service.dart';
import 'app/object_store_factory.dart';
import 'app/ios_open_url_external_input_service.dart';
import 'app/platform_services.dart';
import 'app/actent_dependencies.dart';
import 'app/resident_configuration.dart';
import 'app/pairing_configuration.dart';
import 'app/queued_external_input_service.dart';
import 'app/device_display_name.dart';
import 'features/actent_platform/work_input_file_picker.dart';
import 'features/actent_core/attachment_retention.dart';
import 'features/actent_core/device_identity.dart';
import 'features/actent_core/actent_models.dart';
import 'features/actent_core/actent_router.dart';
import 'features/actent_core/actent_store.dart';
import 'features/actent_core/actent_transport.dart';
import 'features/pairing/pairing_relay.dart';
import 'features/pairing/pairing.dart';
import 'features/actent_core/secret_repository.dart';
import 'features/actent_platform/android_share_bridge.dart';
import 'features/incoming/incoming_content_service.dart';
import 'features/work/work_runner.dart';
import 'l10n/app_localizations.dart';

Future<void> main([List<String> arguments = const []]) async {
  await runZonedGuarded(
    () async {
      // Flutter requires binding initialization and runApp to happen in the
      // same zone. This matters on desktop debug builds, where a zone mismatch
      // is reported as a framework error and the app never reaches its shell.
      WidgetsFlutterBinding.ensureInitialized();
      try {
        await openActentLogService();
        appLogger.info('Actent logging initialized.');
      } on Object {
        // Logging must not prevent the application from starting.
      }
      FlutterError.onError = (details) {
        FlutterError.presentError(details);
        try {
          appLogger.error(
            'Unhandled Flutter error.',
            details.exception,
            details.stack,
          );
        } on Object {
          // The error was already presented and logging is best effort.
        }
      };
      runApp(_StartupGate(externalArguments: arguments));
    },
    (error, stackTrace) {
      try {
        appLogger.error('Uncaught asynchronous error.', error, stackTrace);
      } on Object {
        // Logging must not become another uncaught error.
      }
    },
  );
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

Future<DartloomApp> _createApplication(List<String> externalArguments) async {
  final singleInstance = createSingleInstanceService();
  final argumentInputs = QueuedExternalInputService();
  argumentInputs.addFilePaths(externalArguments);
  final platformExternalInputService = switch (defaultTargetPlatform) {
    TargetPlatform.iOS => CombinedExternalInputService([
      IosExternalInputService(appGroupIdentifier: 'group.com.example.actent'),
      IosOpenUrlExternalInputService(),
    ]),
    TargetPlatform.android => AndroidExternalInputService(),
    _ => argumentInputs,
  };
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
    final initialClipboardChangeToken = await _startupStep(
      appSettings.read('externalInput.clipboard.changeToken'),
      'reading clipboard input state',
    );
    final clipboardExternalInputService = switch (defaultTargetPlatform) {
      TargetPlatform.iOS => ClipboardExternalInputService(
        reader: ActentIosClipboardExternalInputReader(),
        initialChangeToken: initialClipboardChangeToken is String
            ? initialClipboardChangeToken
            : null,
        saveChangeToken: (token) =>
            appSettings.write('externalInput.clipboard.changeToken', token),
      ),
      TargetPlatform.android => ClipboardExternalInputService(
        reader: AndroidClipboardExternalInputReader(),
        initialChangeToken: initialClipboardChangeToken is String
            ? initialClipboardChangeToken
            : null,
        saveChangeToken: (token) =>
            appSettings.write('externalInput.clipboard.changeToken', token),
      ),
      _ => null,
    };
    final externalInputService = clipboardExternalInputService == null
        ? platformExternalInputService
        : CombinedExternalInputService([
            platformExternalInputService,
            clipboardExternalInputService,
          ]);
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
    final deviceDisplayName = await _startupStep(
      resolveDeviceDisplayName(),
      'loading device name',
    );
    final relay = await _startupStep(
      ActentRelaySettings.load(secretRepository),
      'loading relay settings',
    );
    final attachmentRoot = kIsWeb
        ? null
        : await _startupStep(
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
    final queue = WorkQueueCoordinator(
      repository: repository,
      logger: appLogger,
    );
    transport = ActentTransportService(
      deviceId: identity.deviceId,
      identity: identity.packetIdentity,
      repository: repository,
      relay: relay,
      attachmentRoot: attachmentRoot,
      attachmentStore: openedObjectStore,
      seenPacketRetention: packetDedupRetention,
      lanServerConfig: lanServerConfig,
      readAttachment: kIsWeb
          ? (handle) async {
              const prefix = 'actent-indexeddb://';
              if (!handle.startsWith(prefix)) return null;
              return openedObjectStore.read(handle.substring(prefix.length));
            }
          : null,
      writeAttachment: kIsWeb
          ? (messageId, attachmentId, bytes) async {
              final key = 'attachments/$messageId/$attachmentId';
              await openedObjectStore.write(key, Uint8List.fromList(bytes));
              return 'actent-indexeddb://$key';
            }
          : null,
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
          displayName: deviceDisplayName,
          platform: defaultTargetPlatform.name,
          publicKey: identity.publicKey,
          endpoint: {
            'relayUrl': relay.server.toString(),
            'relayTopic': relay.controlTopic,
            'relayBlobTopic': relay.blobTopic,
            if (transport.lanHost != null) 'lanHost': transport.lanHost,
            if (transport.lanPort != null) 'lanPort': transport.lanPort,
            if (transport.lanCertificateSha256 != null)
              'certificateSha256': transport.lanCertificateSha256,
          },
        ),
      ),
      'saving local device information',
    );
    unawaited(_publishDeviceUpdate(router, repository, identity.deviceId));
    unawaited(_publishCatalogSnapshots(router));
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
      deviceDisplayName: deviceDisplayName,
      publicKey: identity.publicKey,
      relayTopic: relay.controlTopic,
      relayBlobTopic: relay.blobTopic,
      relayServer: relay.server,
      relayTokenConfigured: relay.token != null,
      onRelaySettingsChanged: (server, token) async {
        await secretRepository.write('relay.v2.server', server.toString());
        if (token == null || token.isEmpty) {
          await secretRepository.remove('relay.v2.token');
        } else {
          NtfyCredentials(token);
          await secretRepository.write('relay.v2.token', token);
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
        token: relay.token,
      ),
      attachmentRetention: attachmentRoot == null
          ? null
          : AttachmentRetentionManager(
              repository: repository,
              root: attachmentRoot,
            ),
      initialAttachmentRetention: attachmentRetention,
      onAttachmentRetentionChanged: retentionPreferences.save,
      initialPacketDedupRetention: packetDedupRetention,
      onPacketDedupRetentionChanged: dedupPreferences.save,
      router: router,
      queue: queue,
      pickWorkInputFile: switch (defaultTargetPlatform) {
        TargetPlatform.android ||
        TargetPlatform.iOS ||
        TargetPlatform.windows ||
        TargetPlatform.linux ||
        TargetPlatform.macOS => () => pickLocalWorkInputFile(
          attachmentDirectory: attachmentRoot!.path,
          deviceId: identity.deviceId,
        ),
        _ when kIsWeb => () => pickLocalWorkInputFile(
          attachmentStore: openedObjectStore,
          deviceId: identity.deviceId,
        ),
        _ => null,
      },
      externalInputService: externalInputService,
      clipboardExternalInputService: clipboardExternalInputService,
      incomingContentService: attachmentRoot == null
          ? null
          : IncomingContentService(
              deviceId: identity.deviceId,
              importFiles: (paths) => importLocalWorkInputFiles(
                paths: paths,
                attachmentDirectory: attachmentRoot.path,
                deviceId: identity.deviceId,
              ),
            ),
      peerConnectionStatuses: transport.peerConnectionStatuses,
      probePeerConnections: transport.probePeers,
      connectPeerConnection: transport.probePeer,
      desktopSecrets: SettingsDesktopSecretResolver(secretRepository),
      shareBridge: defaultTargetPlatform == TargetPlatform.android
          ? AndroidShareBridge()
          : null,
    );
    await singleInstance?.configure(
      SingleInstanceConfiguration(
        onArgs: (args) async => argumentInputs.addFilePaths(args),
      ),
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
          await argumentInputs.dispose();
          await resident?.dispose();
          await activeObjectStore.close();
          return true;
        },
      ).catchError((error, stackTrace) {
        appLogger.error(
          'Failed to configure the resident menu.',
          error,
          stackTrace,
        );
        debugPrint('Failed to configure the resident menu: $error');
        debugPrintStack(stackTrace: stackTrace);
      }),
    );
    return application;
  } on Object {
    await argumentInputs.dispose();
    await _disposeStartupResources(
      singleInstance: singleInstance,
      transport: transport,
      resident: resident,
      objectStore: objectStore,
    );
    rethrow;
  }
}

Future<void> _publishDeviceUpdate(
  ActentRouter router,
  ActentRepository repository,
  String localDeviceId,
) async {
  for (final device in await repository.listDevices()) {
    if (!device.authorized || device.id == localDeviceId) continue;
    try {
      await router.sendDeviceUpdate(device.id);
    } on Object {
      // A peer that is temporarily offline receives the next update when the
      // app starts or when pairing/catalog synchronization occurs.
    }
  }
}

Future<void> _publishCatalogSnapshots(ActentRouter router) async =>
    router.publishCatalogSnapshotToPeers();

Locale? _localeFromCode(String? code) {
  if (code == null) return null;
  return AppLocalizations.supportedLocales.cast<Locale?>().firstWhere(
    (locale) => locale?.languageCode == code,
    orElse: () => null,
  );
}

class _StartupGate extends StatefulWidget {
  const _StartupGate({this.externalArguments = const []});

  final List<String> externalArguments;

  @override
  State<_StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<_StartupGate> {
  late final Future<DartloomApp> _application;

  @override
  void initState() {
    super.initState();
    _application = _createApplication(widget.externalArguments);
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
