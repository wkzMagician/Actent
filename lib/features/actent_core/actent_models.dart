import 'dart:collection';

const actentSchemaVersion = 2;

enum ActentContentType { none, text, url, image, file, json }

ActentContentType classifyAttachmentContentTypes(Iterable<String> mimeTypes) {
  final normalized = mimeTypes
      .map((mimeType) => mimeType.toLowerCase())
      .toList(growable: false);
  if (normalized.isNotEmpty &&
      normalized.every((mimeType) => mimeType.startsWith('image/'))) {
    return ActentContentType.image;
  }
  if (normalized.isNotEmpty &&
      normalized.every(
        (mimeType) =>
            mimeType == 'application/json' || mimeType.endsWith('+json'),
      )) {
    return ActentContentType.json;
  }
  return ActentContentType.file;
}

extension ActentContentTypeJson on ActentContentType {
  String get value => name;

  static ActentContentType parse(Object? value, String path) {
    if (value is! String) {
      throw ActentValidationException(path, 'must be a string');
    }
    return ActentContentType.values.firstWhere(
      (item) => item.value == value,
      orElse: () => throw ActentValidationException(
        path,
        'must be one of: ${ActentContentType.values.map((item) => item.value).join(', ')}',
      ),
    );
  }
}

enum WorkReceiptStatus {
  succeeded,
  failed,
  stored,
  processing,
  expired,
  cancelled,
  queued,
  cancelling,
  interrupted,
}

extension WorkReceiptStatusJson on WorkReceiptStatus {
  String get value => name;

  static WorkReceiptStatus parse(Object? value, String path) {
    if (value is! String) {
      throw ActentValidationException(path, 'must be a string');
    }
    return WorkReceiptStatus.values.firstWhere(
      (item) => item.value == value,
      orElse: () =>
          throw ActentValidationException(path, 'unknown receipt status'),
    );
  }
}

class ActentValidationException implements Exception {
  const ActentValidationException(this.path, this.message);

  final String path;
  final String message;

  @override
  String toString() => 'Invalid Actent document at $path: $message';
}

class ActentSource {
  const ActentSource({
    required this.kind,
    this.deviceId,
    this.appName,
    this.platform,
  });

  final String kind;
  final String? deviceId;
  final String? appName;
  final String? platform;

  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind,
    if (deviceId != null) 'deviceId': deviceId,
    if (appName != null) 'appName': appName,
    if (platform != null) 'platform': platform,
  };

  factory ActentSource.fromJson(Object? value) {
    final json = _map(value, 'source');
    _rejectUnknown(json, const {
      'kind',
      'deviceId',
      'appName',
      'platform',
    }, 'source');
    return ActentSource(
      kind: _string(json, 'kind', 'source.kind'),
      deviceId: _optionalString(json, 'deviceId', 'source.deviceId'),
      appName: _optionalString(json, 'appName', 'source.appName'),
      platform: _optionalString(json, 'platform', 'source.platform'),
    );
  }
}

class ActentContent {
  ActentContent({required this.type, Map<String, Object?> data = const {}})
    : data = UnmodifiableMapView(Map<String, Object?>.from(data));

  final ActentContentType type;
  final Map<String, Object?> data;

  Map<String, Object?> toJson() => <String, Object?>{
    'type': type.value,
    ...data,
  };

  factory ActentContent.fromJson(Object? value) {
    final json = _map(value, 'content');
    final type = ActentContentTypeJson.parse(json['type'], 'content.type');
    final data = Map<String, Object?>.from(json)..remove('type');
    return ActentContent(type: type, data: data);
  }
}

class ActentAttachment {
  const ActentAttachment({
    required this.id,
    required this.name,
    required this.mimeType,
    required this.byteLength,
    required this.handle,
  });

  final String id;
  final String name;
  final String mimeType;
  final int byteLength;
  final String handle;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'mimeType': mimeType,
    'byteLength': byteLength,
    'handle': handle,
  };

  factory ActentAttachment.fromJson(Object? value, int index) {
    final path = 'attachments[$index]';
    final json = _map(value, path);
    _rejectUnknown(json, const {
      'id',
      'name',
      'mimeType',
      'byteLength',
      'handle',
    }, path);
    final length = _integer(json, 'byteLength', '$path.byteLength');
    if (length < 0) {
      throw ActentValidationException(
        '$path.byteLength',
        'must not be negative',
      );
    }
    return ActentAttachment(
      id: _string(json, 'id', '$path.id'),
      name: _string(json, 'name', '$path.name'),
      mimeType: _string(json, 'mimeType', '$path.mimeType'),
      byteLength: length,
      handle: _string(json, 'handle', '$path.handle'),
    );
  }
}

