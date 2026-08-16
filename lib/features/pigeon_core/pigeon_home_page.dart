import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';

import '../pigeon_platform/android_share_bridge.dart';
import '../pairing/pairing.dart';
import '../pairing/lan_pairing.dart';
import '../pairing/pairing_relay.dart';
import '../work/desktop/desktop_script_runner.dart';
import '../work/android/android_work_runner.dart';
import '../work/work_bindings.dart';
import '../work/work_runner.dart';
import 'pigeon_router.dart';
import 'pigeon_transport.dart';
import 'pigeon_models.dart';
import 'configuration_transfer.dart';
import 'attachment_retention.dart';
import 'pigeon_store.dart';
import '../../l10n/app_localizations.dart';

class PigeonHomePage extends StatefulWidget {
  const PigeonHomePage({
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
    this.canEditWorks = false,
    this.desktopSecrets,
    this.router,
    this.queue,
    this.showPairingQr,
    this.scanPairingQr,
    this.onLocaleChanged,
  });

  final PigeonRepository? repository;
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
  final PigeonLanServerConfig? lanServerConfig;
  final PairingDiscovery? pairingDiscovery;
  final PairingRelayHandshake? pairingHandshake;
  final AttachmentRetentionManager? attachmentRetention;
  final AttachmentRetention initialAttachmentRetention;
  final Future<void> Function(AttachmentRetention value)?
  onAttachmentRetentionChanged;
  final Duration initialPacketDedupRetention;
  final Future<void> Function(Duration value)? onPacketDedupRetentionChanged;
  final bool canEditWorks;
  final DesktopSecretResolver? desktopSecrets;
  final PigeonRouter? router;
  final WorkQueueCoordinator? queue;
  final Future<void> Function(BuildContext context, String invite)?
  showPairingQr;
  final Future<String?> Function(BuildContext context)? scanPairingQr;
  final Future<void> Function(Locale locale)? onLocaleChanged;

  @override
  State<PigeonHomePage> createState() => _PigeonHomePageState();
}

class _PigeonHomePageState extends State<PigeonHomePage> {
  var _selectedIndex = 0;
  final List<PigeonMessage> _messages = [];
  final List<Work> _works = [];
  final List<Device> _devices = [];
  final Map<String, WorkReceiptStatus> _messageStatuses = {};
  final PairingCoordinator _pairing = PairingCoordinator();
  StreamSubscription<PigeonMessage>? _shareSubscription;
  StreamSubscription<PairingAcceptance>? _pairingAcceptanceSubscription;
  LanPairingServer? _lanPairingServer;
  MdnsPairingAdvertiser? _lanPairingAdvertiser;
  WorkQueueCoordinator? _queue;
  AttachmentRetention _retention = AttachmentRetention.sevenDays;
  late Duration _packetDedupRetention;

  List<_PigeonPageData> _pages(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return [
      _PigeonPageData(
        title: l10n.inbox,
        icon: Icons.inbox_outlined,
        message: l10n.inboxDescription,
      ),
      _PigeonPageData(
        title: l10n.works,
        icon: Icons.work_outline,
        message: l10n.worksDescription,
      ),
      _PigeonPageData(
        title: l10n.devices,
        icon: Icons.devices_outlined,
        message: l10n.devicesDescription,
      ),
      _PigeonPageData(
        title: l10n.settings,
        icon: Icons.settings_outlined,
        message: l10n.settingsDescription,
      ),
    ];
  }

  @override
  void initState() {
    super.initState();
    _retention = widget.initialAttachmentRetention;
    _packetDedupRetention = widget.initialPacketDedupRetention;
    final bridge = widget.shareBridge;
    if (bridge != null) {
      _shareSubscription = bridge.messages.listen(_onSharedMessage);
    }
    final repository = widget.repository;
    if (repository != null) {
      _queue = widget.queue ?? WorkQueueCoordinator(repository: repository);
      _queue!.register('local-null', const NullWorkRunner());
      _queue!.addReceiptListener(_onReceipt);
      _loadRepositoryData(repository);
    }
  }

