import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:dartloom_pairing/qr_adapters.dart';
import 'package:dartloom_external_input/dartloom_external_input.dart';

import '../l10n/app_localizations.dart';
import '../features/actent_core/actent_store.dart';
import '../features/actent_core/actent_home_page.dart';
import '../features/actent_core/actent_router.dart';
import '../features/actent_core/actent_transport.dart';
import '../features/pairing/pairing.dart';
import '../features/pairing/pairing_relay.dart';
import '../features/actent_core/attachment_retention.dart';
import '../features/actent_platform/android_share_bridge.dart';
import '../features/actent_core/actent_models.dart';
import '../features/incoming/incoming_content_service.dart';
import '../features/work/desktop/desktop_script_runner.dart';
import '../features/work/work_runner.dart';
import 'pairing_qr_presenter.dart';
import 'clipboard_external_input_service.dart';

class DartloomApp extends StatefulWidget {
  const DartloomApp({
    super.key,
    this.repository,
    this.shareBridge,
    this.deviceId,
    this.deviceDisplayName,
    this.publicKey,
    this.relayTopic,
    this.relayBlobTopic,
    this.relayServer,
    this.relayTokenConfigured = false,
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
    this.pickWorkInputFile,
    this.externalInputService,
    this.clipboardExternalInputService,
    this.incomingContentService,
    this.peerConnectionStatuses,
    this.probePeerConnections,
    this.connectPeerConnection,
    this.locale,
    this.onLocaleChanged,
  });

  final ActentRepository? repository;
  final AndroidShareBridge? shareBridge;
  final String? deviceId;
  final String? deviceDisplayName;
  final String? publicKey;
  final String? relayTopic;
  final String? relayBlobTopic;
  final Uri? relayServer;
  final bool relayTokenConfigured;
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
  final Future<ActentMessage?> Function()? pickWorkInputFile;
  final ExternalInputService? externalInputService;
  final ClipboardExternalInputService? clipboardExternalInputService;
  final IncomingContentService? incomingContentService;
  final Stream<PeerConnectionStatus>? peerConnectionStatuses;
  final Future<void> Function()? probePeerConnections;
  final Future<void> Function(String deviceId)? connectPeerConnection;
  final Locale? locale;
  final Future<void> Function(Locale locale)? onLocaleChanged;

  @override
  State<DartloomApp> createState() => _DartloomAppState();
}

class _DartloomAppState extends State<DartloomApp> with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(widget.clipboardExternalInputService?.poll());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(widget.clipboardExternalInputService?.dispose());
    super.dispose();
  }

  Locale? _locale;

  @override
  void initState() {
    super.initState();
    _locale = widget.locale;
    WidgetsBinding.instance.addObserver(this);
    final clipboard = widget.clipboardExternalInputService;
    if (clipboard != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(clipboard.poll());
      });
    }
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
      deviceDisplayName: widget.deviceDisplayName,
      publicKey: widget.publicKey,
      relayTopic: widget.relayTopic,
      relayBlobTopic: widget.relayBlobTopic,
      relayServer: widget.relayServer,
      relayTokenConfigured: widget.relayTokenConfigured,
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
      pickWorkInputFile: widget.pickWorkInputFile,
      externalInputService: widget.externalInputService,
      incomingContentService: widget.incomingContentService,
      peerConnectionStatuses: widget.peerConnectionStatuses,
      probePeerConnections: widget.probePeerConnections,
      connectPeerConnection: widget.connectPeerConnection,
      onLocaleChanged: _changeLocale,
      canEditWorks:
          kIsWeb ||
          defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.macOS,
      desktopSecrets: widget.desktopSecrets,
      showPairingQr: showActentPairingQr,
      scanPairingQr:
          defaultTargetPlatform == TargetPlatform.android ||
              defaultTargetPlatform == TargetPlatform.iOS
          ? (context) => MobileScannerQrScanner(context).scan()
          : null,
    ),
  );
}