/// The reusable value passed between Works. ActentMessage adds provenance and
/// activity metadata around this payload.
class ActentPayload {
  ActentPayload({
    required this.type,
    Map<String, Object?> data = const {},
    List<ActentAttachment> attachments = const [],
  }) : data = UnmodifiableMapView(Map<String, Object?>.from(data)),
       attachments = List.unmodifiable(attachments);

  final ActentContentType type;
  final Map<String, Object?> data;
  final List<ActentAttachment> attachments;

  ActentContent get content => ActentContent(type: type, data: data);

  Map<String, Object?> toJson() => <String, Object?>{
    'type': type.value,
    'data': data,
    'attachments': attachments.map((item) => item.toJson()).toList(),
  };

  factory ActentPayload.fromJson(Object? value) {
    final json = _map(value, 'payload');
    final rawAttachments = json['attachments'];
    if (rawAttachments is! List) {
      throw const ActentValidationException(
        'payload.attachments',
        'must be an array',
      );
    }
    return ActentPayload(
      type: ActentContentTypeJson.parse(json['type'], 'payload.type'),
      data: _map(json['data'], 'payload.data'),
      attachments: [
        for (var index = 0; index < rawAttachments.length; index++)
          ActentAttachment.fromJson(rawAttachments[index], index),
      ],
    );
  }

  factory ActentPayload.fromLegacy({
    required ActentContent content,
    required List<ActentAttachment> attachments,
  }) => ActentPayload(
    type: content.type,
    data: content.data,
    attachments: attachments,
  );
}

class ActentMessage {
  ActentMessage({
    required this.id,
    required this.traceId,
    required this.createdAt,
    required this.source,
    ActentContent? content,
    List<ActentAttachment> attachments = const [],
    ActentPayload? payload,
    Map<String, Object?> metadata = const {},
    this.schemaVersion = actentSchemaVersion,
  }) : payload =
           payload ??
           (content == null
               ? (throw ArgumentError('content or payload is required'))
               : ActentPayload.fromLegacy(
                   content: content,
                   attachments: attachments,
                 )),
       metadata = UnmodifiableMapView(Map<String, Object?>.from(metadata));

  final String id;
  final String traceId;
  final int schemaVersion;
  final DateTime createdAt;
  final ActentSource source;
  final ActentPayload payload;
  final Map<String, Object?> metadata;

  ActentContent get content => payload.content;

  List<ActentAttachment> get attachments => payload.attachments;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'traceId': traceId,
    'schemaVersion': schemaVersion,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'source': source.toJson(),
    'payload': payload.toJson(),
    'metadata': metadata,
  };

  factory ActentMessage.fromJson(Object? value) {
    final json = _map(value, 'message');
    _rejectUnknown(json, const {
      'id',
      'traceId',
      'schemaVersion',
      'createdAt',
      'source',
      'payload',
      'content',
      'attachments',
      'metadata',
    }, 'message');
    final schemaVersion = _integer(json, 'schemaVersion', 'schemaVersion');
    if (schemaVersion != 1 && schemaVersion != actentSchemaVersion) {
      throw ActentValidationException(
        'schemaVersion',
        'unsupported version $schemaVersion; expected $actentSchemaVersion',
      );
    }
    final metadata = _map(json['metadata'], 'metadata');
    final payload = json['payload'] == null
        ? ActentPayload.fromLegacy(
            content: ActentContent.fromJson(json['content']),
            attachments: _legacyAttachments(json['attachments']),
          )
        : ActentPayload.fromJson(json['payload']);
    return ActentMessage(
      id: _string(json, 'id', 'id'),
      traceId: _string(json, 'traceId', 'traceId'),
      schemaVersion: actentSchemaVersion,
      createdAt: _date(json, 'createdAt', 'createdAt'),
      source: ActentSource.fromJson(json['source']),
      payload: payload,
      metadata: metadata,
    );
  }
}

class Device {
  Device({
    required this.id,
    required this.displayName,
    required this.platform,
    required this.publicKey,
    Map<String, Object?> endpoint = const {},
    this.pairedAt,
    this.authorized = true,
  }) : endpoint = UnmodifiableMapView(Map<String, Object?>.from(endpoint));

