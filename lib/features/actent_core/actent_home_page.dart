import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
import '../actent_platform/work_definition_picker.dart';

class ActentHomePage extends StatefulWidget {
  const ActentHomePage({
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
    this.canEditWorks = false,
    this.desktopSecrets,
    this.router,
    this.queue,
    this.pickWorkInputFile,
    this.importWorkInputFiles,
    this.initialFilePaths = const [],
    this.externalFilePaths,
    this.peerConnectionStatuses,
    this.probePeerConnections,
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
  final bool canEditWorks;
  final DesktopSecretResolver? desktopSecrets;
  final ActentRouter? router;
  final WorkQueueCoordinator? queue;
  final Future<ActentMessage?> Function()? pickWorkInputFile;
  final Future<ActentMessage?> Function(List<String> paths)?
  importWorkInputFiles;
  final List<String> initialFilePaths;
  final Stream<List<String>>? externalFilePaths;
  final Stream<PeerConnectionStatus>? peerConnectionStatuses;
  final Future<void> Function()? probePeerConnections;
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
  final List<Workflow> _workflows = [];
  final List<WorkflowExecution> _workflowExecutions = [];
  final List<Device> _devices = [];
  final Map<String, _ActivityStatus> _messageStatuses = {};
  final Map<String, WorkRequest> _latestRequestsByMessage = {};
  final Map<String, WorkReceipt> _receiptsByRequest = {};
  String? _selectedActivityId;
  final Map<String, PeerConnectionStatus> _peerConnectionStatusByDevice = {};
  String? _pendingWorkName;
  final PairingCoordinator _pairing = PairingCoordinator();
  StreamSubscription<ActentMessage>? _shareSubscription;
  StreamSubscription<PairingAcceptance>? _pairingAcceptanceSubscription;
  StreamSubscription<List<String>>? _externalFileSubscription;
  StreamSubscription<PeerConnectionStatus>? _peerConnectionSubscription;
  StreamSubscription<void>? _repositoryUpdateSubscription;
  LanPairingServer? _lanPairingServer;
  MdnsPairingAdvertiser? _lanPairingAdvertiser;
  WorkQueueCoordinator? _queue;
  AttachmentRetention _retention = AttachmentRetention.sevenDays;
  late Duration _packetDedupRetention;

  bool get _isAndroid => defaultTargetPlatform == TargetPlatform.android;
  bool get _isIos => defaultTargetPlatform == TargetPlatform.iOS;
  bool get _supportsNetworkWork => true;
  bool get _supportsDesktopWork => !kIsWeb && widget.canEditWorks;

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
        title: l10n.workflows,
        icon: Icons.account_tree_outlined,
        message: l10n.workflowsDescription,
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
      _repositoryUpdateSubscription = widget.router?.repositoryUpdates.listen(
        (_) => unawaited(_loadRepositoryData(repository)),
      );
    }
    _externalFileSubscription = widget.externalFilePaths?.listen(
      _importExternalFiles,
    );
    final probePeerConnections = widget.probePeerConnections;
    if (probePeerConnections != null) {
      unawaited(Future<void>.delayed(Duration.zero, probePeerConnections));
    }
    _peerConnectionSubscription = widget.peerConnectionStatuses?.listen((
      status,
    ) {
      if (!mounted) return;
      setState(() => _peerConnectionStatusByDevice[status.deviceId] = status);
    });
  }