  Future<void> _loadRepositoryData(PigeonRepository repository) async {
    final messages = await repository.listMessages();
    var works = await repository.listWorks();
    if (widget.shareBridge != null &&
        !works.any((work) => work.id == 'android-share')) {
      final shareWork = Work(
        id: 'android-share',
        revision: 1,
        name: 'Android Share',
        ownerDeviceId: widget.deviceId ?? 'local-device',
        acceptedContentTypes: PigeonContentType.values.toSet(),
        platformBindings: const {
          'kind': 'android-intent',
          'action': 'android.intent.action.SEND',
          'categories': <String>[],
          'extras': <String, Object?>{},
          'chooser': true,
          'attachmentPlacement': 'streams',
        },
      );
      await repository.saveWork(shareWork);
      works = [...works, shareWork];
    }
    final devices = await repository.listDevices();
    final requests = await repository.listRequests();
    final receipts = await repository.listReceipts();
    final receiptsByRequest = {
      for (final receipt in receipts) receipt.requestId: receipt,
    };
    final statuses = <String, WorkReceiptStatus>{};
    for (final request in requests) {
      final receipt = receiptsByRequest[request.requestId];
      if (receipt != null) statuses[request.message.id] = receipt.status;
    }
    messages.sort((left, right) => right.createdAt.compareTo(left.createdAt));
    if (!mounted) return;
    setState(() {
      _messages
        ..clear()
        ..addAll(messages);
      _works
        ..clear()
        ..addAll(works);
      _devices
        ..clear()
        ..addAll(devices);
      _messageStatuses
        ..clear()
        ..addAll(statuses);
    });
    final queue = _queue;
    if (queue != null) {
      for (final work in works) {
        try {
          switch (work.platformBindings['kind']) {
            case 'null':
              queue.register(work.id, const NullWorkRunner());
            case 'desktop-script' when widget.canEditWorks:
              queue.register(
                work.id,
                DesktopScriptRunner(
                  config: DesktopScriptBinding.fromWork(work).toConfig(work),
                  secrets: widget.desktopSecrets,
                ),
              );
            case 'android-intent' when widget.shareBridge != null:
              final bridge = widget.shareBridge!;
              queue.register(
                work.id,
                AndroidIntentRunner(
                  spec: AndroidIntentBinding.fromWork(work).spec,
                  uriProvider: bridge.contentUriProvider,
                  launcher: bridge.intentLauncher,
                ),
              );
            case 'android-http' when widget.shareBridge != null:
              queue.register(
                work.id,
                AndroidHttpRunner(
                  spec: AndroidHttpBinding.fromWork(work).spec,
                  client: IoAndroidHttpClient(),
                  secrets: _AndroidSecretResolver(widget.desktopSecrets),
                ),
              );
          }
        } on WorkBindingException {
          // Invalid work definitions remain visible for correction in Works.
        }
      }
      await queue.restorePending(works);
    }
  }

  Future<void> _onReceipt(WorkReceipt receipt) async {
    final request = await widget.repository?.getRequest(receipt.requestId);
    if (!mounted || request == null) return;
    setState(() => _messageStatuses[request.message.id] = receipt.status);
  }

  @override
  void dispose() {
    _shareSubscription?.cancel();
    _pairingAcceptanceSubscription?.cancel();
    unawaited(_closeLanPairing());
    super.dispose();
  }

  Future<void> _onSharedMessage(PigeonMessage message) async {
    final repository = widget.repository;
    if (repository != null) {
      await repository.saveMessage(message);
    }
    if (!mounted) return;
    setState(() => _messages.insert(0, message));
    _showWorkPicker(message);
  }