  final String id;
  final String displayName;
  final String platform;
  final String publicKey;
  final Map<String, Object?> endpoint;
  final DateTime? pairedAt;
  final bool authorized;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'displayName': displayName,
    'platform': platform,
    'publicKey': publicKey,
    'endpoint': endpoint,
    if (pairedAt != null) 'pairedAt': pairedAt!.toUtc().toIso8601String(),
    'authorized': authorized,
  };

  factory Device.fromJson(Object? value) {
    final json = _map(value, 'device');
    return Device(
      id: _string(json, 'id', 'id'),
      displayName: _string(json, 'displayName', 'displayName'),
      platform: _string(json, 'platform', 'platform'),
      publicKey: _string(json, 'publicKey', 'publicKey'),
      endpoint: _map(json['endpoint'], 'endpoint'),
      pairedAt: json.containsKey('pairedAt')
          ? _date(json, 'pairedAt', 'pairedAt')
          : null,
      authorized: _boolean(json, 'authorized', 'authorized'),
    );
  }
}

class Work {
  Work({
    required this.id,
    required this.revision,
    required this.name,
    required this.ownerDeviceId,
    this.allowedSourceDeviceIds = const {},
    this.acceptedContentTypes = const {},
    this.outputType = ActentContentType.none,
    this.timeout = const Duration(hours: 24),
    this.queueLimit = 10,
    this.enabled = true,
    Map<String, Object?> platformBindings = const {},
    Map<String, Object?> catalogVisibility = const {},
  }) : platformBindings = UnmodifiableMapView(
         Map<String, Object?>.from(platformBindings),
       ),
       catalogVisibility = UnmodifiableMapView(
         Map<String, Object?>.from(catalogVisibility),
       );

  final String id;
  final int revision;
  final String name;
  final String ownerDeviceId;
  final Set<String> allowedSourceDeviceIds;
  final Set<ActentContentType> acceptedContentTypes;
  final ActentContentType outputType;
  final Duration timeout;
  final int queueLimit;
  final bool enabled;
  final Map<String, Object?> platformBindings;
  final Map<String, Object?> catalogVisibility;

  factory Work.nullWork({
    required String id,
    required String ownerDeviceId,
    String name = 'Null',
    int revision = 1,
  }) => Work(
    id: id,
    revision: revision,
    name: name,
    ownerDeviceId: ownerDeviceId,
    acceptedContentTypes: ActentContentType.values.toSet(),
    outputType: ActentContentType.none,
    platformBindings: const {'kind': 'null'},
  );

  bool accepts(ActentMessage message) =>
      enabled && acceptedContentTypes.contains(message.content.type);

  bool isAuthorized(String? sourceDeviceId) =>
      allowedSourceDeviceIds.isEmpty ||
      (sourceDeviceId != null &&
          allowedSourceDeviceIds.contains(sourceDeviceId));

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'revision': revision,
    'name': name,
    'ownerDeviceId': ownerDeviceId,
    'allowedSourceDeviceIds': allowedSourceDeviceIds.toList()..sort(),
    'acceptedContentTypes':
        acceptedContentTypes.map((item) => item.value).toList()..sort(),
    'outputType': outputType.value,
    'timeoutSeconds': timeout.inSeconds,
    'queueLimit': queueLimit,
    'enabled': enabled,
    'platformBindings': platformBindings,
    'catalogVisibility': catalogVisibility,
  };

  /// The definition needed by a peer to display and route a task.
  ///
  /// Execution bindings remain on the owning device. A peer only needs the
  /// stable identity, display metadata and compatibility information.
  Map<String, Object?> toCatalogJson() => <String, Object?>{
    'id': id,
    'revision': revision,
    'name': name,
    'ownerDeviceId': ownerDeviceId,
    'allowedSourceDeviceIds': allowedSourceDeviceIds.toList(),
    'acceptedContentTypes': acceptedContentTypes
        .map((value) => value.value)
        .toList(),
    'outputType': outputType.value,
    'timeoutSeconds': timeout.inSeconds,
    'queueLimit': queueLimit,
    'enabled': enabled,
    'catalogVisibility': catalogVisibility,
    'catalogOnly': true,
  };

  factory Work.fromJson(Object? value) {
    final json = _map(value, 'work');
    final allowed = _stringList(
      json['allowedSourceDeviceIds'],
      'allowedSourceDeviceIds',
    );
    final accepted = json['acceptedContentTypes'];
    if (accepted is! List) {
      throw const ActentValidationException(
        'acceptedContentTypes',
        'must be an array',
      );
    }
    final timeoutSeconds = _integer(json, 'timeoutSeconds', 'timeoutSeconds');
    final queueLimit = _integer(json, 'queueLimit', 'queueLimit');
    if (timeoutSeconds <= 0 || queueLimit <= 0) {
      throw const ActentValidationException(
        'work',
        'timeout and queueLimit must be positive',
      );
    }
    final rawBinding = json['platformBindings'];
    final outputType = json['outputType'] == null
        ? _legacyOutputType(rawBinding)
        : ActentContentTypeJson.parse(json['outputType'], 'outputType');
    return Work(
      id: _string(json, 'id', 'id'),
      revision: _integer(json, 'revision', 'revision'),
      name: _string(json, 'name', 'name'),
      ownerDeviceId: _string(json, 'ownerDeviceId', 'ownerDeviceId'),
      allowedSourceDeviceIds: allowed.toSet(),
      acceptedContentTypes: {
        for (var index = 0; index < accepted.length; index++)
          ActentContentTypeJson.parse(
            accepted[index],
            'acceptedContentTypes[$index]',
          ),
      },
      outputType: outputType,
      timeout: Duration(seconds: timeoutSeconds),
      queueLimit: queueLimit,
      enabled: _boolean(json, 'enabled', 'enabled'),
      platformBindings: json['catalogOnly'] == true
          ? const {}
          : _map(json['platformBindings'], 'platformBindings'),
      catalogVisibility: _map(json['catalogVisibility'], 'catalogVisibility'),
    );
  }
}