  Future<void> _loadRepositoryData(ActentRepository repository) async {
    final l10n = AppLocalizations.of(context)!;
    final messages = await repository.listMessages();
    var works = await repository.listWorks();
    final workflows = await repository.listWorkflows();
    final workflowExecutions = await repository.listWorkflowExecutions();
    final localDeviceId = widget.deviceId ?? 'local-device';
    final localNullId = 'null-$localDeviceId';
    var localCatalogChanged = false;
    final existingNull = works
        .where((work) => work.id == localNullId)
        .firstOrNull;
    if (existingNull == null &&
        !await repository.wasOwnedWorkDeleted(localNullId)) {
      final nullWork = Work.nullWork(
        id: localNullId,
        ownerDeviceId: localDeviceId,
        name: l10n.nullWork,
      );
      await repository.saveWork(nullWork);
      works = [...works, nullWork];
      localCatalogChanged = true;
    } else if (existingNull != null &&
        existingNull.name == 'Null' &&
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
        !works.any((work) => work.id == 'android-share') &&
        !await repository.wasOwnedWorkDeleted('android-share')) {
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
    final devices = (await repository.listDevices())
        .where((device) => device.id != (widget.deviceId ?? 'local-device'))
        .toList();
    final requests = await repository.listRequests();
    final receipts = await repository.listReceipts();
    final receiptsByRequest = {
      for (final receipt in receipts) receipt.requestId: receipt,
    };
    final latestRequests = <String, WorkRequest>{};
    for (final request in requests) {
      final previous = latestRequests[request.message.id];
      if (previous == null || request.createdAt.isAfter(previous.createdAt)) {
        latestRequests[request.message.id] = request;
      }
    }
    final statuses = <String, _ActivityStatus>{};
    for (final request in latestRequests.values) {
      final receipt = receiptsByRequest[request.requestId];
      statuses[request.message.id] = receipt == null
          ? _ActivityStatus.sending
          : _activityStatusFromReceipt(receipt.status);
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
      _workflows
        ..clear()
        ..addAll(workflows);
      _workflowExecutions
        ..clear()
        ..addAll(workflowExecutions);
      _devices
        ..clear()
        ..addAll(devices);
      _messageStatuses
        ..clear()
        ..addAll(statuses);
      _latestRequestsByMessage
        ..clear()
        ..addAll(latestRequests);
      _receiptsByRequest
        ..clear()
        ..addAll(receiptsByRequest);
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
            case 'desktop-file' when _supportsDesktopWork:
              queue.register(
                work.id,
                DesktopFileRunner(
                  path: DesktopFileBinding.fromWork(work).path,
                  secrets: widget.desktopSecrets,
                ),
              );
            case 'desktop-shell' when _supportsDesktopWork:
              queue.register(
                work.id,
                DesktopScriptRunner(
                  config: DesktopShellBinding.fromWork(work).toConfig(work),
                  secrets: widget.desktopSecrets,
                ),
              );
            case 'web-js':
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
            case 'android-http' || 'http' when _supportsNetworkWork:
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
    setState(
      () => _messageStatuses[request.message.id] = _activityStatusFromReceipt(
        receipt.status,
      ),
    );
  }

  @override
  void dispose() {
    _shareSubscription?.cancel();
    _pairingAcceptanceSubscription?.cancel();
    _externalFileSubscription?.cancel();
    _peerConnectionSubscription?.cancel();
    _repositoryUpdateSubscription?.cancel();
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
    final availableWorks = _works
        .where((work) => work.accepts(message) && _isSelectableWork(work))
        .toList(growable: false);
    final workById = {for (final work in _works) work.id: work};
    final availableWorkflows = _workflows
        .where((workflow) {
          if (!workflow.enabled || workflow.steps.isEmpty) return false;
          final first = workById[workflow.steps.first.workId];
          return first != null &&
              first.accepts(message) &&
              _isSelectableWork(first);
        })
        .toList(growable: false);
    final target = await showModalBottomSheet<_SharedContentTarget>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: Text(l10n.chooseWorkOrWorkflow),
              subtitle: Text(l10n.chooseWorkDescription),
            ),
            if (availableWorks.isNotEmpty)
              ListTile(dense: true, title: Text(l10n.works)),
            for (final availableWork in availableWorks)
              ListTile(
                leading: const Icon(Icons.play_arrow_outlined),
                title: Text(availableWork.name),
                subtitle: Text(
                  '${availableWork.ownerDeviceId == (widget.deviceId ?? 'local-device') ? l10n.thisDevice : l10n.remoteDevice} · revision ${availableWork.revision}',
                ),
                onTap: () =>
                    Navigator.of(context)
                        .pop(_SharedContentTarget.work(availableWork)),
              ),
            if (availableWorkflows.isNotEmpty)
              ListTile(dense: true, title: Text(l10n.workflows)),
            for (final workflow in availableWorkflows)
              ListTile(
                leading: const Icon(Icons.account_tree_outlined),
                title: Text(workflow.name),
                subtitle: Text(
                  '${workflow.steps.length} ${l10n.workflowSteps}',
                ),
                onTap: () =>
                    Navigator.of(context)
                        .pop(_SharedContentTarget.workflow(workflow)),
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
    if (target == null || !mounted) return;
    final work = target.work;
    if (work != null) {
      await _routeMessageToWork(message, work);
      return;
    }
    final workflow = target.workflow;
    if (workflow != null) await _runWorkflowWithMessage(workflow, message);
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
    final normalized = work.acceptedContentTypes.toSet();
    if (normalized.contains(ActentContentType.text)) {
      normalized.remove(ActentContentType.none);
    }
    final types = normalized.toList()
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
      ActentContentType.none => 'text',
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
        ActentContentType.none => l10n.inputText,
        ActentContentType.text => l10n.inputText,
        ActentContentType.url => l10n.inputUrl,
        ActentContentType.image => l10n.inputImage,
        ActentContentType.file => l10n.inputFile,
        ActentContentType.json => l10n.inputJson,
      };

  IconData _contentTypeIcon(ActentContentType type) => switch (type) {
    ActentContentType.none => Icons.text_fields,
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
    if (mounted) {
      setState(() => _messageStatuses[message.id] = _ActivityStatus.sending);
    }
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
      if (mounted) {
        setState(
          () => _messageStatuses[message.id] = _ActivityStatus.sendFailed,
        );
      }
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
        ? _activityPage(context, pages[0])
        : _selectedIndex == 1
        ? _worksPage(context)
        : _selectedIndex == 2
        ? _workflowsPage(context)
        : _selectedIndex == 3
        ? _devicesPage(context)
        : _settingsPage(context);
    return Scaffold(
      appBar: AppBar(title: Text(page.title)),
      body: body,
      floatingActionButton: _selectedIndex == 3
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
          : _selectedIndex == 2
          ? FloatingActionButton.extended(
              onPressed: _showAddWorkflow,
              icon: const Icon(Icons.add),
              label: Text(AppLocalizations.of(context)!.addWorkflow),
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
                        '${_workKindLabel(work, l10n)} · '
                        '${work.enabled ? l10n.enable : l10n.disable}',
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

  Widget _workflowsPage(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (_workflows.isEmpty && _workflowExecutions.isEmpty) {
      return _emptyPage(_pages(context)[2]);
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final workflow in _workflows)
          Card(
            child: ListTile(
              leading: IconButton(
                tooltip: l10n.runWork,
                icon: const Icon(Icons.play_arrow_outlined),
                onPressed: workflow.enabled
                    ? () => _runWorkflow(workflow)
                    : null,
              ),
              title: Text(workflow.name),
              subtitle: Text(
                '${workflow.steps.length} ${l10n.workflowSteps} · '
                '${workflow.enabled ? l10n.workflowReady : l10n.workflowInvalid}',
              ),
              trailing: _isLocalWorkflow(workflow)
                  ? PopupMenuButton<String>(
                      onSelected: (value) async {
                        if (value == 'delete') {
                          final repository = widget.repository;
                          if (repository == null) return;
                          await repository.deleteWorkflow(workflow.id);
                          await _publishCatalogChanges();
                          await _loadRepositoryData(repository);
                        }
                      },
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: 'delete',
                          child: Text(l10n.delete),
                        ),
                      ],
                    )
                  : null,
            ),
          ),
        for (final execution in _workflowExecutions.reversed)
          Card(
            child: ListTile(
              leading: const Icon(Icons.history_outlined),
              title: Text(
                _workflows
                        .where(
                          (workflow) => workflow.id == execution.workflowId,
                        )
                        .firstOrNull
                        ?.name ??
                    execution.workflowId,
              ),
              subtitle: Text(
                '${execution.status.value} · step ${execution.currentStepIndex + 1}',
              ),
              trailing: execution.status == WorkflowExecutionStatus.failed
                  ? TextButton(
                      onPressed: () => _continueWorkflow(execution),
                      child: Text(l10n.continueLabel),
                    )
                  : null,
            ),
          ),
      ],
    );
  }

  Future<void> _continueWorkflow(WorkflowExecution execution) async {
    final router = widget.router;
    final repository = widget.repository;
    if (router == null || repository == null) return;
    final workflow = await repository.getWorkflow(execution.workflowId);
    if (workflow == null) return;
    final updated = await router.continueWorkflow(workflow, execution);
    await _loadRepositoryData(repository);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(updated.status.value)));
  }

  bool _isLocalWorkflow(Workflow workflow) =>
      workflow.ownerDeviceId == (widget.deviceId ?? 'local-device');

  Future<void> _runWorkflow(Workflow workflow) async {
    final router = widget.router;
    if (router == null || workflow.steps.isEmpty) return;
    final first = _works
        .where((work) => work.id == workflow.steps.first.workId)
        .firstOrNull;
    if (first == null || !first.enabled || !_isSelectableWork(first)) return;
    final inputType = first.acceptedContentTypes.length == 1
        ? first.acceptedContentTypes.single
        : await _showInputTypePicker(first);
    if (inputType == null || !mounted) return;
    ActentMessage? message;
    if ((inputType == ActentContentType.file ||
            inputType == ActentContentType.image ||
            inputType == ActentContentType.json) &&
        widget.pickWorkInputFile != null) {
      message = await widget.pickWorkInputFile!();
    } else if (inputType == ActentContentType.text ||
        inputType == ActentContentType.url ||
        inputType == ActentContentType.json) {
      message = await _showManualInputDialog(inputType);
    }
    if (message == null || !mounted || !first.accepts(message)) return;
    await _runWorkflowWithMessage(workflow, message);
  }

  Future<void> _runWorkflowWithMessage(
    Workflow workflow,
    ActentMessage message,
  ) async {
    final router = widget.router;
    if (router == null || workflow.steps.isEmpty) return;
    final repository = widget.repository;
    if (repository == null) return;
    final l10n = AppLocalizations.of(context)!;
    try {
      final execution = await router.runWorkflow(message, workflow);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            execution.status == WorkflowExecutionStatus.succeeded
                ? l10n.activitySucceeded
                : '${l10n.workflowInvalid}: ${execution.error?.code ?? execution.status.value}',
          ),
        ),
      );
      await _loadRepositoryData(repository);
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.workRequestFailed(error.toString()))),
      );
    }
  }

  Future<void> _showAddWorkflow() async {
    final repository = widget.repository;
    if (repository == null) return;
    final l10n = AppLocalizations.of(context)!;
    final candidates = _works.where(_isSelectableWork).toList()
      ..sort((left, right) => left.name.compareTo(right.name));
    final result = await showDialog<(String, List<WorkflowStep>)>(
      context: context,
      builder: (dialogContext) {
        final nameController = TextEditingController();
        final steps = <WorkflowStep>[];
        String? selectedWorkId;
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text(l10n.addWorkflow),
            content: SizedBox(
              width: 480,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: InputDecoration(labelText: l10n.workflowName),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(l10n.workflowSteps),
                  ),
                  for (var index = 0; index < steps.length; index++)
                    ListTile(
                      dense: true,
                      leading: Text('${index + 1}'),
                      title: Text(
                        _workSelectionLabel(
                          _works.firstWhere(
                            (work) => work.id == steps[index].workId,
                          ),
                          l10n,
                        ),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: () =>
                            setDialogState(() => steps.removeAt(index)),
                      ),
                    ),
                  if (candidates.isNotEmpty)
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButton<String>(
                            isExpanded: true,
                            value: selectedWorkId,
                            hint: Text(l10n.addWorkflowStep),
                            items: [
                              for (final work in candidates)
                                DropdownMenuItem(
                                  value: work.id,
                                  child: Text(
                                    _workSelectionLabel(work, l10n),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged: (value) =>
                                setDialogState(() => selectedWorkId = value),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.add),
                          onPressed: selectedWorkId == null
                              ? null
                              : () {
                                  final work = candidates.firstWhere(
                                    (item) => item.id == selectedWorkId,
                                  );
                                  setDialogState(() {
                                    steps.add(
                                      WorkflowStep(
                                        id: 'step-${steps.length + 1}',
                                        workId: work.id,
                                        workRevision: work.revision,
                                        deviceId: work.ownerDeviceId,
                                      ),
                                    );
                                    selectedWorkId = null;
                                  });
                                },
                        ),
                      ],
                    )
                  else
                    Text(l10n.noWorkflowSteps),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(l10n.cancel),
              ),
              FilledButton(
                onPressed: steps.isEmpty || nameController.text.trim().isEmpty
                    ? null
                    : () => Navigator.pop(dialogContext, (
                        nameController.text.trim(),
                        List.of(steps),
                      )),
                child: Text(l10n.save),
              ),
            ],
          ),
        );
      },
    );
    if (result == null) return;
    final now = DateTime.now().toUtc();
    await repository.saveWorkflow(
      Workflow(
        id: 'workflow-${now.microsecondsSinceEpoch}',
        revision: 1,
        name: result.$1,
        ownerDeviceId: widget.deviceId ?? 'local-device',
        steps: result.$2,
        acceptedContentTypes: ActentContentType.values.toSet(),
      ),
    );
    await _publishCatalogChanges();
    await _loadRepositoryData(repository);
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
    'web-js' => true,
    'desktop-script' => _supportsDesktopWork,
    'desktop-file' || 'desktop-shell' => _supportsDesktopWork,
    _ => false,
  };

  String _workOwnerLabel(Work work, AppLocalizations l10n) {
    if (_isLocalWork(work)) return l10n.thisDevice;
    for (final device in _devices) {
      if (device.id == work.ownerDeviceId) return device.displayName;
    }
    return work.ownerDeviceId;
  }

  String _workSelectionLabel(Work work, AppLocalizations l10n) =>
      '${work.name} — ${_workOwnerLabel(work, l10n)}';

  String _workKindLabel(Work work, AppLocalizations l10n) =>
      switch (work.platformBindings['kind']) {
        'null' => l10n.nullWorkType,
        'desktop-shell' => l10n.shellWorkType,
        'desktop-file' || 'desktop-script' => l10n.fileWorkType,
        'web-js' => l10n.javaScriptWorkType,
        'android-intent' || 'ios-url' => l10n.applicationWorkType,
        'android-http' || 'http' => l10n.networkWorkType,
        _ => work.platformBindings['kind'] as String? ?? l10n.works,
      };

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
    if (!mounted) return;
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
              if (_supportsDesktopWork)
                ListTile(
                  leading: const Icon(Icons.terminal),
                  title: Text(l10n.fileWorkType),
                  onTap: () => Navigator.pop(dialogContext, 'file'),
                ),
              if (_supportsDesktopWork)
                ListTile(
                  leading: const Icon(Icons.code),
                  title: Text(l10n.shellWorkType),
                  onTap: () => Navigator.pop(dialogContext, 'shell'),
                ),
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
      case 'file':
        await _addDesktopFileWork();
      case 'shell':
        await _addDesktopShellWork();
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

  Future<void> _addDesktopFileWork() => _editDesktopFileWork();

  Future<void> _addDesktopShellWork() => _editDesktopShellWork();

  Future<void> _addWebJsWork() => _editWebJsWork();

  Future<bool> _trySaveWork(ActentRepository repository, Work work) async {
    try {
      await repository.saveWork(work);
      return true;
    } on StateError catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.workNameAlreadyExists),
          ),
        );
      }
      debugPrint('Unable to save Work: $error');
      return false;
    }
  }

  Future<void> _addNullWork() async {
    final repository = widget.repository;
    if (repository == null) return;
    final l10n = AppLocalizations.of(context)!;
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        final controller = TextEditingController(text: _pendingWorkName ?? '');
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
    if (!await _trySaveWork(
      repository,
      Work(
        id: 'null-${DateTime.now().microsecondsSinceEpoch}',
        revision: 1,
        name: name,
        ownerDeviceId: widget.deviceId ?? 'local-device',
        acceptedContentTypes: ActentContentType.values.toSet(),
        platformBindings: const {'kind': 'null'},
      ),
    )) {
      return;
    }
    await _publishCatalogChanges();
    await _loadRepositoryData(repository);
  }

  Future<void> _addAndroidApplicationWork() async {
    final l10n = AppLocalizations.of(context)!;
    final values = await showDialog<(String, String, String)?>(
      context: context,
      builder: (dialogContext) {
        final name = TextEditingController(text: _pendingWorkName ?? '');
        var action = 'android.intent.action.SEND';
        return AlertDialog(
          title: Text(l10n.addApplicationWork),
          content: StatefulBuilder(
            builder: (context, setState) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: InputDecoration(labelText: l10n.name),
                ),
                DropdownButtonFormField<String>(
                  initialValue: action,
                  decoration: InputDecoration(labelText: l10n.intentAction),
                  items: const [
                    DropdownMenuItem(
                      value: 'android.intent.action.SEND',
                      child: Text('Share text or files'),
                    ),
                    DropdownMenuItem(
                      value: 'android.intent.action.VIEW',
                      child: Text('Open a URL'),
                    ),
                  ],
                  onChanged: (value) =>
                      setState(() => action = value ?? action),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, (
                name.text.trim(),
                action,
                action == 'android.intent.action.VIEW'
                    ? 'text/uri-list'
                    : 'text/plain',
              )),
              child: Text(l10n.save),
            ),
          ],
        );
      },
    );
    if (values == null || values.$1.isEmpty) return;
    final bridge = widget.shareBridge;
    if (bridge == null) return;
    final targets = await bridge.findIntentTargets(
      action: values.$2,
      mimeType: values.$3,
    );
    if (!mounted) return;
    if (targets.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.noCompatibleApps)));
      return;
    }
    final target = await showDialog<AndroidIntentTarget>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.chooseApplication),
        content: SizedBox(
          width: 420,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: targets.length,
            itemBuilder: (context, index) {
              final item = targets[index];
              return ListTile(
                title: Text(item.label),
                subtitle: Text(item.packageName),
                onTap: () => Navigator.pop(dialogContext, item),
              );
            },
          ),
        ),
      ),
    );
    if (target == null) return;
    await _saveCreatedAndroidWork(
      name: values.$1,
      idPrefix: 'android-intent',
      bindings: {
        'kind': 'android-intent',
        'action': values.$2,
        'mimeType': values.$3,
        'categories': const <String>[],
        'extras': const <String, Object?>{},
        'chooser': false,
        'attachmentPlacement': values.$2 == 'android.intent.action.VIEW'
            ? 'none'
            : 'streams',
        'packageName': target.packageName,
        'componentName': target.componentName,
      },
    );
  }

  Future<void> _addAndroidNetworkWork() async {
    final l10n = AppLocalizations.of(context)!;
    final values = await showDialog<(String, String, String, String, String)?>(
      context: context,
      builder: (dialogContext) {
        final name = TextEditingController(text: _pendingWorkName ?? '');
        final url = TextEditingController(text: 'https://');
        final headers = TextEditingController();
        final body = TextEditingController();
        var method = 'POST';
        return AlertDialog(
          title: Text(l10n.addNetworkWork),
          content: SingleChildScrollView(
            child: Column(
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
                StatefulBuilder(
                  builder: (context, setState) =>
                      DropdownButtonFormField<String>(
                        initialValue: method,
                        decoration: InputDecoration(
                          labelText: l10n.networkMethod,
                        ),
                        items: const ['GET', 'POST', 'PUT', 'PATCH', 'DELETE']
                            .map(
                              (value) => DropdownMenuItem(
                                value: value,
                                child: Text(value),
                              ),
                            )
                            .toList(),
                        onChanged: (value) =>
                            setState(() => method = value ?? 'POST'),
                      ),
                ),
                TextField(
                  controller: headers,
                  decoration: InputDecoration(
                    labelText: l10n.networkHeaders,
                    hintText: 'Content-Type: application/json',
                  ),
                  maxLines: 3,
                ),
                TextField(
                  controller: body,
                  decoration: InputDecoration(labelText: l10n.networkBody),
                  maxLines: 5,
                ),
              ],
            ),
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
                method,
                headers.text,
                body.text,
              )),
              child: Text(l10n.save),
            ),
          ],
        );
      },
    );
    if (values == null || values.$1.isEmpty || values.$2.isEmpty) return;
    final headers = <String, String>{};
    for (final line in values.$4.split(RegExp(r'\r?\n'))) {
      final separator = line.indexOf(':');
      if (separator > 0) {
        headers[line.substring(0, separator).trim()] = line
            .substring(separator + 1)
            .trim();
      }
    }
    await _saveCreatedAndroidWork(
      name: values.$1,
      idPrefix: 'http',
      bindings: {
        'kind': 'http',
        'urlTemplate': values.$2,
        'method': values.$3,
        'headers': headers,
        if (values.$5.trim().isNotEmpty)
          'bodyTemplate': values.$5
        else if (values.$3 != 'GET' && values.$3 != 'DELETE')
          'bodyTemplate': '{{content.text}}',
      },
    );
  }

  Future<void> _addIosApplicationWork() async {
    final l10n = AppLocalizations.of(context)!;
    final values = await showDialog<(String, String, String)?>(
      context: context,
      builder: (dialogContext) {
        final name = TextEditingController(text: _pendingWorkName ?? '');
        final url = TextEditingController();
        var mode = 'url';
        return AlertDialog(
          title: Text(l10n.addApplicationWork),
          content: StatefulBuilder(
            builder: (context, setState) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: InputDecoration(labelText: l10n.name),
                ),
                DropdownButtonFormField<String>(
                  initialValue: mode,
                  decoration: InputDecoration(
                    labelText: l10n.iosApplicationMode,
                  ),
                  items: [
                    DropdownMenuItem(
                      value: 'url',
                      child: Text(l10n.applicationUrl),
                    ),
                    DropdownMenuItem(
                      value: 'shortcut',
                      child: Text(l10n.shortcutName),
                    ),
                  ],
                  onChanged: (value) => setState(() => mode = value ?? mode),
                ),
                TextField(
                  controller: url,
                  decoration: InputDecoration(
                    labelText: mode == 'shortcut'
                        ? l10n.shortcutName
                        : l10n.applicationUrl,
                  ),
                ),
              ],
            ),
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
                mode,
              )),
              child: Text(l10n.save),
            ),
          ],
        );
      },
    );
    if (values == null || values.$1.isEmpty || values.$2.isEmpty) return;
    final urlTemplate = values.$3 == 'shortcut'
        ? 'shortcuts://run-shortcut?name=${Uri.encodeComponent(values.$2)}&input={{content.text}}'
        : values.$2;
    await _saveCreatedAndroidWork(
      name: values.$1,
      idPrefix: 'ios-url',
      bindings: {'kind': 'ios-url', 'urlTemplate': urlTemplate},
    );
  }

  Future<void> _saveCreatedAndroidWork({
    required String name,
    required String idPrefix,
    required Map<String, Object?> bindings,
  }) async {
    final repository = widget.repository;
    if (repository == null) return;
    if (!await _trySaveWork(
      repository,
      Work(
        id: '$idPrefix-${DateTime.now().microsecondsSinceEpoch}',
        revision: 1,
        name: name,
        ownerDeviceId: widget.deviceId ?? 'local-device',
        acceptedContentTypes: ActentContentType.values.toSet(),
        platformBindings: bindings,
      ),
    )) {
      return;
    }
    await _publishCatalogChanges();
    await _loadRepositoryData(repository);
  }

  Future<void> _editWork(Work work) => switch (work.platformBindings['kind']) {
    'null' => _editNullWork(work),
    'web-js' => _editWebJsWork(work),
    'desktop-script' when _supportsDesktopWork => _editDesktopWork(work),
    'desktop-file' when _supportsDesktopWork => _editDesktopFileWork(work),
    'desktop-shell' when _supportsDesktopWork => _editDesktopShellWork(work),
    _ => Future<void>.value(),
  };

  Future<void> _editDesktopShellWork([Work? existing]) async {
    final l10n = AppLocalizations.of(context)!;
    final values = await showDialog<(String, String)?>(
      context: context,
      builder: (dialogContext) {
        final name = TextEditingController(
          text: existing?.name ?? _pendingWorkName ?? '',
        );
        final source = TextEditingController(
          text: existing?.platformBindings['source'] as String? ?? '',
        );
        final shell = defaultTargetPlatform == TargetPlatform.windows
            ? 'powershell.exe'
            : defaultTargetPlatform == TargetPlatform.macOS
            ? 'zsh'
            : 'bash';
        final dialogWidth = MediaQuery.sizeOf(dialogContext).width - 32;
        return AlertDialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 24,
          ),
          title: Text(
            existing == null ? l10n.addShellWork : l10n.editShellWork,
          ),
          content: SingleChildScrollView(
            child: SizedBox(
              width: dialogWidth.clamp(0.0, 720.0).toDouble(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: name,
                    decoration: InputDecoration(labelText: l10n.name),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('${l10n.shell}: $shell'),
                  ),
                  TextField(
                    controller: source,
                    decoration: InputDecoration(labelText: l10n.shellSource),
                    minLines: 10,
                    maxLines: 18,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, (name.text.trim(), source.text)),
              child: Text(l10n.save),
            ),
          ],
        );
      },
    );
    if (values == null || values.$1.isEmpty || values.$2.trim().isEmpty) return;
    final repository = widget.repository;
    if (repository == null) return;
    final shell = defaultTargetPlatform == TargetPlatform.windows
        ? 'powershell.exe'
        : defaultTargetPlatform == TargetPlatform.macOS
        ? 'zsh'
        : 'bash';
    if (!await _trySaveWork(
      repository,
      Work(
        id: existing?.id ?? 'shell-${DateTime.now().microsecondsSinceEpoch}',
        revision: (existing?.revision ?? 0) + 1,
        name: values.$1,
        ownerDeviceId: widget.deviceId ?? 'local-device',
        allowedSourceDeviceIds: existing?.allowedSourceDeviceIds ?? const {},
        acceptedContentTypes: ActentContentType.values.toSet(),
        timeout: existing?.timeout ?? const Duration(hours: 24),
        queueLimit: existing?.queueLimit ?? 10,
        platformBindings: {
          'kind': 'desktop-shell',
          'shell': shell,
          'source': values.$2,
        },
        catalogVisibility: existing?.catalogVisibility ?? const {},
      ),
    )) {
      return;
    }
    await _publishCatalogChanges();
    await _loadRepositoryData(repository);
  }

  Future<void> _editDesktopFileWork([Work? existing]) async {
    final l10n = AppLocalizations.of(context)!;
    final values = await showDialog<(String, String)?>(
      context: context,
      builder: (dialogContext) {
        final name = TextEditingController(
          text: existing?.name ?? _pendingWorkName ?? '',
        );
        final path = TextEditingController(
          text: existing?.platformBindings['path'] as String? ?? '',
        );
        return StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: Text(
              existing == null ? l10n.addFileWork : l10n.editFileWork,
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: InputDecoration(labelText: l10n.name),
                ),
                TextField(
                  controller: path,
                  readOnly: true,
                  decoration: InputDecoration(
                    labelText: l10n.programOrScriptFile,
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.folder_open),
                      onPressed: () async {
                        final selected = await pickWorkDefinitionFile();
                        if (selected != null) {
                          setState(() => path.text = selected);
                        }
                      },
                    ),
                  ),
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
                  path.text.trim(),
                )),
                child: Text(l10n.save),
              ),
            ],
          ),
        );
      },
    );
    if (values == null || values.$1.isEmpty || values.$2.isEmpty) return;
    final repository = widget.repository;
    if (repository == null) return;
    if (!await _trySaveWork(
      repository,
      Work(
        id: existing?.id ?? 'file-${DateTime.now().microsecondsSinceEpoch}',
        revision: (existing?.revision ?? 0) + 1,
        name: values.$1,
        ownerDeviceId: widget.deviceId ?? 'local-device',
        allowedSourceDeviceIds: existing?.allowedSourceDeviceIds ?? const {},
        acceptedContentTypes: ActentContentType.values.toSet(),
        timeout: existing?.timeout ?? const Duration(hours: 24),
        queueLimit: existing?.queueLimit ?? 10,
        platformBindings: {'kind': 'desktop-file', 'path': values.$2},
        catalogVisibility: existing?.catalogVisibility ?? const {},
      ),
    )) {
      return;
    }
    await _publishCatalogChanges();
    await _loadRepositoryData(repository);
  }

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
    if (!await _trySaveWork(
      repository,
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
    )) {
      return;
    }
    await _publishCatalogChanges();
    await _loadRepositoryData(repository);
  }

  Future<void> _editWebJsWork([Work? existing]) async {
    final l10n = AppLocalizations.of(context)!;
    final values = await showDialog<(String, String, String)?>(
      context: context,
      builder: (dialogContext) {
        final name = TextEditingController(
          text: existing?.name ?? _pendingWorkName ?? '',
        );
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
    if (!await _trySaveWork(repository, work)) return;
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
    if (!await _trySaveWork(repository, work)) return;
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
        try {
          await widget.router?.cancelRequest(request.requestId);
        } on Object {
          // A remote peer may be offline. Deleting the local definition must
          // not be blocked by best-effort cancellation of its old request.
        }
      }
    }
    await repository.deleteOwnedWork(work.id);
    await _publishCatalogChanges();
    await _loadRepositoryData(repository);
  }

  Future<void> _publishCatalogChanges() async {
    final router = widget.router;
    if (router == null) return;
    await router.publishCatalogSnapshotToPeers();
  }

  Widget _devicesPage(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return _devices.isEmpty
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
              for (final device in _devices) _deviceCard(device, l10n),
            ],
          );
  }

  Widget _deviceCard(Device device, AppLocalizations l10n) {
    final status = _peerConnectionStatusByDevice[device.id];
    final connected = status?.state == PeerConnectionState.connected;
    final statusLabel = status == null
        ? l10n.deviceConnectionChecking
        : connected
        ? l10n.deviceConnected
        : l10n.deviceDisconnected;
    return Card(
      child: ListTile(
        leading: Icon(
          connected ? Icons.link : Icons.link_off,
          color: connected ? Colors.green : Colors.grey,
        ),
        title: Text(_deviceLabel(device, l10n)),
        subtitle: Text(
          '$statusLabel · ${device.platform} · ${_shortDeviceId(device.id)}',
        ),
        trailing: Icon(
          device.authorized ? Icons.verified_outlined : Icons.block,
          color: device.authorized ? Colors.green : Colors.red,
        ),
        onTap: () => _unpairDevice(device),
      ),
    );
  }

  String _deviceLabel(Device device, AppLocalizations l10n) {
    final name = device.displayName.trim();
    if (name.isEmpty || name == device.id || name == 'Actent device') {
      return l10n.unnamedDevice;
    }
    return name;
  }

  String _shortDeviceId(String deviceId) {
    final value = deviceId.startsWith('device-')
        ? deviceId.substring('device-'.length)
        : deviceId;
    if (value.length <= 12) return value;
    return '${value.substring(0, 6)}…${value.substring(value.length - 4)}';
  }

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
    final router = widget.router;
    if (router != null) {
      await router.unpair(device.id);
    } else {
      await repository.deleteDevice(device.id);
    }
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
      relayUrl:
          widget.pairingHandshake?.server.toString() ??
          'https://actent.wkzmagician.top',
      controlTopic: widget.relayTopic ?? '',
      blobTopic: widget.relayBlobTopic ?? '',
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
      controlTopic: invite.issuerControlTopic,
      blobTopic: invite.issuerBlobTopic,
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
      relayUrl:
          pairingHandshake?.server.toString() ??
          'https://actent.wkzmagician.top',
      temporaryTopic: 'actent-pair-${DateTime.now().microsecondsSinceEpoch}',
      issuerControlTopic: widget.relayTopic ?? '',
      issuerBlobTopic: widget.relayBlobTopic ?? '',
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
        controlTopic: widget.relayTopic ?? '',
        blobTopic: widget.relayBlobTopic ?? '',
        lanHost: widget.lanHost,
        lanPort: widget.lanPort,
        certificateSha256: widget.lanCertificateSha256,
      );
      await _savePairedDevice(
        invite,
        authorized: false,
        controlTopic: invite.issuerControlTopic,
        blobTopic: invite.issuerBlobTopic,
      );
      _waitForPairingConfirmation(invite, acceptance);
      return;
    }
    await _savePairedDevice(
      invite,
      authorized: true,
      controlTopic: invite.issuerControlTopic,
      blobTopic: invite.issuerBlobTopic,
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
            'relayTopic': acceptance.controlTopic,
            'relayBlobTopic': acceptance.blobTopic,
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
      await widget.router?.sendDeviceUpdate(acceptance.deviceId);
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
        controlTopic: invite.issuerControlTopic,
        blobTopic: invite.issuerBlobTopic,
      );
    } on Object {
      // The pending device remains unauthorized until the user retries the
      // invitation; no endpoint becomes selectable on a timeout.
    }
  }

  Future<void> _savePairedDevice(
    PairingInvite invite, {
    required bool authorized,
    required String controlTopic,
    required String blobTopic,
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
          'relayTopic': controlTopic,
          'relayBlobTopic': blobTopic,
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
      await router.sendDeviceUpdate(invite.issuerDeviceId);
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
            '${widget.relayServer ?? Uri.parse('https://actent.wkzmagician.top')}'
            '${widget.relayTokenConfigured ? ' · ${l10n.authorizationConfigured}' : ''}',
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

  Widget _activityPage(BuildContext context, _ActentPageData page) {
    if (_messages.isEmpty) return _emptyPage(page);
    final wide = MediaQuery.sizeOf(context).width >= 800;
    final selected =
        _messages.where((item) => item.id == _selectedActivityId).firstOrNull ??
        _messages.first;
    final list = ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final message = _messages[index];
        return Card(
          color: wide && message.id == selected.id
              ? Theme.of(context).colorScheme.secondaryContainer
              : null,
          child: ListTile(
            onTap: () {
              if (wide) {
                setState(() => _selectedActivityId = message.id);
              } else {
                unawaited(_openActivityDetails(message));
              }
            },
            leading: const Icon(Icons.share_outlined),
            title: Text(_messagePreview(message)),
            subtitle: Text(
              '${_activityTime(message.createdAt)} · '
              '${_activityStatusLabel(_messageStatuses[message.id], AppLocalizations.of(context)!)}',
            ),
            trailing: PopupMenuButton<String>(
              onSelected: (value) async {
                if (value == 'retry') {
                  await _retryMessage(message);
                } else if (value == 'discard') {
                  await _discardMessage(message);
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'retry',
                  child: Text(AppLocalizations.of(context)!.resend),
                ),
                PopupMenuItem(
                  value: 'discard',
                  child: Text(AppLocalizations.of(context)!.discard),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (!wide) return list;
    return Row(
      children: [
        SizedBox(width: 380, child: list),
        const VerticalDivider(width: 1),
        Expanded(child: _activityDetails(selected, embedded: true)),
      ],
    );
  }

  _ActivityDetailPage _activityDetails(
    ActentMessage message, {
    bool embedded = false,
  }) {
    final request = _latestRequestsByMessage[message.id];
    final receipt = request == null
        ? null
        : _receiptsByRequest[request.requestId];
    return _ActivityDetailPage(
      message: message,
      request: request,
      receipt: receipt,
      embedded: embedded,
      status: _activityStatusLabel(
        _messageStatuses[message.id],
        AppLocalizations.of(context)!,
      ),
      time: _activityTime(message.createdAt),
    );
  }

  Future<void> _discardMessage(ActentMessage message) async {
    await _cancelMessageRequests(message);
    await _deleteMessage(message);
  }

  Future<void> _openActivityDetails(ActentMessage message) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => _activityDetails(message)),
    );
  }

  Future<void> _retryMessage(ActentMessage message) async {
    final repository = widget.repository;
    if (repository == null) return;
    final request = (await repository.listRequests())
        .where((item) => item.message.id == message.id)
        .fold<WorkRequest?>(
          null,
          (latest, item) =>
              latest == null || item.createdAt.isAfter(latest.createdAt)
              ? item
              : latest,
        );
    if (request == null) return;
    final work = await repository.getWork(request.workId);
    if (work == null) return;
    await _routeMessageToWork(message, work);
  }

  _ActivityStatus _activityStatusFromReceipt(WorkReceiptStatus status) =>
      switch (status) {
        WorkReceiptStatus.stored => _ActivityStatus.received,
        WorkReceiptStatus.queued => _ActivityStatus.queued,
        WorkReceiptStatus.processing => _ActivityStatus.processing,
        WorkReceiptStatus.cancelling => _ActivityStatus.cancelling,
        WorkReceiptStatus.interrupted => _ActivityStatus.interrupted,
        WorkReceiptStatus.succeeded => _ActivityStatus.succeeded,
        WorkReceiptStatus.failed => _ActivityStatus.failed,
        WorkReceiptStatus.expired => _ActivityStatus.expired,
        WorkReceiptStatus.cancelled => _ActivityStatus.cancelled,
      };

  String _activityStatusLabel(_ActivityStatus? status, AppLocalizations l10n) =>
      switch (status ?? _ActivityStatus.sending) {
        _ActivityStatus.sending => l10n.activitySending,
        _ActivityStatus.sendFailed => l10n.activitySendFailed,
        _ActivityStatus.received => l10n.activityReceived,
        _ActivityStatus.queued => l10n.activityQueued,
        _ActivityStatus.processing => l10n.activityProcessing,
        _ActivityStatus.cancelling => l10n.activityCancelling,
        _ActivityStatus.interrupted => l10n.activityInterrupted,
        _ActivityStatus.failed => l10n.activityFailed,
        _ActivityStatus.expired => '已过期',
        _ActivityStatus.cancelled => '已取消',
        _ActivityStatus.succeeded => l10n.activitySucceeded,
      };

  String _messagePreview(ActentMessage message) {
    final value = message.content.data['text'] ?? message.content.data['url'];
    if (value is String && value.trim().isNotEmpty) {
      return value.trim().replaceAll(RegExp(r'\s+'), ' ');
    }
    if (message.attachments.isNotEmpty) return message.attachments.first.name;
    return message.content.type.value;
  }

  String _activityTime(DateTime value) {
    final local = value.toLocal();
    String twoDigits(int item) => item.toString().padLeft(2, '0');
    return '${local.year}-${twoDigits(local.month)}-${twoDigits(local.day)} '
        '${twoDigits(local.hour)}:${twoDigits(local.minute)}';
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
    setState(() {
      _messages.removeWhere((item) => item.id == message.id);
      _messageStatuses.remove(message.id);
    });
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
          text:
              (widget.relayServer ??
                      Uri.parse('https://actent.wkzmagician.top'))
                  .toString(),
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

class _SharedContentTarget {
  const _SharedContentTarget._({this.work, this.workflow});

  const _SharedContentTarget.work(Work value) : this._(work: value);

  const _SharedContentTarget.workflow(Workflow value) : this._(workflow: value);

  final Work? work;
  final Workflow? workflow;
}

class _ActivityDetailPage extends StatelessWidget {
  const _ActivityDetailPage({
    required this.message,
    required this.request,
    required this.receipt,
    this.embedded = false,
    required this.status,
    required this.time,
  });

  final ActentMessage message;
  final WorkRequest? request;
  final WorkReceipt? receipt;
  final bool embedded;
  final String status;
  final String time;

  @override
  Widget build(BuildContext context) {
    final diagnostics = receipt?.diagnostics;
    final summary = receipt?.summary;
    final body = ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _detailCard('状态', status),
        _detailCard('时间', time),
        _detailCard(
          '内容',
          const JsonEncoder.withIndent('  ').convert(message.payload.toJson()),
        ),
        if (request != null) ...[
          _detailCard('任务', request!.workId),
          _detailCard('请求 ID', request!.requestId),
          _detailCard('目标设备', request!.targetDeviceId),
        ],
        if (receipt?.errorCode != null) _detailCard('错误码', receipt!.errorCode!),
        if (summary != null && summary.isNotEmpty)
          _diagnosticCard(context, '错误摘要', summary),
        if (diagnostics != null) ...[
          _detailCard('执行阶段', diagnostics.stage),
          if (diagnostics.exitCode != null)
            _detailCard('退出码', '${diagnostics.exitCode}'),
          if (diagnostics.duration != null)
            _detailCard('耗时', '${diagnostics.duration!.inMilliseconds} ms'),
          if (diagnostics.stdout != null)
            _diagnosticCard(
              context,
              '标准输出',
              diagnostics.stdout!,
              diagnostics.stdoutTruncated,
            ),
          if (diagnostics.stderr != null)
            _diagnosticCard(
              context,
              '标准错误输出',
              diagnostics.stderr!,
              diagnostics.stderrTruncated,
            ),
        ],
      ],
    );
    if (embedded) return body;
    return Scaffold(
      appBar: AppBar(title: const Text('活动详情')),
      body: body,
    );
  }

  Widget _detailCard(String title, String value) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          SelectableText(value),
        ],
      ),
    ),
  );

  Widget _diagnosticCard(
    BuildContext context,
    String title,
    String value, [
    bool truncated = false,
  ]) {
    final previewByLines = value.split('\n').take(100).join('\n');
    final display = previewByLines.length > 8192
        ? previewByLines.substring(0, 8192)
        : previewByLines;
    final omitted = truncated || display.length < value.length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  tooltip: '复制详细信息',
                  icon: const Icon(Icons.copy_outlined),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: value));
                    if (context.mounted) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(const SnackBar(content: Text('已复制详细信息')));
                    }
                  },
                ),
              ],
            ),
            SelectableText(
              display,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
            if (omitted)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('显示内容已省略；可复制已保留的完整诊断。'),
              ),
          ],
        ),
      ),
    );
  }
}

enum _ActivityStatus {
  sending,
  sendFailed,
  received,
  queued,
  processing,
  cancelling,
  interrupted,
  failed,
  expired,
  cancelled,
  succeeded,
}

class _AndroidSecretResolver implements SecretResolver {
  const _AndroidSecretResolver(this.delegate);

  final DesktopSecretResolver? delegate;

  @override
  Future<String?> resolve(String name) =>
      delegate?.resolve(name) ?? Future<String?>.value();
}