  Future<void> _showWorkPicker(PigeonMessage message) async {
    final work = await showModalBottomSheet<Work>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
              title: Text('Choose Work'),
              subtitle: Text('Select where this shared content should go.'),
            ),
            for (final availableWork in _works.where(_isSelectableWork))
              ListTile(
                leading: const Icon(Icons.play_arrow_outlined),
                title: Text(availableWork.name),
                subtitle: Text(
                  '${availableWork.ownerDeviceId == (widget.deviceId ?? 'local-device') ? 'This device' : 'Remote device'} · revision ${availableWork.revision}',
                ),
                onTap: () => Navigator.of(context).pop(availableWork),
              ),
            ListTile(
              leading: const Icon(Icons.archive_outlined),
              title: const Text('Null — store locally'),
              onTap: () => Navigator.of(context).pop(
                Work.nullWork(
                  id: 'local-null',
                  ownerDeviceId: widget.deviceId ?? 'local-device',
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('Discard'),
              onTap: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
    if (work == null || !mounted) return;
    final repository = widget.repository;
    final queue = _queue;
    if (repository == null || queue == null) return;
    try {
      final router = widget.router;
      if (router != null) {
        await router.route(message, work, targetDeviceId: work.ownerDeviceId);
      } else {
        await repository.saveWork(work);
        final now = DateTime.now().toUtc();
        await queue.enqueue(
          work,
          WorkRequest(
            requestId: 'share-${now.microsecondsSinceEpoch}',
            message: message,
            workId: work.id,
            workRevision: work.revision,
            sourceDeviceId: widget.deviceId ?? 'local-device',
            targetDeviceId: widget.deviceId ?? 'local-device',
            createdAt: now,
            expiresAt: now.add(work.timeout),
          ),
        );
      }
      await _loadRepositoryData(repository);
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Work request failed: $error')));
    }
  }

  bool _isSelectableWork(Work work) {
    final localId = widget.deviceId ?? 'local-device';
    if (work.ownerDeviceId == localId) return true;
    return _devices.any(
      (device) => device.id == work.ownerDeviceId && device.authorized,
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = _pages(context);
    final page = pages[_selectedIndex];
    final body = _selectedIndex == 0
        ? (_messages.isNotEmpty
              ? ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _messages.length,
                  itemBuilder: (context, index) {
                    final message = _messages[index];
                    return Card(
                      child: ListTile(
                        leading: const Icon(Icons.share_outlined),
                        title: Text(message.content.type.value),
                        subtitle: Text(
                          '${message.id}${_messageStatuses[message.id] == null ? '' : ' · ${_messageStatuses[message.id]!.value}'}',
                        ),
                        onTap: () => _showWorkPicker(message),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            PopupMenuButton<String>(
                              onSelected: (value) async {
                                if (value == 'retry') {
                                  await _showWorkPicker(message);
                                } else if (value == 'cancel') {
                                  await _cancelMessageRequests(message);
                                } else if (value == 'delete') {
                                  await _deleteMessage(message);
                                }
                              },
                              itemBuilder: (context) => const [
                                PopupMenuItem(
                                  value: 'retry',
                                  child: Text('Run again'),
                                ),
                                PopupMenuItem(
                                  value: 'cancel',
                                  child: Text('Cancel pending requests'),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Text('Delete message'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                )
              : _emptyPage(pages[0]))
        : _selectedIndex == 1
        ? _worksPage(context)
        : _selectedIndex == 2
        ? _devicesPage(context)
        : _settingsPage(context);
    return Scaffold(
      appBar: AppBar(title: Text(page.title)),
      body: body,
      floatingActionButton: _selectedIndex == 2
          ? FloatingActionButton.extended(
              onPressed: _showPairingActions,
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Pair device'),
            )
          : _selectedIndex == 1 && widget.canEditWorks
          ? FloatingActionButton.extended(
              onPressed: _addDesktopWork,
              icon: const Icon(Icons.add),
              label: const Text('Add Work'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) =>
            setState(() => _selectedIndex = index),
        destinations: [
          for (final item in pages)
            NavigationDestination(icon: Icon(item.icon), label: item.title),
        ],
      ),
    );
  }

  Widget _emptyPage(_PigeonPageData page) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              page.icon,
              size: 56,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 20),
            Text(
              page.message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
      ),
    ),
  );

  Widget _worksPage(BuildContext context) => _works.isEmpty
      ? _emptyPage(_pages(context)[1])
      : ListView(
          padding: const EdgeInsets.all(16),
          children: [
            for (final work in _works)
              Card(
                child: ListTile(
                  leading: Icon(
                    work.platformBindings['kind'] == 'null'
                        ? Icons.archive_outlined
                        : Icons.play_arrow_outlined,
                  ),
                  title: Text(work.name),
                  subtitle: Text(
                    '${work.id} · revision ${work.revision} · '
                    '${work.enabled ? 'enabled' : 'disabled'}',
                  ),
                  trailing:
                      work.ownerDeviceId ==
                              (widget.deviceId ?? 'local-device') &&
                          work.platformBindings['kind'] == 'desktop-script'
                      ? PopupMenuButton<String>(
                          onSelected: (value) async {
                            switch (value) {
                              case 'edit':
                                await _editDesktopWork(work);
                              case 'toggle':
                                await _toggleWork(work);
                              case 'delete':
                                await _deleteWork(work);
                            }
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'edit',
                              child: Text('Edit'),
                            ),
                            PopupMenuItem(
                              value: 'toggle',
                              child: Text(work.enabled ? 'Disable' : 'Enable'),
                            ),
                            const PopupMenuItem(
                              value: 'delete',
                              child: Text('Delete'),
                            ),
                          ],
                        )
                      : null,
                ),
              ),
          ],
        );

  Future<void> _addDesktopWork() => _editDesktopWork();

  Future<void> _editDesktopWork([Work? existing]) async {
    final values = await showDialog<(String, String, String)?>(
      context: context,
      builder: (dialogContext) {
        final name = TextEditingController(text: existing?.name ?? '');
        final executable = TextEditingController(
          text: existing?.platformBindings['executable'] as String? ?? '',
        );
        final arguments = TextEditingController(
          text:
              (existing?.platformBindings['arguments'] as List?)
                  ?.whereType<String>()
                  .join('\n') ??
              '',
        );
        return AlertDialog(
          title: Text(
            existing == null ? 'Add Script Work' : 'Edit Script Work',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                TextField(
                  controller: executable,
                  decoration: const InputDecoration(
                    labelText: 'Absolute executable path',
                  ),
                ),
                TextField(
                  controller: arguments,
                  decoration: const InputDecoration(
                    labelText: 'Arguments (one per line)',
                  ),
                  maxLines: 3,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(
                dialogContext,
              ).pop((name.text.trim(), executable.text.trim(), arguments.text)),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
    if (values == null || values.$1.isEmpty || values.$2.isEmpty) return;
    final id =
        existing?.id ?? 'script-${DateTime.now().microsecondsSinceEpoch}';
    final work = Work(
      id: id,
      revision: (existing?.revision ?? 0) + 1,
      name: values.$1,
      ownerDeviceId: widget.deviceId ?? 'local-device',
      allowedSourceDeviceIds: existing?.allowedSourceDeviceIds ?? const {},
      acceptedContentTypes: PigeonContentType.values.toSet(),
      timeout: existing?.timeout ?? const Duration(hours: 24),
      queueLimit: existing?.queueLimit ?? 10,
      enabled: existing?.enabled ?? true,
      platformBindings: {
        'kind': 'desktop-script',
        'executable': values.$2,
        'arguments': values.$3
            .split(RegExp(r'\r?\n'))
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty)
            .toList(),
        'environment': const <String, String>{},
        if (existing?.platformBindings['workingDirectory'] != null)
          'workingDirectory': existing!.platformBindings['workingDirectory'],
        if (existing?.platformBindings['secretEnvironment'] != null)
          'secretEnvironment': existing!.platformBindings['secretEnvironment'],
      },
      catalogVisibility: existing?.catalogVisibility ?? const {},
    );
    final repository = widget.repository;
    if (repository == null) return;
    try {
      await DesktopScriptBinding.fromWork(work).toConfig(work).validate();
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Work validation failed: $error')));
      return;
    }
    await repository.saveWork(work);
    final router = widget.router;
    if (router != null) {
      for (final device in _devices.where((device) => device.authorized)) {
        try {
          await router.sendCatalogDelta(device.id);
        } on Object {
          // A disconnected peer receives the latest catalog on its next
          // pairing/reconnect; local Work creation must still succeed.
        }
      }
    }
    await _loadRepositoryData(repository);
  }

  Future<void> _toggleWork(Work work) async {
    final repository = widget.repository;
    if (repository == null) return;
    await repository.saveWork(
      Work(
        id: work.id,
        revision: work.revision + 1,
        name: work.name,
        ownerDeviceId: work.ownerDeviceId,
        allowedSourceDeviceIds: work.allowedSourceDeviceIds,
        acceptedContentTypes: work.acceptedContentTypes,
        timeout: work.timeout,
        queueLimit: work.queueLimit,
        enabled: !work.enabled,
        platformBindings: work.platformBindings,
        catalogVisibility: work.catalogVisibility,
      ),
    );
    await _publishCatalogChanges();
    await _loadRepositoryData(repository);
  }

  Future<void> _deleteWork(Work work) async {
    final repository = widget.repository;
    if (repository == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Work?'),
        content: Text('Delete “${work.name}” and cancel pending requests?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    for (final request in await repository.listRequests()) {
      if (request.workId == work.id &&
          await repository.getReceipt(request.requestId) == null) {
        await widget.router?.cancelRequest(request.requestId);
      }
    }
    await repository.deleteWork(work.id);
    await _publishCatalogChanges();
    await _loadRepositoryData(repository);
  }

  Future<void> _publishCatalogChanges() async {
    final router = widget.router;
    if (router == null) return;
    for (final device in _devices.where((device) => device.authorized)) {
      try {
        await router.sendCatalogDelta(device.id);
      } on Object {
        // The next reconnect receives a fresh catalog snapshot.
      }
    }
  }

  Widget _devicesPage(BuildContext context) => _devices.isEmpty
      ? ListView(
          padding: const EdgeInsets.all(24),
          children: [
            _emptyPage(_pages(context)[2]),
            const SizedBox(height: 12),
            _pairingImportButton(),
          ],
        )
      : ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _pairingImportButton(),
            const SizedBox(height: 8),
            for (final device in _devices)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.devices_outlined),
                  title: Text(device.displayName),
                  subtitle: Text('${device.platform} · ${device.id}'),
                  trailing: Icon(
                    device.authorized ? Icons.verified_outlined : Icons.block,
                    color: device.authorized ? Colors.green : Colors.red,
                  ),
                  onTap: () => _unpairDevice(device),
                ),
              ),
          ],
        );

  Future<void> _unpairDevice(Device device) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove paired device?'),
        content: Text(
          'Remove ${device.displayName} and its remote Work catalog? '
          'Existing Inbox history is kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final repository = widget.repository;
    if (repository == null) return;
    for (final request in await repository.listRequests()) {
      if ((request.sourceDeviceId == device.id ||
              request.targetDeviceId == device.id) &&
          await repository.getReceipt(request.requestId) == null) {
        await widget.router?.cancelRequest(request.requestId);
      }
    }
    for (final work in await repository.listWorks()) {
      if (work.ownerDeviceId == device.id) {
        await repository.deleteWork(work.id);
      }
    }
    await repository.deleteDevice(device.id);
    await _loadRepositoryData(repository);
  }

  Widget _pairingImportButton() => Column(
    children: [
      if (widget.pairingDiscovery != null)
        OutlinedButton.icon(
          onPressed: _discoverLanDevices,
          icon: const Icon(Icons.wifi_find),
          label: const Text('Discover on LAN'),
        ),
      OutlinedButton.icon(
        onPressed: _importPairingInvite,
        icon: const Icon(Icons.content_paste_go),
        label: const Text('Paste invitation'),
      ),
      if (widget.scanPairingQr != null)
        OutlinedButton.icon(
          onPressed: _scanPairingInvite,
          icon: const Icon(Icons.qr_code_scanner),
          label: const Text('Scan QR invitation'),
        ),
    ],
  );

  Future<void> _discoverLanDevices() async {
    final discovery = widget.pairingDiscovery;
    if (discovery == null) return;
    try {
      final advertisements = await discovery
          .discover()
          .take(8)
          .toList()
          .timeout(
            const Duration(seconds: 4),
            onTimeout: () => <PairingAdvertisement>[],
          );
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      final selected = await showDialog<PairingAdvertisement>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Nearby Pigeon devices'),
          content: advertisements.isEmpty
              ? Text(l10n.lanNoDevices)
              : SizedBox(
                  width: 420,
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final advertisement in advertisements)
                        ListTile(
                          leading: const Icon(Icons.devices_outlined),
                          title: Text(advertisement.displayName),
                          subtitle: Text(
                            '${advertisement.platform} · '
                            '${advertisement.host ?? 'unknown host'}:'
                            '${advertisement.port ?? 0}',
                          ),
                          onTap: () =>
                              Navigator.of(dialogContext).pop(advertisement),
                        ),
                    ],
                  ),
                ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );
      if (selected != null) await _pairOverLan(selected);
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('LAN discovery failed: $error')));
    }
  }