class WorkflowStep {
  const WorkflowStep({
    required this.id,
    required this.workId,
    required this.workRevision,
    required this.deviceId,
  });

  final String id;
  final String workId;
  final int workRevision;
  final String deviceId;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'workId': workId,
    'workRevision': workRevision,
    'deviceId': deviceId,
  };

  factory WorkflowStep.fromJson(Object? value) {
    final json = _map(value, 'workflow.step');
    return WorkflowStep(
      id: _string(json, 'id', 'workflow.step.id'),
      workId: _string(json, 'workId', 'workflow.step.workId'),
      workRevision: _integer(
        json,
        'workRevision',
        'workflow.step.workRevision',
      ),
      deviceId: _string(json, 'deviceId', 'workflow.step.deviceId'),
    );
  }
}

class Workflow {
  Workflow({
    required this.id,
    required this.revision,
    required this.name,
    required this.ownerDeviceId,
    required this.steps,
    this.acceptedContentTypes = const {},
    this.enabled = true,
  });

  final String id;
  final int revision;
  final String name;
  final String ownerDeviceId;
  final List<WorkflowStep> steps;
  final Set<ActentContentType> acceptedContentTypes;
  final bool enabled;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'revision': revision,
    'name': name,
    'ownerDeviceId': ownerDeviceId,
    'acceptedContentTypes': acceptedContentTypes
        .map((item) => item.value)
        .toList(),
    'enabled': enabled,
    'steps': steps.map((step) => step.toJson()).toList(),
  };

  factory Workflow.fromJson(Object? value) {
    final json = _map(value, 'workflow');
    final rawTypes = json['acceptedContentTypes'];
    final rawSteps = json['steps'];
    if (rawTypes is! List || rawSteps is! List || rawSteps.isEmpty) {
      throw const ActentValidationException(
        'workflow',
        'acceptedContentTypes and steps must be non-empty arrays',
      );
    }
    return Workflow(
      id: _string(json, 'id', 'workflow.id'),
      revision: _integer(json, 'revision', 'workflow.revision'),
      name: _string(json, 'name', 'workflow.name'),
      ownerDeviceId: _string(json, 'ownerDeviceId', 'workflow.ownerDeviceId'),
      acceptedContentTypes: {
        for (var index = 0; index < rawTypes.length; index++)
          ActentContentTypeJson.parse(
            rawTypes[index],
            'workflow.acceptedContentTypes[$index]',
          ),
      },
      enabled: _boolean(json, 'enabled', 'workflow.enabled'),
      steps: rawSteps.map(WorkflowStep.fromJson).toList(growable: false),
    );
  }
}

enum WorkflowExecutionStatus {
  queued,
  running,
  succeeded,
  failed,
  cancelled,
  invalid,
}

