import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:dartloom_pairing/qr_adapters.dart';

import '../l10n/app_localizations.dart';
import '../features/actent_core/actent_store.dart';
import '../features/actent_core/actent_home_page.dart';
import '../features/actent_core/actent_router.dart';
import '../features/actent_core/actent_transport.dart';
import '../features/pairing/pairing.dart';
import '../features/pairing/pairing_relay.dart';
import '../features/actent_core/attachment_retention.dart';
import '../features/actent_platform/android_share_bridge.dart';
import '../features/work/desktop/desktop_script_runner.dart';
import '../features/work/work_runner.dart';

class DartloomApp extends StatefulWidget {
  const DartloomApp({
    super.key,
    this.repository,
    this.shareBridge,
    this.deviceId,
    this.publicKey,
    this.relayTopic,
    this.relayServer,
    this.relayAuthorizationConfigured = false,
    this.onRelaySettingsChanged,
    this.lanHost,
    this.lanPort,
    this.lanCertificateSha256,
    this.lanServerConfig,
    this.pairingDiscovery,
    this.pairingHandshake,
    this.attachmentRetention,
    this.initialAttachmentRetention = AttachmentRetention.sevenDays,
    this.onAttachmentRetentionChanged,
    this.initialPacketDedupRetention = const Duration(days: 7),
    this.onPacketDedupRetentionChanged,
    this.desktopSecrets,
    this.router,
    this.queue,
    this.locale,
    this.onLocaleChanged,
  });

  final ActentRepository? repository;
  final AndroidShareBridge? shareBridge;
  final String? deviceId;
  final String? publicKey;
  final String? relayTopic;
  final Uri? relayServer;
  final bool relayAuthorizationConfigured;
  final Future<void> Function(Uri server, String? authorization)?
  onRelaySettingsChanged;
  final String? lanHost;
  final int? lanPort;
  final String? lanCertificateSha256;
  final ActentLanServerConfig? lanServerConfig;
  final PairingDiscovery? pairingDiscovery;
  final PairingRelayHandshake? pairingHandshake;
  final AttachmentRetentionManager? attachmentRetention;
  final AttachmentRetention initialAttachmentRetention;
  final Future<void> Function(AttachmentRetention value)?
  onAttachmentRetentionChanged;
  final Duration initialPacketDedupRetention;
  final Future<void> Function(Duration value)? onPacketDedupRetentionChanged;
  final DesktopSecretResolver? desktopSecrets;
  final ActentRouter? router;
  final WorkQueueCoordinator? queue;
  final Locale? locale;
  final Future<void> Function(Locale locale)? onLocaleChanged;

  @override
  State<DartloomApp> createState() => _DartloomAppState();
}

class _DartloomAppState extends State<DartloomApp> {
  Locale? _locale;

  @override
  void initState() {
    super.initState();
    _locale = widget.locale;
  }

  Future<void> _changeLocale(Locale locale) async {
    await widget.onLocaleChanged?.call(locale);
    if (mounted) setState(() => _locale = locale);
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    onGenerateTitle: (context) => AppLocalizations.of(context)!.appTitle,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: _locale,
    theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
    home: ActentHomePage(
      repository: widget.repository,
      shareBridge: widget.shareBridge,
      deviceId: widget.deviceId,
      publicKey: widget.publicKey,
      relayTopic: widget.relayTopic,
      relayServer: widget.relayServer,
      relayAuthorizationConfigured: widget.relayAuthorizationConfigured,
      onRelaySettingsChanged: widget.onRelaySettingsChanged,
      lanHost: widget.lanHost,
      lanPort: widget.lanPort,
      lanCertificateSha256: widget.lanCertificateSha256,
      lanServerConfig: widget.lanServerConfig,
      pairingDiscovery: widget.pairingDiscovery,
      pairingHandshake: widget.pairingHandshake,
      attachmentRetention: widget.attachmentRetention,
      initialAttachmentRetention: widget.initialAttachmentRetention,
      onAttachmentRetentionChanged: widget.onAttachmentRetentionChanged,
      initialPacketDedupRetention: widget.initialPacketDedupRetention,
      onPacketDedupRetentionChanged: widget.onPacketDedupRetentionChanged,
      router: widget.router,
      queue: widget.queue,
      onLocaleChanged: _changeLocale,
      canEditWorks:
          kIsWeb ||
          defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.macOS,
      desktopSecrets: widget.desktopSecrets,
      showPairingQr: (context, invite) =>
          FlutterQrCodePresenter(context).show(invite),
      scanPairingQr:
          defaultTargetPlatform == TargetPlatform.android ||
              defaultTargetPlatform == TargetPlatform.iOS
          ? (context) => MobileScannerQrScanner(context).scan()
          : null,
    ),
  );
}