  Future<void> _pairOverLan(PairingAdvertisement advertisement) async {
    final host = advertisement.host;
    final port = advertisement.port;
    if (host == null || port == null || port <= 0) {
      throw const PairingValidationException(
        'discovery result has no pairing endpoint',
      );
    }
    final client = LanPairingClient();
    final invite = await client.fetchInvite(host: host, port: port);
    if (advertisement.fingerprint.isNotEmpty &&
        _publicKeyFingerprint(invite.issuerPublicKey) !=
            advertisement.fingerprint) {
      throw const PairingValidationException(
        'LAN discovery public key does not match the invitation',
      );
    }
    if (!mounted) return;
    final code = await _requestPairingCode();
    if (code == null) return;
    final session = PairingSession(invite)
      ..accept(
        remoteDeviceId: invite.issuerDeviceId,
        remotePublicKey: invite.issuerPublicKey,
      );
    session.confirm(code);
    final confirmation = await client.sendAcceptance(
      invite: invite,
      host: host,
      port: port,
      deviceId: widget.deviceId ?? 'local-device',
      publicKey: widget.publicKey ?? 'local-public-key',
      displayName: 'Pigeon ${widget.deviceId ?? 'device'}',
      platform: 'paired',
      relayUrl: widget.pairingHandshake?.server.toString() ?? 'https://ntfy.sh',
      relayTopic: widget.relayTopic ?? '',
      lanHost: widget.lanHost,
      lanPort: widget.lanPort,
      serverCertificateSha256: invite.issuerCertificateSha256,
      certificateSha256: widget.lanCertificateSha256,
    );
    if (confirmation.nonce != invite.nonce) {
      throw const PairingValidationException(
        'LAN pairing confirmation nonce mismatch',
      );
    }
    await _savePairedDevice(
      invite,
      authorized: true,
      relayTopic: invite.issuerRelayTopic,
    );
  }