extension WorkflowExecutionStatusJson on WorkflowExecutionStatus {
  String get value => name;

  static WorkflowExecutionStatus parse(Object? value, String path) {
    if (value is! String) {
      throw ActentValidationException(path, 'must be a string');
    }
    return WorkflowExecutionStatus.values.firstWhere(
      (item) => item.value == value,
      orElse: () =>
          throw ActentValidationException(path, 'unknown workflow status'),
    );
  }
}

/// Durable coordination state for one linear Workflow execution.
///
/// The output is retained for continuation, but it is deliberately optional
/// in the activity view: a remote final executor may keep the actual payload
/// while the owner receives only status and error metadata.
class WorkflowExecution {
  WorkflowExecution({
    required this.id,
    required this.workflowId,
    required this.workflowRevision,
    required this.sourceDeviceId,
    required this.createdAt,
    required this.status,
    this.currentStepIndex = 0,
    this.updatedAt,
    this.error,
    this.output,
  });

  final String id;
  final String workflowId;
  final int workflowRevision;
  final String sourceDeviceId;
  final DateTime createdAt;
  final WorkflowExecutionStatus status;
  final int currentStepIndex;
  final DateTime? updatedAt;
  final WorkError? error;
  final ActentPayload? output;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'workflowId': workflowId,
    'workflowRevision': workflowRevision,
    'sourceDeviceId': sourceDeviceId,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'status': status.value,
    'currentStepIndex': currentStepIndex,
    if (updatedAt != null) 'updatedAt': updatedAt!.toUtc().toIso8601String(),
    if (error != null) 'error': error!.toJson(),
    if (output != null) 'output': output!.toJson(),
  };

  factory WorkflowExecution.fromJson(Object? value) {
    final json = _map(value, 'workflowExecution');
    return WorkflowExecution(
      id: _string(json, 'id', 'workflowExecution.id'),
      workflowId: _string(json, 'workflowId', 'workflowExecution.workflowId'),
      workflowRevision: _integer(
        json,
        'workflowRevision',
        'workflowExecution.workflowRevision',
      ),
      sourceDeviceId: _string(
        json,
        'sourceDeviceId',
        'workflowExecution.sourceDeviceId',
      ),
      createdAt: _date(json, 'createdAt', 'workflowExecution.createdAt'),
      status: WorkflowExecutionStatusJson.parse(
        json['status'],
        'workflowExecution.status',
      ),
      currentStepIndex: _integer(
        json,
        'currentStepIndex',
        'workflowExecution.currentStepIndex',
      ),
      updatedAt: json['updatedAt'] == null
          ? null
          : _date(json, 'updatedAt', 'workflowExecution.updatedAt'),
      error: json['error'] == null ? null : WorkError.fromJson(json['error']),
      output: json['output'] == null
          ? null
          : ActentPayload.fromJson(json['output']),
    );
  }
}

class WorkRequest {
  WorkRequest({
    required this.requestId,
    required this.message,
    required this.workId,
    required this.workRevision,
    required this.sourceDeviceId,
    required this.targetDeviceId,
    required this.createdAt,
    required this.expiresAt,
    this.workflowExecutionId,
    this.workflowStepId,
    this.workflowOwnerDeviceId,
  });

  final String requestId;
  final ActentMessage message;
  final String workId;
  final int workRevision;
  final String sourceDeviceId;
  final String targetDeviceId;
  final DateTime createdAt;
  final DateTime expiresAt;
  final String? workflowExecutionId;
  final String? workflowStepId;
  final String? workflowOwnerDeviceId;

  bool get isExpired => !expiresAt.isAfter(DateTime.now().toUtc());

  Map<String, Object?> toJson() => <String, Object?>{
    'requestId': requestId,
    'message': message.toJson(),
    'workId': workId,
    'workRevision': workRevision,
    'sourceDeviceId': sourceDeviceId,
    'targetDeviceId': targetDeviceId,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'expiresAt': expiresAt.toUtc().toIso8601String(),
    if (workflowExecutionId != null) 'workflowExecutionId': workflowExecutionId,
    if (workflowStepId != null) 'workflowStepId': workflowStepId,
    if (workflowOwnerDeviceId != null)
      'workflowOwnerDeviceId': workflowOwnerDeviceId,
  };

