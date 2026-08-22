import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../actent_platform/android_share_bridge.dart';
import '../pairing/pairing.dart';
import '../pairing/lan_pairing.dart';
import '../pairing/pairing_relay.dart';
import '../work/desktop/desktop_script_runner.dart';
import '../work/android/android_work_runner.dart';
import '../work/work_bindings.dart';
import '../work/work_runner.dart';
import '../work/web_js_work.dart';
import 'actent_router.dart';
import 'actent_transport.dart';
import 'actent_models.dart';
import 'configuration_transfer.dart';
import 'attachment_retention.dart';
import 'actent_store.dart';
import '../../l10n/app_localizations.dart';
import '../../app/pairing_configuration.dart';

class ActentHomePage extends StatefulWidget {
  const ActentHomePage({
    super.key,
    this.repository,
    this.shareBridge,
    this.deviceId,
    this.deviceDisplayName,
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
    this.pickWorkInputFile,
    this.importWorkInputFiles,
    this.initialFilePaths = const [],
    this.externalFilePaths,
    this.showPairingQr,
    this.scanPairingQr,
    this.onLocaleChanged,
  });

  final ActentRepository? repository;
  final AndroidShareBridge? shareBridge;
  final String? deviceId;
  final String? deviceDisplayName;
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
  final bool canEditWorks;
  final DesktopSecretResolver? desktopSecrets;
  final ActentRouter? router;
  final WorkQueueCoordinator? queue;
  final Future<ActentMessage?> Function()? pickWorkInputFile;
  final Future<ActentMessage?> Function(List<String> paths)?
  importWorkInputFiles;
  final List<String> initialFilePaths;
  final Stream<List<String>>? externalFilePaths;
  final Future<void> Function(BuildContext context, String invite)?
  showPairingQr;
  final Future<String?> Function(BuildContext context)? scanPairingQr;
  final Future<void> Function(Locale locale)? onLocaleChanged;

  @override
  State<ActentHomePage> createState() => _ActentHomePageState();
}

class _ActentHomePageState extends State<ActentHomePage> {
  var _selectedIndex = 0;
  final List<ActentMessage> _messages = [];
  final List<Work> _works = [];
  final List<Device> _devices = [];
  final Map<String, WorkReceiptStatus> _messageStatuses = {};
  final PairingCoordinator _pairing = PairingCoordinator();
  StreamSubscription<ActentMessage>? _shareSubscription;
  StreamSubscription<PairingAcceptance>? _pairingAcceptanceSubscription;
  StreamSubscription<List<String>>? _externalFileSubscription;
  LanPairingServer? _lanPairingServer;
  MdnsPairingAdvertiser? _lanPairingAdvertiser;
  WorkQueueCoordinator? _queue;
  AttachmentRetention _retention = AttachmentRetention.sevenDays;
  late Duration _packetDedupRetention;

  bool get _isAndroid => defaultTargetPlatform == TargetPlatform.android;
  bool get _isIos => defaultTargetPlatform == TargetPlatform.iOS;
  bool get _supportsNetworkWork => _isAndroid || _isIos;