  Future<String?> _requestPairingCode() => showDialog<String>(
    context: context,
    builder: (dialogContext) {
      final controller = TextEditingController();
      return AlertDialog(
        title: const Text('Confirm LAN pairing code'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: '6-digit code'),
          keyboardType: TextInputType.number,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('Confirm'),
          ),
        ],
      );
    },
  );

  String _publicKeyFingerprint(String publicKey) {
    try {
      return sha256.convert(base64Url.decode(publicKey)).toString();
    } on FormatException {
      throw const PairingValidationException(
        'paired device public key is invalid',
      );
    }
  }

  Future<void> _showPairingActions() async {
    await _closeLanPairing();
    final pairingHandshake = widget.pairingHandshake;
    final lanConfig = widget.lanServerConfig;
    PairingSession? activeSession;
    LanPairingServer? lanServer;
    if (lanConfig != null) {
      lanServer = LanPairingServer(
        securityContext: lanConfig.securityContext,
        host: lanConfig.bindAddress,
        onRequest: (request) {
          final session = activeSession;
          if (session == null) {
            throw StateError('LAN pairing invitation is not ready');
          }
          return LanPairingRequestHandler(
            invite: session.invite,
            issuerDeviceId: widget.deviceId ?? 'local-device',
            onAccepted: (acceptance) =>
                _completeIssuerPairing(session, acceptance),
          ).handle(request);
        },
      );
      await lanServer.start();
    }
    final pairingPort = lanServer?.boundPort;
    if (lanServer != null && pairingPort == null) {
      await lanServer.close();
      throw StateError('LAN pairing server did not bind a port');
    }
    final session = _pairing.createInvite(
      issuerDeviceId: widget.deviceId ?? 'local-device',
      issuerPublicKey: widget.publicKey ?? 'local-public-key',
      relayUrl: pairingHandshake?.server.toString() ?? 'https://ntfy.sh',
      temporaryTopic: 'pigeon-pair-${DateTime.now().microsecondsSinceEpoch}',
      issuerRelayTopic: widget.relayTopic ?? '',
      issuerLanHost: widget.lanHost,
      issuerLanPort: widget.lanPort,
      issuerPairingLanPort: pairingPort,
      issuerCertificateSha256: widget.lanCertificateSha256,
    );
    activeSession = session;
    if (lanServer != null) {
      final advertiser = MdnsPairingAdvertiser(
        deviceId: widget.deviceId ?? 'local-device',
        displayName: 'Pigeon ${widget.deviceId ?? 'device'}',
        platform: 'paired',
        fingerprint: _publicKeyFingerprint(
          widget.publicKey ?? 'local-public-key',
        ),
        port: pairingPort!,
      );
      try {
        await advertiser.start();
        _lanPairingServer = lanServer;
        _lanPairingAdvertiser = advertiser;
      } on Object {
        await lanServer.close();
        rethrow;
      }
    }
    await _pairingAcceptanceSubscription?.cancel();
    if (pairingHandshake != null) {
      _pairingAcceptanceSubscription = pairingHandshake
          .listenForAcceptance(session.invite)
          .listen(
            (acceptance) =>
                unawaited(_completeIssuerPairing(session, acceptance)),
          );
    }
    final showQr = widget.showPairingQr;
    try {
      if (!mounted) return;
      if (showQr != null) {
        await showQr(context, session.invite.toUri());
      } else if (mounted) {
        await _showInviteText(session.invite.toUri());
      }
    } finally {
      // The relay confirmation can continue after the dialog closes, but the
      // LAN discovery advertisement and temporary pairing listener are scoped
      // to the explicit pairing UI.
      await _closeLanPairing();
    }
  }

  Future<void> _closeLanPairing() async {
    await _lanPairingAdvertiser?.stop();
    _lanPairingAdvertiser = null;
    await _lanPairingServer?.close();
    _lanPairingServer = null;
  }

  Future<void> _importPairingInvite() async {
    final values = await showDialog<(String, String)?>(
      context: context,
      builder: (dialogContext) {
        final inviteController = TextEditingController();
        final codeController = TextEditingController();
        return AlertDialog(
          title: const Text('Add paired device'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: inviteController,
                decoration: const InputDecoration(labelText: 'Invitation URI'),
                maxLines: 3,
              ),
              TextField(
                controller: codeController,
                decoration: const InputDecoration(labelText: '6-digit code'),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(
                dialogContext,
              ).pop((inviteController.text.trim(), codeController.text.trim())),
              child: const Text('Confirm'),
            ),
          ],
        );
      },
    );
    if (values == null) return;
    try {
      await _acceptInvite(values.$1, values.$2);
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Pairing failed: $error')));
    }
  }

  Future<void> _scanPairingInvite() async {
    final scan = widget.scanPairingQr;
    if (scan == null) return;
    final inviteUri = await scan(context);
    if (!mounted || inviteUri == null) return;
    final code = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        final controller = TextEditingController();
        return AlertDialog(
          title: const Text('Confirm pairing code'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(labelText: '6-digit code'),
            keyboardType: TextInputType.number,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(controller.text),
              child: const Text('Confirm'),
            ),
          ],
        );
      },
    );
    if (code == null) return;
    try {
      await _acceptInvite(inviteUri, code.trim());
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Pairing failed: $error')));
    }
  }

  Future<void> _acceptInvite(String value, String code) async {
    final invite = PairingInvite.fromUri(value);
    final session = PairingSession(invite)
      ..accept(
        remoteDeviceId: invite.issuerDeviceId,
        remotePublicKey: invite.issuerPublicKey,
      );
    session.confirm(code);
    final pairingHandshake = widget.pairingHandshake;
    if (pairingHandshake != null) {
      final acceptance = await pairingHandshake.sendAcceptance(
        invite: invite,
        deviceId: widget.deviceId ?? 'local-device',
        publicKey: widget.publicKey ?? 'local-public-key',
        displayName: 'Pigeon ${widget.deviceId ?? 'device'}',
        platform: 'paired',
        relayUrl: pairingHandshake.server.toString(),
        relayTopic: widget.relayTopic ?? '',
        lanHost: widget.lanHost,
        lanPort: widget.lanPort,
        certificateSha256: widget.lanCertificateSha256,
      );
      await _savePairedDevice(
        invite,
        authorized: false,
        relayTopic: invite.issuerRelayTopic,
      );
      _waitForPairingConfirmation(invite, acceptance);
      return;
    }
    await _savePairedDevice(
      invite,
      authorized: true,
      relayTopic: invite.issuerRelayTopic,
    );
  }

  Future<bool> _completeIssuerPairing(
    PairingSession session,
    PairingAcceptance acceptance,
  ) async {
    if (!acceptance.verify(session.invite) || session.isTerminal) return false;
    try {
      if (!await _confirmPairingAcceptance(acceptance)) return false;
      if (!mounted || session.isTerminal) return false;
      session.accept(
        remoteDeviceId: acceptance.deviceId,
        remotePublicKey: acceptance.publicKey,
      );
      session.confirm(acceptance.shortCode);
      final repository = widget.repository;
      if (repository == null) return false;
      await repository.saveDevice(
        Device(
          id: acceptance.deviceId,
          displayName: acceptance.displayName,
          platform: acceptance.platform,
          publicKey: acceptance.publicKey,
          endpoint: {
            'relayUrl': acceptance.relayUrl,
            'relayTopic': acceptance.relayTopic,
            if (acceptance.lanHost != null) 'lanHost': acceptance.lanHost,
            if (acceptance.lanPort != null) 'lanPort': acceptance.lanPort,
            if (acceptance.certificateSha256 != null)
              'certificateSha256': acceptance.certificateSha256,
          },
          pairedAt: DateTime.now().toUtc(),
        ),
      );
      final handshake = widget.pairingHandshake;
      if (handshake != null) {
        await handshake.sendConfirmation(
          acceptance: acceptance,
          issuerDeviceId: widget.deviceId ?? 'local-device',
        );
      }
      await widget.router?.sendCatalogSnapshot(acceptance.deviceId);
      await _loadRepositoryData(repository);
      final server = _lanPairingServer;
      if (server != null) {
        unawaited(
          Future<void>.delayed(const Duration(milliseconds: 250), () async {
            if (identical(_lanPairingServer, server)) {
              await _closeLanPairing();
            }
          }),
        );
      }
      return true;
    } on Object catch (error) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Pairing confirmation failed: $error')),
      );
      return false;
    }
  }

  Future<bool> _confirmPairingAcceptance(PairingAcceptance acceptance) async {
    if (!mounted) return false;
    final fingerprint = _publicKeyFingerprint(acceptance.publicKey);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Confirm new paired device'),
        content: SingleChildScrollView(
          child: ListBody(
            children: [
              Text('Name: ${acceptance.displayName}'),
              Text('Device ID: ${acceptance.deviceId}'),
              Text('Platform: ${acceptance.platform}'),
              const SizedBox(height: 12),
              const Text('Public-key fingerprint:'),
              SelectableText(fingerprint),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Reject'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Pair device'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _waitForPairingConfirmation(
    PairingInvite invite,
    PairingAcceptance acceptance,
  ) async {
    final handshake = widget.pairingHandshake;
    if (handshake == null || widget.relayTopic == null) return;
    try {
      final confirmation = await handshake
          .listenForConfirmation(invite, localRelayTopic: widget.relayTopic!)
          .firstWhere(
            (value) =>
                value.acceptorDeviceId == (widget.deviceId ?? 'local-device') &&
                value.issuerDeviceId == invite.issuerDeviceId &&
                value.shortCode == invite.shortCode &&
                value.proof ==
                    pairingProof(
                      nonce: invite.nonce,
                      shortCode: invite.shortCode,
                      deviceId: invite.issuerDeviceId,
                      publicKey: acceptance.publicKey,
                    ),
          )
          .timeout(const Duration(minutes: 10));
      if (confirmation.nonce != invite.nonce) return;
      await _savePairedDevice(
        invite,
        authorized: true,
        relayTopic: invite.issuerRelayTopic,
      );
    } on Object {
      // The pending device remains unauthorized until the user retries the
      // invitation; no endpoint becomes selectable on a timeout.
    }
  }

  Future<void> _savePairedDevice(
    PairingInvite invite, {
    required bool authorized,
    required String relayTopic,
  }) async {
    final repository = widget.repository;
    if (repository == null) return;
    await repository.saveDevice(
      Device(
        id: invite.issuerDeviceId,
        displayName: invite.issuerDeviceId,
        platform: 'paired',
        publicKey: invite.issuerPublicKey,
        endpoint: {
          'relayUrl': invite.relayUrl,
          'relayTopic': relayTopic,
          if (invite.issuerLanHost != null) 'lanHost': invite.issuerLanHost,
          if (invite.issuerLanPort != null) 'lanPort': invite.issuerLanPort,
          if (invite.issuerPairingLanPort != null)
            'pairingLanPort': invite.issuerPairingLanPort,
          if (invite.issuerCertificateSha256 != null)
            'certificateSha256': invite.issuerCertificateSha256,
          'temporaryPairingTopic': invite.temporaryTopic,
        },
        pairedAt: DateTime.now().toUtc(),
        authorized: authorized,
      ),
    );
    final router = widget.router;
    if (router != null && authorized) {
      await router.sendCatalogSnapshot(invite.issuerDeviceId);
    }
    await _loadRepositoryData(repository);
  }

  Future<void> _showInviteText(String invite) => showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Pair device'),
      content: SelectableText(invite),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Close'),
        ),
      ],
    ),
  );

  Widget _settingsPage(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final currentLocale = Localizations.localeOf(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ListTile(
          leading: Icon(Icons.lock_outline),
          title: Text(l10n.secrets),
          subtitle: Text(l10n.secretsDescription),
        ),
        ListTile(
          leading: Icon(Icons.sync_outlined),
          title: Text(l10n.transport),
          subtitle: Text(l10n.transportDescription),
        ),
        ListTile(
          leading: const Icon(Icons.cloud_outlined),
          title: Text(l10n.relayServer),
          subtitle: Text(
            '${widget.relayServer ?? Uri.parse('https://ntfy.sh')}'
            '${widget.relayAuthorizationConfigured ? ' · ${l10n.authorizationConfigured}' : ''}',
          ),
          onTap: _editRelaySettings,
        ),
        ListTile(
          leading: Icon(Icons.delete_sweep_outlined),
          title: Text(l10n.attachmentRetention),
          subtitle: Text(l10n.attachmentRetentionDescription),
        ),
        ListTile(
          leading: const Icon(Icons.cleaning_services_outlined),
          title: Text(l10n.purgeExpiredAttachments),
          subtitle: Text(l10n.currentRetention(_retention.name)),
          onTap: _chooseRetention,
        ),
        ListTile(
          leading: const Icon(Icons.content_copy_outlined),
          title: Text(l10n.packetDeduplicationRetention),
          subtitle: Text('${_packetDedupRetention.inDays} day(s)'),
          onTap: _choosePacketDedupRetention,
        ),
        ListTile(
          leading: const Icon(Icons.file_upload_outlined),
          title: Text(l10n.exportConfiguration),
          subtitle: Text(l10n.exportConfigurationDescription),
          onTap: _exportConfiguration,
        ),
        ListTile(
          leading: const Icon(Icons.file_download_outlined),
          title: Text(l10n.importConfiguration),
          subtitle: Text(l10n.importConfigurationDescription),
          onTap: _importConfiguration,
        ),
        ListTile(
          leading: const Icon(Icons.language_outlined),
          title: Text(l10n.language),
          subtitle: Text(l10n.languageDescription),
          trailing: DropdownButton<Locale>(
            value: AppLocalizations.supportedLocales.firstWhere(
              (locale) => locale.languageCode == currentLocale.languageCode,
              orElse: () => AppLocalizations.supportedLocales.first,
            ),
            items: [
              DropdownMenuItem(
                value: const Locale('en'),
                child: Text(l10n.languageEnglish),
              ),
              DropdownMenuItem(
                value: const Locale('zh'),
                child: Text(l10n.languageChinese),
              ),
            ],
            onChanged: (locale) {
              if (locale != null) {
                unawaited(widget.onLocaleChanged?.call(locale));
              }
            },
          ),
        ),
      ],
    );
  }

  Future<void> _deleteMessage(PigeonMessage message) async {
    final repository = widget.repository;
    if (repository == null) return;
    final manager = widget.attachmentRetention;
    if (manager != null) {
      await manager.deleteMessage(message.id);
    } else {
      await repository.deleteMessage(message.id);
    }
    if (!mounted) return;
    setState(() => _messages.removeWhere((item) => item.id == message.id));
  }

  Future<void> _cancelMessageRequests(PigeonMessage message) async {
    final repository = widget.repository;
    final router = widget.router;
    if (repository == null || router == null) return;
    for (final request in await repository.listRequests()) {
      if (request.message.id == message.id &&
          await repository.getReceipt(request.requestId) == null) {
        await router.cancelRequest(request.requestId);
      }
    }
    await _loadRepositoryData(repository);
  }

  Future<void> _editRelaySettings() async {
    final callback = widget.onRelaySettingsChanged;
    if (callback == null) return;
    final values = await showDialog<(String, String?)>(
      context: context,
      builder: (dialogContext) {
        final server = TextEditingController(
          text: (widget.relayServer ?? Uri.parse('https://ntfy.sh')).toString(),
        );
        final authorization = TextEditingController();
        return AlertDialog(
          title: const Text('Relay settings'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: server,
                decoration: const InputDecoration(labelText: 'ntfy server URL'),
                keyboardType: TextInputType.url,
              ),
              TextField(
                controller: authorization,
                decoration: const InputDecoration(
                  labelText: 'Authorization (empty to clear)',
                ),
                obscureText: true,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop((
                server.text.trim(),
                authorization.text.trim().isEmpty
                    ? null
                    : authorization.text.trim(),
              )),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
    if (values == null) return;
    final server = Uri.tryParse(values.$1);
    if (server == null || !server.hasScheme || server.host.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Relay URL is invalid.')));
      return;
    }
    try {
      await callback(server, values.$2);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Relay settings saved; restart Pigeon to reconnect.'),
        ),
      );
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Save failed: $error')));
    }
  }

  Future<void> _chooseRetention() async {
    final selected = await showDialog<AttachmentRetention>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Attachment retention'),
        children: [
          for (final value in AttachmentRetention.values)
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialogContext).pop(value),
              child: Text(value.name),
            ),
        ],
      ),
    );
    if (selected == null) return;
    setState(() => _retention = selected);
    await widget.onAttachmentRetentionChanged?.call(selected);
    final manager = widget.attachmentRetention;
    if (manager == null || selected == AttachmentRetention.forever) return;
    final deleted = await manager.purgeExpired(retention: selected);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Removed $deleted expired message(s).')),
    );
    final repository = widget.repository;
    if (repository != null) await _loadRepositoryData(repository);
  }

  Future<void> _choosePacketDedupRetention() async {
    final selected = await showDialog<Duration>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Packet deduplication retention'),
        children: [
          for (final days in const [1, 7, 30, 90])
            SimpleDialogOption(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(Duration(days: days)),
              child: Text('$days day(s)'),
            ),
        ],
      ),
    );
    if (selected == null) return;
    setState(() => _packetDedupRetention = selected);
    await widget.onPacketDedupRetentionChanged?.call(selected);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Deduplication retention saved; restart to apply.'),
      ),
    );
  }

  Future<void> _exportConfiguration() async {
    final repository = widget.repository;
    if (repository == null) return;
    final json = const JsonEncoder.withIndent('  ')
        .convert(await PigeonConfigurationTransfer(repository).export());
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Export configuration'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(child: SelectableText(json)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _importConfiguration() async {
    final repository = widget.repository;
    if (repository == null) return;
    final controller = TextEditingController();
    final json = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Import configuration'),
        content: SizedBox(
          width: 560,
          child: TextField(
            controller: controller,
            maxLines: 12,
            decoration: const InputDecoration(
              hintText: '{"version":1,"works":[],"devices":[]}',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('Import'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (json == null) return;
    try {
      await PigeonConfigurationTransfer(repository).import(jsonDecode(json));
      await _loadRepositoryData(repository);
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Import failed: $error')));
    }
  }
}

class _PigeonPageData {
  const _PigeonPageData({
    required this.title,
    required this.icon,
    required this.message,
  });

  final String title;
  final IconData icon;
  final String message;
}

class _AndroidSecretResolver implements SecretResolver {
  const _AndroidSecretResolver(this.delegate);

  final DesktopSecretResolver? delegate;

  @override
  Future<String?> resolve(String name) =>
      delegate?.resolve(name) ?? Future<String?>.value();
}