  factory WorkRequest.fromJson(Object? value) {
    final json = _map(value, 'request');
    return WorkRequest(
      requestId: _string(json, 'requestId', 'requestId'),
      message: ActentMessage.fromJson(json['message']),
      workId: _string(json, 'workId', 'workId'),
      workRevision: _integer(json, 'workRevision', 'workRevision'),
      sourceDeviceId: _string(json, 'sourceDeviceId', 'sourceDeviceId'),
      targetDeviceId: _string(json, 'targetDeviceId', 'targetDeviceId'),
      createdAt: _date(json, 'createdAt', 'createdAt'),
      expiresAt: _date(json, 'expiresAt', 'expiresAt'),
      workflowExecutionId: _optionalString(
        json,
        'workflowExecutionId',
        'workflowExecutionId',
      ),
      workflowStepId: _optionalString(json, 'workflowStepId', 'workflowStepId'),
      workflowOwnerDeviceId: _optionalString(
        json,
        'workflowOwnerDeviceId',
        'workflowOwnerDeviceId',
      ),
    );
  }
}

class WorkReceipt {
  const WorkReceipt({
    required this.requestId,
    required this.workId,
    required this.status,
    required this.createdAt,
    this.sequence = 1,
    this.completedAt,
    this.errorCode,
    this.error,
    this.summary,
    this.diagnostics,
    this.output,
  });

  final String requestId;
  final String workId;
  final WorkReceiptStatus status;
  final DateTime createdAt;
  final int sequence;
  final DateTime? completedAt;
  final String? errorCode;
  final WorkError? error;
  final String? summary;
  final WorkExecutionDiagnostics? diagnostics;
  final ActentPayload? output;

  Map<String, Object?> toJson() => <String, Object?>{
    'requestId': requestId,
    'workId': workId,
    'status': status.value,
    'sequence': sequence,
    'createdAt': createdAt.toUtc().toIso8601String(),
    if (completedAt != null)
      'completedAt': completedAt!.toUtc().toIso8601String(),
    if (errorCode != null) 'errorCode': errorCode,
    if (error != null) 'error': error!.toJson(),
    if (summary != null) 'summary': summary,
    if (diagnostics != null) 'diagnostics': diagnostics!.toJson(),
    if (output != null) 'output': output!.toJson(),
  };

  /// The receipt representation sent to a peer deliberately excludes raw
  /// process output. A script's local diagnostics can contain paths or other
  /// private machine details and remain on the executing device.
  Map<String, Object?> toRemoteJson({int maxSummaryCharacters = 4096}) =>
      <String, Object?>{
        ...toJson(),
        if (summary != null)
          'summary': _limitText(summary!, maxSummaryCharacters),
      }..remove('diagnostics');

  factory WorkReceipt.fromJson(Object? value) {
    final json = _map(value, 'receipt');
    return WorkReceipt(
      requestId: _string(json, 'requestId', 'requestId'),
      workId: _string(json, 'workId', 'workId'),
      status: WorkReceiptStatusJson.parse(json['status'], 'status'),
      createdAt: _date(json, 'createdAt', 'createdAt'),
      sequence: json['sequence'] is int ? json['sequence'] as int : 1,
      completedAt: json.containsKey('completedAt')
          ? _date(json, 'completedAt', 'completedAt')
          : null,
      errorCode: _optionalString(json, 'errorCode', 'errorCode'),
      error: json['error'] == null ? null : WorkError.fromJson(json['error']),
      summary: _optionalString(json, 'summary', 'summary'),
      diagnostics: json['diagnostics'] == null
          ? null
          : WorkExecutionDiagnostics.fromJson(json['diagnostics']),
      output: json['output'] == null
          ? null
          : ActentPayload.fromJson(json['output']),
    );
  }
}

/// Bounded local process information for an executed Work. It is stored with
/// the receipt, while network receipts intentionally omit it.
class WorkExecutionDiagnostics {
  const WorkExecutionDiagnostics({
    required this.stage,
    this.startedAt,
    this.completedAt,
    this.exitCode,
    this.stdout,
    this.stderr,
    this.stdoutTruncated = false,
    this.stderrTruncated = false,
  });

  final String stage;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final int? exitCode;
  final String? stdout;
  final String? stderr;
  final bool stdoutTruncated;
  final bool stderrTruncated;

  Duration? get duration => startedAt == null || completedAt == null
      ? null
      : completedAt!.difference(startedAt!);