  List<_ActentPageData> _pages(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return [
      _ActentPageData(
        title: l10n.activity,
        icon: Icons.history_outlined,
        message: l10n.activityDescription,
      ),
      _ActentPageData(
        title: l10n.works,
        icon: Icons.work_outline,
        message: l10n.worksDescription,
      ),
      _ActentPageData(
        title: l10n.devices,
        icon: Icons.devices_outlined,
        message: l10n.devicesDescription,
      ),
      _ActentPageData(
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
    _externalFileSubscription = widget.externalFilePaths?.listen(
      _importExternalFiles,
    );
  }

  Future<void> _loadRepositoryData(ActentRepository repository) async {
    final l10n = AppLocalizations.of(context)!;
    final messages = await repository.listMessages();
    var works = await repository.listWorks();
    final localDeviceId = widget.deviceId ?? 'local-device';
    final localNullId = 'null-$localDeviceId';
    var localCatalogChanged = false;
    final existingNull = works
        .where((work) => work.id == localNullId)
        .firstOrNull;
    if (existingNull == null) {
      final nullWork = Work.nullWork(
        id: localNullId,
        ownerDeviceId: localDeviceId,
        name: l10n.nullWork,
      );
      await repository.saveWork(nullWork);
      works = [...works, nullWork];
      localCatalogChanged = true;
    } else if (existingNull.name == 'Null' &&
        existingNull.name != l10n.nullWork) {
      final renamedNull = Work(
        id: existingNull.id,
        revision: existingNull.revision + 1,
        name: l10n.nullWork,
        ownerDeviceId: existingNull.ownerDeviceId,
        allowedSourceDeviceIds: existingNull.allowedSourceDeviceIds,
        acceptedContentTypes: existingNull.acceptedContentTypes,
        timeout: existingNull.timeout,
        queueLimit: existingNull.queueLimit,
        enabled: existingNull.enabled,
        platformBindings: existingNull.platformBindings,
        catalogVisibility: existingNull.catalogVisibility,
      );
      await repository.saveWork(renamedNull);
      works = [
        for (final work in works) work.id == localNullId ? renamedNull : work,
      ];
      localCatalogChanged = true;
    }
    if (widget.shareBridge != null &&
        !works.any((work) => work.id == 'android-share')) {
      final shareWork = Work(
        id: 'android-share',
        revision: 1,
        name: 'Android Share',
        ownerDeviceId: widget.deviceId ?? 'local-device',
        acceptedContentTypes: ActentContentType.values.toSet(),
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
      localCatalogChanged = true;
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
    if (localCatalogChanged) await _publishCatalogChanges();
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
            case 'web-js' when kIsWeb:
              queue.register(
                work.id,
                WebJsWorkRunner(WebJsBinding.fromWork(work).toConfig()),
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
            case 'android-http' when _supportsNetworkWork:
              queue.register(
                work.id,
                AndroidHttpRunner(
                  spec: AndroidHttpBinding.fromWork(work).spec,
                  client: IoAndroidHttpClient(),
                  secrets: _AndroidSecretResolver(widget.desktopSecrets),
                ),
              );
            case 'ios-url' when _isIos:
              queue.register(work.id, IosUrlBinding.fromWork(work).toRunner());
          }
        } on WorkBindingException {
          // Invalid work definitions remain visible for correction in Works.
        }
      }
      await queue.restorePending(works);
    }
    if (widget.initialFilePaths.isNotEmpty && mounted) {
      await _importExternalFiles(widget.initialFilePaths);
    }
  }

  Future<void> _importExternalFiles(List<String> paths) async {
    final importer = widget.importWorkInputFiles;
    if (importer == null) return;
    try {
      final message = await importer(paths);
      if (message != null) await _onSharedMessage(message);
    } on Object catch (error) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.fileSelectionFailed(error.toString()))),
      );
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
    _externalFileSubscription?.cancel();
    unawaited(_closeLanPairing());
    super.dispose();
  }

  Future<void> _onSharedMessage(ActentMessage message) async {
    final repository = widget.repository;
    if (repository != null) {
      await repository.saveMessage(message);
    }
    if (!mounted) return;
    setState(() => _messages.insert(0, message));
    _showWorkPicker(message);
  }

  Future<void> _showWorkPicker(ActentMessage message) async {
    final l10n = AppLocalizations.of(context)!;
    final work = await showModalBottomSheet<Work>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: Text(l10n.chooseWork),
              subtitle: Text(l10n.chooseWorkDescription),
            ),
            for (final availableWork in _works.where(
              (availableWork) =>
                  availableWork.accepts(message) &&
                  _isSelectableWork(availableWork),
            ))
              ListTile(
                leading: const Icon(Icons.play_arrow_outlined),
                title: Text(availableWork.name),
                subtitle: Text(
                  '${availableWork.ownerDeviceId == (widget.deviceId ?? 'local-device') ? l10n.thisDevice : l10n.remoteDevice} · revision ${availableWork.revision}',
                ),
                onTap: () => Navigator.of(context).pop(availableWork),
              ),
            ListTile(
              leading: const Icon(Icons.archive_outlined),
              title: Text(l10n.nullWork),
              onTap: () => Navigator.of(context).pop(
                Work.nullWork(
                  id: 'local-null',
                  ownerDeviceId: widget.deviceId ?? 'local-device',
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.close),
              title: Text(l10n.discard),
              onTap: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
    if (work == null || !mounted) return;
    await _routeMessageToWork(message, work);
  }

  Future<void> _showMessagePicker(Work work) async {
    if (!work.enabled || !_isSelectableWork(work)) return;
    final accepted = work.acceptedContentTypes;
    final fileTypes = {
      ActentContentType.file,
      ActentContentType.image,
      ActentContentType.json,
    };
    final inputType = accepted.length == 1
        ? accepted.single
        : accepted.difference(fileTypes).isEmpty
        ? ActentContentType.file
        : await _showInputTypePicker(work);
    if (inputType == null || !mounted) return;
    if (inputType == ActentContentType.file ||
        inputType == ActentContentType.image) {
      await _pickFileForWork(work);
      return;
    }
    if (inputType == ActentContentType.json &&
        widget.pickWorkInputFile != null) {
      await _pickFileForWork(work);
      return;
    }
    final message = await _showManualInputDialog(inputType);
    if (message != null && mounted) {
      await _routeMessageToWork(message, work);
    }
  }

  Future<ActentContentType?> _showInputTypePicker(Work work) async {
    final l10n = AppLocalizations.of(context)!;
    final types = work.acceptedContentTypes.toList()
      ..sort((left, right) => left.index.compareTo(right.index));
    return showModalBottomSheet<ActentContentType>(
      context: context,
      builder: (dialogContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: Text(l10n.chooseInputType),
              subtitle: Text(l10n.chooseInputTypeDescription),
            ),
            for (final type in types)
              ListTile(
                leading: Icon(_contentTypeIcon(type)),
                title: Text(_contentTypeLabel(type, l10n)),
                onTap: () => Navigator.of(dialogContext).pop(type),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickFileForWork(Work work) async {
    final l10n = AppLocalizations.of(context)!;
    final pickWorkInputFile = widget.pickWorkInputFile;
    if (pickWorkInputFile != null) {
      try {
        final message = await pickWorkInputFile();
        if (message != null && mounted && work.accepts(message)) {
          await _routeMessageToWork(message, work);
        } else if (message != null && mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(l10n.inputTypeNotAccepted)));
        }
      } on Object catch (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.fileSelectionFailed(error.toString()))),
        );
      }
      return;
    }
    final compatibleMessages = _messages
        .where(work.accepts)
        .toList(growable: false);
    if (compatibleMessages.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.noMessagesAvailable)));
      return;
    }
    final message = await showModalBottomSheet<ActentMessage>(
      context: context,
      builder: (dialogContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: Text(l10n.chooseWorkInput),
              subtitle: Text(l10n.chooseWorkInputDescription),
            ),
            for (final candidate in compatibleMessages)
              ListTile(
                leading: const Icon(Icons.inbox_outlined),
                title: Text(candidate.content.type.value),
                subtitle: Text(candidate.id),
                onTap: () => Navigator.of(dialogContext).pop(candidate),
              ),
          ],
        ),
      ),
    );
    if (message == null || !mounted) return;
    await _routeMessageToWork(message, work);
  }

  Future<ActentMessage?> _showManualInputDialog(ActentContentType type) async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_contentTypeLabel(type, l10n)),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: type == ActentContentType.json ? 5 : 1,
          maxLines: type == ActentContentType.json ? 12 : 5,
          keyboardType: TextInputType.multiline,
          decoration: InputDecoration(
            hintText: type == ActentContentType.url
                ? l10n.urlInputHint
                : l10n.inputValueHint,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: Text(l10n.continueLabel),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || value.trim().isEmpty) return null;
    final now = DateTime.now().toUtc();
    final id = 'manual-${now.microsecondsSinceEpoch}';
    final key = switch (type) {
      ActentContentType.text => 'text',
      ActentContentType.url => 'url',
      ActentContentType.json => 'json',
      _ => 'text',
    };
    return ActentMessage(
      id: id,
      traceId: id,
      createdAt: now,
      source: ActentSource(
        kind: 'manual-input',
        deviceId: widget.deviceId ?? 'local-device',
        appName: 'Actent',
      ),
      content: ActentContent(type: type, data: {key: value.trim()}),
    );
  }

  String _contentTypeLabel(ActentContentType type, AppLocalizations l10n) =>
      switch (type) {
        ActentContentType.text => l10n.inputText,
        ActentContentType.url => l10n.inputUrl,
        ActentContentType.image => l10n.inputImage,
        ActentContentType.file => l10n.inputFile,
        ActentContentType.json => l10n.inputJson,
      };

  IconData _contentTypeIcon(ActentContentType type) => switch (type) {
    ActentContentType.text => Icons.text_fields,
    ActentContentType.url => Icons.link,
    ActentContentType.image => Icons.image_outlined,
    ActentContentType.file => Icons.insert_drive_file_outlined,
    ActentContentType.json => Icons.data_object,
  };

  Future<void> _routeMessageToWork(ActentMessage message, Work work) async {
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
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.workRequestFailed(error.toString()))),
      );
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
                              itemBuilder: (context) => [
                                PopupMenuItem(
                                  value: 'retry',
                                  child: Text(
                                    AppLocalizations.of(context)!.runAgain,
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'cancel',
                                  child: Text(
                                    AppLocalizations.of(context)!
                                        .cancelPendingRequests,
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Text(
                                    AppLocalizations.of(context)!.deleteMessage,
                                  ),
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
              label: Text(AppLocalizations.of(context)!.pairDevice),
            )
          : _selectedIndex == 1
          ? FloatingActionButton.extended(
              onPressed: _showAddWork,
              icon: const Icon(Icons.add),
              label: Text(AppLocalizations.of(context)!.addWork),
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

  Widget _emptyPage(_ActentPageData page) => Center(
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

  Widget _worksPage(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return _works.isEmpty
        ? _emptyPage(_pages(context)[1])
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final group in _worksByOwner(l10n)) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 4),
                  child: Text(
                    group.$1,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                for (final work in group.$2)
                  Card(
                    child: ListTile(
                      leading: IconButton(
                        tooltip: l10n.runWork,
                        onPressed: work.enabled && _isSelectableWork(work)
                            ? () => _showMessagePicker(work)
                            : null,
                        icon: const Icon(Icons.play_arrow_outlined),
                      ),
                      title: Text(work.name),
                      subtitle: Text(
                        '${_workOwnerLabel(work, l10n)} · '
                        '${work.id} · revision ${work.revision} · '
                        '${work.enabled ? AppLocalizations.of(context)!.enable : AppLocalizations.of(context)!.disable}',
                      ),
                      trailing: _isLocalWork(work)
                          ? PopupMenuButton<String>(
                              onSelected: (value) async {
                                switch (value) {
                                  case 'edit':
                                    await _editWork(work);
                                  case 'toggle':
                                    await _toggleWork(work);
                                  case 'delete':
                                    await _deleteWork(work);
                                }
                              },
                              itemBuilder: (context) => [
                                if (_canEditWork(work))
                                  PopupMenuItem(
                                    value: 'edit',
                                    child: Text(l10n.edit),
                                  ),
                                PopupMenuItem(
                                  value: 'toggle',
                                  child: Text(
                                    work.enabled ? l10n.disable : l10n.enable,
                                  ),
                                ),
                                if (work.id != 'android-share')
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: Text(l10n.delete),
                                  ),
                              ],
                            )
                          : null,
                    ),
                  ),
              ],
            ],
          );
  }

  List<(String, List<Work>)> _worksByOwner(AppLocalizations l10n) {
    final groups = <String, List<Work>>{};
    for (final work in _works) {
      groups.putIfAbsent(_workOwnerLabel(work, l10n), () => []).add(work);
    }
    final result = groups.entries.map((entry) {
      entry.value.sort((a, b) => a.name.compareTo(b.name));
      return (entry.key, entry.value);
    }).toList();
    result.sort((a, b) => a.$1.compareTo(b.$1));
    return result;
  }

  bool _isLocalWork(Work work) =>
      work.ownerDeviceId == (widget.deviceId ?? 'local-device');

  bool _canEditWork(Work work) => switch (work.platformBindings['kind']) {
    'null' => true,
    'web-js' => kIsWeb,
    'desktop-script' => widget.canEditWorks,
    _ => false,
  };

  String _workOwnerLabel(Work work, AppLocalizations l10n) {
    if (_isLocalWork(work)) return l10n.thisDevice;
    for (final device in _devices) {
      if (device.id == work.ownerDeviceId) return device.displayName;
    }
    return work.ownerDeviceId;
  }

  String _attachmentRetentionLabel(
    AttachmentRetention value,
    AppLocalizations l10n,
  ) => switch (value) {
    AttachmentRetention.oneDay => l10n.retentionOneDay,
    AttachmentRetention.sevenDays => l10n.retentionSevenDays,
    AttachmentRetention.oneMonth => l10n.retentionOneMonth,
    AttachmentRetention.forever => l10n.retentionForever,
  };

  Future<void> _showAddWork() async {
    final l10n = AppLocalizations.of(context)!;
    final type = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.chooseWorkType),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.archive_outlined),
                title: Text(l10n.nullWorkType),
                onTap: () => Navigator.pop(dialogContext, 'null'),
              ),
              if (widget.canEditWorks)
                ListTile(
                  leading: const Icon(Icons.terminal),
                  title: Text(l10n.scriptWorkType),
                  onTap: () => Navigator.pop(dialogContext, 'script'),
                ),
              if (kIsWeb)
                ListTile(
                  leading: const Icon(Icons.javascript),
                  title: Text(l10n.javaScriptWorkType),
                  onTap: () => Navigator.pop(dialogContext, 'javascript'),
                ),
              if (_isAndroid && widget.shareBridge != null)
                ListTile(
                  leading: const Icon(Icons.apps_outlined),
                  title: Text(l10n.applicationWorkType),
                  onTap: () => Navigator.pop(dialogContext, 'application'),
                ),
              if (_isIos)
                ListTile(
                  leading: const Icon(Icons.apps_outlined),
                  title: Text(l10n.applicationWorkType),
                  onTap: () => Navigator.pop(dialogContext, 'iosApplication'),
                ),
              if (_supportsNetworkWork)
                ListTile(
                  leading: const Icon(Icons.http),
                  title: Text(l10n.networkWorkType),
                  onTap: () => Navigator.pop(dialogContext, 'network'),
                ),
            ],
          ),
        ),
      ),
    );
    switch (type) {
      case 'null':
        await _addNullWork();
      case 'script':
        await _addDesktopWork();
      case 'javascript':
        await _addWebJsWork();
      case 'application':
        await _addAndroidApplicationWork();
      case 'iosApplication':
        await _addIosApplicationWork();
      case 'network':
        await _addAndroidNetworkWork();
    }
  }

  Future<void> _addDesktopWork() => _editDesktopWork();

  Future<void> _addWebJsWork() => _editWebJsWork();

  Future<void> _addNullWork() async {
    final repository = widget.repository;
    if (repository == null) return;
    final l10n = AppLocalizations.of(context)!;
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        final controller = TextEditingController();
        return AlertDialog(
          title: Text(l10n.addWork),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(labelText: l10n.name),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(controller.text.trim()),
              child: Text(l10n.save),
            ),
          ],
        );
      },
    );
    if (name == null || name.isEmpty) return;
    await repository.saveWork(
      Work(
        id: 'null-${DateTime.now().microsecondsSinceEpoch}',
        revision: 1,
        name: name,
        ownerDeviceId: widget.deviceId ?? 'local-device',
        acceptedContentTypes: ActentContentType.values.toSet(),
        platformBindings: const {'kind': 'null'},
      ),
    );
    await _publishCatalogChanges();
    await _loadRepositoryData(repository);
  }

  Future<void> _addAndroidApplicationWork() async {
    final l10n = AppLocalizations.of(context)!;
    final values = await showDialog<(String, String)?>(
      context: context,
      builder: (dialogContext) {
        final name = TextEditingController();
        final packageName = TextEditingController();
        return AlertDialog(
          title: Text(l10n.addApplicationWork),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: InputDecoration(labelText: l10n.name),
              ),
              TextField(
                controller: packageName,
                decoration: InputDecoration(labelText: l10n.androidPackageName),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, (
                name.text.trim(),
                packageName.text.trim(),
              )),
              child: Text(l10n.save),
            ),
          ],
        );
      },
    );
    if (values == null || values.$1.isEmpty) return;
    await _saveCreatedAndroidWork(
      name: values.$1,
      idPrefix: 'android-intent',
      bindings: {
        'kind': 'android-intent',
        'action': 'android.intent.action.SEND',
        'categories': const <String>[],
        'extras': const <String, Object?>{},
        'chooser': true,
        'attachmentPlacement': 'streams',
        if (values.$2.isNotEmpty) 'packageName': values.$2,
      },
    );
  }

  Future<void> _addAndroidNetworkWork() async {
    final l10n = AppLocalizations.of(context)!;
    final values = await showDialog<(String, String)?>(
      context: context,
      builder: (dialogContext) {
        final name = TextEditingController();
        final url = TextEditingController(text: 'https://');
        return AlertDialog(
          title: Text(l10n.addNetworkWork),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: InputDecoration(labelText: l10n.name),
              ),
              TextField(
                controller: url,
                decoration: InputDecoration(labelText: l10n.networkUrl),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, (
                name.text.trim(),
                url.text.trim(),
              )),
              child: Text(l10n.save),
            ),
          ],
        );
      },
    );
    if (values == null || values.$1.isEmpty || values.$2.isEmpty) return;
    await _saveCreatedAndroidWork(
      name: values.$1,
      idPrefix: 'android-http',
      bindings: {
        'kind': 'android-http',
        'urlTemplate': values.$2,
        'method': 'POST',
        'headers': const <String, String>{},
        'bodyTemplate': '{{content.text}}',
      },
    );
  }

  Future<void> _addIosApplicationWork() async {
    final l10n = AppLocalizations.of(context)!;
    final values = await showDialog<(String, String)?>(
      context: context,
      builder: (dialogContext) {
        final name = TextEditingController();
        final url = TextEditingController();
        return AlertDialog(
          title: Text(l10n.addApplicationWork),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: InputDecoration(labelText: l10n.name),
              ),
              TextField(
                controller: url,
                decoration: InputDecoration(labelText: l10n.applicationUrl),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, (
                name.text.trim(),
                url.text.trim(),
              )),
              child: Text(l10n.save),
            ),
          ],
        );
      },
    );
    if (values == null || values.$1.isEmpty || values.$2.isEmpty) return;
    await _saveCreatedAndroidWork(
      name: values.$1,
      idPrefix: 'ios-url',
      bindings: {'kind': 'ios-url', 'urlTemplate': values.$2},
    );
  }

  Future<void> _saveCreatedAndroidWork({
    required String name,
    required String idPrefix,
    required Map<String, Object?> bindings,
  }) async {
    final repository = widget.repository;
    if (repository == null) return;
    await repository.saveWork(
      Work(
        id: '$idPrefix-${DateTime.now().microsecondsSinceEpoch}',
        revision: 1,
        name: name,
        ownerDeviceId: widget.deviceId ?? 'local-device',
        acceptedContentTypes: ActentContentType.values.toSet(),
        platformBindings: bindings,
      ),
    );
    await _publishCatalogChanges();
    await _loadRepositoryData(repository);
  }

  Future<void> _editWork(Work work) => switch (work.platformBindings['kind']) {
    'null' => _editNullWork(work),
    'web-js' when kIsWeb => _editWebJsWork(work),
    'desktop-script' when widget.canEditWorks => _editDesktopWork(work),
    _ => Future<void>.value(),
  };

  Future<void> _editNullWork(Work existing) async {
    final l10n = AppLocalizations.of(context)!;
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        final controller = TextEditingController(text: existing.name);
        return AlertDialog(
          title: Text(l10n.edit),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(labelText: l10n.name),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(controller.text.trim()),
              child: Text(l10n.save),
            ),
          ],
        );
      },
    );
    if (name == null || name.isEmpty) return;
    final repository = widget.repository;
    if (repository == null) return;
    await repository.saveWork(
      Work(
        id: existing.id,
        revision: existing.revision + 1,
        name: name,
        ownerDeviceId: existing.ownerDeviceId,
        allowedSourceDeviceIds: existing.allowedSourceDeviceIds,
        acceptedContentTypes: existing.acceptedContentTypes,
        timeout: existing.timeout,
        queueLimit: existing.queueLimit,
        enabled: existing.enabled,
        platformBindings: existing.platformBindings,
        catalogVisibility: existing.catalogVisibility,
      ),
    );
    await _publishCatalogChanges();
    await _loadRepositoryData(repository);
  }

  Future<void> _editWebJsWork([Work? existing]) async {
    final l10n = AppLocalizations.of(context)!;
    final values = await showDialog<(String, String, String)?>(
      context: context,
      builder: (dialogContext) {
        final name = TextEditingController(text: existing?.name ?? '');
        final source = TextEditingController(
          text:
              existing?.platformBindings['source'] as String? ??
              'return input.content;',
        );
        final hosts = TextEditingController(
          text:
              (existing?.platformBindings['allowedHosts'] as List?)
                  ?.whereType<String>()
                  .join('\n') ??
              '',
        );
        return AlertDialog(
          title: Text(
            existing == null ? l10n.addJavaScriptWork : l10n.editJavaScriptWork,
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: InputDecoration(labelText: l10n.name),
                ),
                TextField(
                  controller: source,
                  decoration: InputDecoration(labelText: l10n.javaScriptBody),
                  minLines: 8,
                  maxLines: 14,
                ),
                TextField(
                  controller: hosts,
                  decoration: InputDecoration(
                    labelText: l10n.allowedNetworkHosts,
                  ),
                  maxLines: 3,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext)
                      .pop((name.text.trim(), source.text, hosts.text)),
              child: Text(l10n.save),
            ),
          ],
        );
      },
    );
    if (values == null || values.$1.isEmpty || values.$2.trim().isEmpty) return;
    final allowedHosts = values.$3
        .split(RegExp(r'\r?\n'))
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList();
    final work = Work(
      id: existing?.id ?? 'web-js-${DateTime.now().microsecondsSinceEpoch}',
      revision: (existing?.revision ?? 0) + 1,
      name: values.$1,
      ownerDeviceId: widget.deviceId ?? 'local-device',
      allowedSourceDeviceIds: existing?.allowedSourceDeviceIds ?? const {},
      acceptedContentTypes: ActentContentType.values.toSet(),
      timeout: existing?.timeout ?? const Duration(minutes: 5),
      queueLimit: existing?.queueLimit ?? 10,
      enabled: existing?.enabled ?? true,
      platformBindings: {
        'kind': 'web-js',
        'source': values.$2,
        'allowedHosts': allowedHosts,
      },
      catalogVisibility: existing?.catalogVisibility ?? const {},
    );
    final repository = widget.repository;
    if (repository == null) return;
    await repository.saveWork(work);
    await _publishCatalogChanges();
    await _loadRepositoryData(repository);
  }

  Future<void> _editDesktopWork([Work? existing]) async {
    final l10n = AppLocalizations.of(context)!;
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
            existing == null ? l10n.addScriptWork : l10n.editScriptWork,
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: InputDecoration(labelText: l10n.name),
                ),
                TextField(
                  controller: executable,
                  decoration: InputDecoration(
                    labelText: l10n.absoluteExecutablePath,
                  ),
                ),
                TextField(
                  controller: arguments,
                  decoration: InputDecoration(
                    labelText: l10n.argumentsOnePerLine,
                  ),
                  maxLines: 3,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(
                dialogContext,
              ).pop((name.text.trim(), executable.text.trim(), arguments.text)),
              child: Text(l10n.save),
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
      acceptedContentTypes: ActentContentType.values.toSet(),
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
    await _publishCatalogChanges();
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
    final l10n = AppLocalizations.of(context)!;
    final repository = widget.repository;
    if (repository == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.deleteWorkTitle),
        content: Text(l10n.deleteWorkMessage(work.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.delete),
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
        // Snapshots are idempotent and repair a peer that restarted or missed
        // an earlier delta. Work catalogs are small, so correctness wins here.
        await router.sendCatalogSnapshot(device.id);
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
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.removePairedDeviceTitle),
        content: Text(l10n.removePairedDeviceMessage(device.displayName)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.remove),
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
          label: Text(AppLocalizations.of(context)!.discoverOnLan),
        ),
      OutlinedButton.icon(
        onPressed: _importPairingInvite,
        icon: const Icon(Icons.content_paste_go),
        label: Text(AppLocalizations.of(context)!.pasteInvitation),
      ),
      if (widget.scanPairingQr != null)
        OutlinedButton.icon(
          onPressed: _scanPairingInvite,
          icon: const Icon(Icons.qr_code_scanner),
          label: Text(AppLocalizations.of(context)!.scanQrInvitation),
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
          title: Text(l10n.nearbyDevices),
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
              child: Text(l10n.close),
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
    final client = LanPairingClient(uriScheme: actentPairingUriScheme);
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
      displayName: widget.deviceDisplayName ?? 'Actent device',
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
      final l10n = AppLocalizations.of(context)!;
      final controller = TextEditingController();
      return AlertDialog(
        title: Text(l10n.confirmLanPairingCode),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(labelText: l10n.sixDigitCode),
          keyboardType: TextInputType.number,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: Text(l10n.confirm),
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
      uriScheme: actentPairingUriScheme,
      issuerDeviceId: widget.deviceId ?? 'local-device',
      issuerPublicKey: widget.publicKey ?? 'local-public-key',
      relayUrl: pairingHandshake?.server.toString() ?? 'https://ntfy.sh',
      temporaryTopic: 'actent-pair-${DateTime.now().microsecondsSinceEpoch}',
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
        displayName: widget.deviceDisplayName ?? 'Actent device',
        platform: 'paired',
        fingerprint: _publicKeyFingerprint(
          widget.publicKey ?? 'local-public-key',
        ),
        port: pairingPort!,
        serviceType: actentMdnsServiceName,
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
    final l10n = AppLocalizations.of(context)!;
    final values = await showDialog<(String, String)?>(
      context: context,
      builder: (dialogContext) {
        final inviteController = TextEditingController();
        final codeController = TextEditingController();
        return AlertDialog(
          title: Text(l10n.addPairedDevice),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: inviteController,
                decoration: InputDecoration(labelText: l10n.invitationUri),
                maxLines: 3,
              ),
              TextField(
                controller: codeController,
                decoration: InputDecoration(labelText: l10n.sixDigitCode),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(
                dialogContext,
              ).pop((inviteController.text.trim(), codeController.text.trim())),
              child: Text(l10n.confirm),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.pairingFailedWithError(error.toString()))),
      );
    }
  }

  Future<void> _scanPairingInvite() async {
    final l10n = AppLocalizations.of(context)!;
    final scan = widget.scanPairingQr;
    if (scan == null) return;
    final inviteUri = await scan(context);
    if (!mounted || inviteUri == null) return;
    final code = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        final controller = TextEditingController();
        return AlertDialog(
          title: Text(l10n.confirmPairingCode),
          content: TextField(
            controller: controller,
            decoration: InputDecoration(labelText: l10n.sixDigitCode),
            keyboardType: TextInputType.number,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(controller.text),
              child: Text(l10n.confirm),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.pairingFailedWithError(error.toString()))),
      );
    }
  }

  Future<void> _acceptInvite(String value, String code) async {
    final invite = PairingInvite.fromUri(
      value,
      uriScheme: actentPairingUriScheme,
    );
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
        displayName: widget.deviceDisplayName ?? 'Actent device',
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
    final l10n = AppLocalizations.of(context)!;
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
        SnackBar(content: Text(l10n.pairingFailedWithError(error.toString()))),
      );
      return false;
    }
  }

  Future<bool> _confirmPairingAcceptance(PairingAcceptance acceptance) async {
    final l10n = AppLocalizations.of(context)!;
    if (!mounted) return false;
    final fingerprint = _publicKeyFingerprint(acceptance.publicKey);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.confirmNewPairedDevice),
        content: SingleChildScrollView(
          child: ListBody(
            children: [
              Text(l10n.deviceName(acceptance.displayName)),
              Text(l10n.deviceId(acceptance.deviceId)),
              Text(l10n.platform(acceptance.platform)),
              const SizedBox(height: 12),
              Text(l10n.publicKeyFingerprint),
              SelectableText(fingerprint),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.reject),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.pairDevice),
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

  Future<void> _showInviteText(String invite) {
    final l10n = AppLocalizations.of(context)!;
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.pairDevice),
        content: SelectableText(invite),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.close),
          ),
        ],
      ),
    );
  }

  Widget _settingsPage(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final currentLocale = Localizations.localeOf(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
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
          leading: const Icon(Icons.cleaning_services_outlined),
          title: Text(l10n.purgeExpiredAttachments),
          subtitle: Text(
            l10n.currentRetention(_attachmentRetentionLabel(_retention, l10n)),
          ),
          onTap: _chooseRetention,
        ),
        ListTile(
          leading: const Icon(Icons.content_copy_outlined),
          title: Text(l10n.packetDeduplicationRetention),
          subtitle: Text(
            l10n.packetRetentionDays(_packetDedupRetention.inDays),
          ),
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

  Future<void> _deleteMessage(ActentMessage message) async {
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

  Future<void> _cancelMessageRequests(ActentMessage message) async {
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
    final l10n = AppLocalizations.of(context)!;
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
          title: Text(l10n.relaySettingsTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: server,
                decoration: InputDecoration(labelText: l10n.ntfyServerUrl),
                keyboardType: TextInputType.url,
              ),
              TextField(
                controller: authorization,
                decoration: InputDecoration(
                  labelText: l10n.authorizationEmptyToClear,
                ),
                obscureText: true,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop((
                server.text.trim(),
                authorization.text.trim().isEmpty
                    ? null
                    : authorization.text.trim(),
              )),
              child: Text(l10n.save),
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
          .showSnackBar(SnackBar(content: Text(l10n.invalidRelayUrl)));
      return;
    }
    try {
      await callback(server, values.$2);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.relaySettingsSaved)));
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.saveFailedWithError(error.toString()))),
      );
    }
  }

  Future<void> _chooseRetention() async {
    final l10n = AppLocalizations.of(context)!;
    final selected = await showDialog<AttachmentRetention>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(l10n.attachmentRetentionTitle),
        children: [
          for (final value in AttachmentRetention.values)
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialogContext).pop(value),
              child: Text(_attachmentRetentionLabel(value, l10n)),
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
      SnackBar(content: Text(l10n.removedExpiredMessages(deleted))),
    );
    final repository = widget.repository;
    if (repository != null) await _loadRepositoryData(repository);
  }

  Future<void> _choosePacketDedupRetention() async {
    final l10n = AppLocalizations.of(context)!;
    final selected = await showDialog<Duration>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(l10n.packetDeduplicationRetentionTitle),
        children: [
          for (final days in const [1, 7, 30, 90])
            SimpleDialogOption(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(Duration(days: days)),
              child: Text(l10n.packetRetentionDays(days)),
            ),
        ],
      ),
    );
    if (selected == null) return;
    setState(() => _packetDedupRetention = selected);
    await widget.onPacketDedupRetentionChanged?.call(selected);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.deduplicationRetentionSaved)));
  }

  Future<void> _exportConfiguration() async {
    final l10n = AppLocalizations.of(context)!;
    final repository = widget.repository;
    if (repository == null) return;
    final json = const JsonEncoder.withIndent('  ')
        .convert(await ActentConfigurationTransfer(repository).export());
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.exportConfigurationTitle),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(child: SelectableText(json)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.close),
          ),
        ],
      ),
    );
  }

  Future<void> _importConfiguration() async {
    final l10n = AppLocalizations.of(context)!;
    final repository = widget.repository;
    if (repository == null) return;
    final controller = TextEditingController();
    final json = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.importConfigurationTitle),
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
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: Text(l10n.import),
          ),
        ],
      ),
    );
    controller.dispose();
    if (json == null) return;
    try {
      await ActentConfigurationTransfer(repository).import(jsonDecode(json));
      await _loadRepositoryData(repository);
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.importFailedWithError(error.toString()))),
      );
    }
  }
}

class _ActentPageData {
  const _ActentPageData({
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