  Map<String, Object?> toJson() => <String, Object?>{
    'stage': stage,
    if (startedAt != null) 'startedAt': startedAt!.toUtc().toIso8601String(),
    if (completedAt != null)
      'completedAt': completedAt!.toUtc().toIso8601String(),
    if (exitCode != null) 'exitCode': exitCode,
    if (stdout != null) 'stdout': stdout,
    if (stderr != null) 'stderr': stderr,
    if (stdoutTruncated) 'stdoutTruncated': true,
    if (stderrTruncated) 'stderrTruncated': true,
  };

  factory WorkExecutionDiagnostics.fromJson(Object? value) {
    final json = _map(value, 'diagnostics');
    return WorkExecutionDiagnostics(
      stage: _string(json, 'stage', 'diagnostics.stage'),
      startedAt: json['startedAt'] == null
          ? null
          : _date(json, 'startedAt', 'diagnostics.startedAt'),
      completedAt: json['completedAt'] == null
          ? null
          : _date(json, 'completedAt', 'diagnostics.completedAt'),
      exitCode: json['exitCode'] is int ? json['exitCode'] as int : null,
      stdout: _optionalString(json, 'stdout', 'diagnostics.stdout'),
      stderr: _optionalString(json, 'stderr', 'diagnostics.stderr'),
      stdoutTruncated: json['stdoutTruncated'] == true,
      stderrTruncated: json['stderrTruncated'] == true,
    );
  }
}

String _limitText(String value, int maximum) => value.length <= maximum
    ? value
    : '${value.substring(0, maximum)}\n[truncated]';

class WorkError {
  const WorkError({required this.code, this.message, this.details});

  final String code;
  final String? message;
  final Map<String, Object?>? details;

  Map<String, Object?> toJson() => <String, Object?>{
    'code': code,
    if (message != null) 'message': message,
    if (details != null) 'details': details,
  };

  factory WorkError.fromJson(Object? value) {
    final json = _map(value, 'error');
    return WorkError(
      code: _string(json, 'code', 'error.code'),
      message: _optionalString(json, 'message', 'error.message'),
      details: json['details'] == null
          ? null
          : _map(json['details'], 'error.details'),
    );
  }
}

List<ActentAttachment> _legacyAttachments(Object? value) {
  if (value is! List) {
    throw const ActentValidationException('attachments', 'must be an array');
  }
  return [
    for (var index = 0; index < value.length; index++)
      ActentAttachment.fromJson(value[index], index),
  ];
}

ActentContentType _legacyOutputType(Object? value) {
  if (value is! Map) return ActentContentType.none;
  final kind = value['kind'];
  return switch (kind) {
    'desktop-script' ||
    'desktop-shell' ||
    'desktop-file' ||
    'web-js' ||
    'http' ||
    'android-http' => ActentContentType.text,
    _ => ActentContentType.none,
  };
}

Map<String, Object?> _map(Object? value, String path) {
  if (value is! Map) {
    throw ActentValidationException(path, 'must be an object');
  }
  try {
    return Map<String, Object?>.from(value);
  } on TypeError {
    throw ActentValidationException(path, 'must have string keys');
  }
}

String _string(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw ActentValidationException(path, 'must be a non-empty string');
  }
  return value;
}

String? _optionalString(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String) {
    throw ActentValidationException(path, 'must be a string');
  }
  return value;
}

int _integer(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value is! int) {
    throw ActentValidationException(path, 'must be an integer');
  }
  return value;
}

bool _boolean(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value is! bool) {
    throw ActentValidationException(path, 'must be a boolean');
  }
  return value;
}

void _rejectUnknown(
  Map<String, Object?> json,
  Set<String> allowed,
  String path,
) {
  final unknown = json.keys.where((key) => !allowed.contains(key)).toList()
    ..sort();
  if (unknown.isNotEmpty) {
    throw ActentValidationException(
      path,
      'contains unknown fields: ${unknown.join(', ')}',
    );
  }
}

DateTime _date(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value is! String) {
    throw ActentValidationException(path, 'must be an ISO-8601 string');
  }
  final date = DateTime.tryParse(value);
  if (date == null) {
    throw ActentValidationException(path, 'must be an ISO-8601 string');
  }
  return date.toUtc();
}

List<String> _stringList(Object? value, String path) {
  if (value is! List || value.any((item) => item is! String || item.isEmpty)) {
    throw ActentValidationException(
      path,
      'must be an array of non-empty strings',
    );
  }
  return List<String>.from(value);
}
