import 'dart:collection';

const pigeonSchemaVersion = 1;

enum PigeonContentType { text, url, image, file, json }

extension PigeonContentTypeJson on PigeonContentType {
  String get value => name;

  static PigeonContentType parse(Object? value, String path) {
    if (value is! String) {
      throw PigeonValidationException(path, 'must be a string');
    }
    return PigeonContentType.values.firstWhere(
      (item) => item.value == value,
      orElse: () => throw PigeonValidationException(
        path,
        'must be one of: ${PigeonContentType.values.map((item) => item.value).join(', ')}',
      ),
    );
  }
}

enum WorkReceiptStatus { succeeded, failed, stored, expired, cancelled }

extension WorkReceiptStatusJson on WorkReceiptStatus {
  String get value => name;

  static WorkReceiptStatus parse(Object? value, String path) {
    if (value is! String) {
      throw PigeonValidationException(path, 'must be a string');
    }
    return WorkReceiptStatus.values.firstWhere(
      (item) => item.value == value,
      orElse: () =>
          throw PigeonValidationException(path, 'unknown receipt status'),
    );
  }
}

class PigeonValidationException implements Exception {
  const PigeonValidationException(this.path, this.message);

  final String path;
  final String message;

  @override
  String toString() => 'Invalid Pigeon document at $path: $message';
}

class PigeonSource {
  const PigeonSource({
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

  factory PigeonSource.fromJson(Object? value) {
    final json = _map(value, 'source');
    _rejectUnknown(json, const {
      'kind',
      'deviceId',
      'appName',
      'platform',
    }, 'source');
    return PigeonSource(
      kind: _string(json, 'kind', 'source.kind'),
      deviceId: _optionalString(json, 'deviceId', 'source.deviceId'),
      appName: _optionalString(json, 'appName', 'source.appName'),
      platform: _optionalString(json, 'platform', 'source.platform'),
    );
  }
}

class PigeonContent {
  PigeonContent({required this.type, Map<String, Object?> data = const {}})
    : data = UnmodifiableMapView(Map<String, Object?>.from(data));

  final PigeonContentType type;
  final Map<String, Object?> data;

  Map<String, Object?> toJson() => <String, Object?>{
    'type': type.value,
    ...data,
  };

  factory PigeonContent.fromJson(Object? value) {
    final json = _map(value, 'content');
    final type = PigeonContentTypeJson.parse(json['type'], 'content.type');
    final data = Map<String, Object?>.from(json)..remove('type');
    return PigeonContent(type: type, data: data);
  }
}

class PigeonAttachment {
  const PigeonAttachment({
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

  factory PigeonAttachment.fromJson(Object? value, int index) {
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
      throw PigeonValidationException(
        '$path.byteLength',
        'must not be negative',
      );
    }
    return PigeonAttachment(
      id: _string(json, 'id', '$path.id'),
      name: _string(json, 'name', '$path.name'),
      mimeType: _string(json, 'mimeType', '$path.mimeType'),
      byteLength: length,
      handle: _string(json, 'handle', '$path.handle'),
    );
  }
}

class PigeonMessage {
  PigeonMessage({
    required this.id,
    required this.traceId,
    required this.createdAt,
    required this.source,
    required this.content,
    this.attachments = const [],
    Map<String, Object?> metadata = const {},
    this.schemaVersion = pigeonSchemaVersion,
  }) : metadata = UnmodifiableMapView(Map<String, Object?>.from(metadata));

  final String id;
  final String traceId;
  final int schemaVersion;
  final DateTime createdAt;
  final PigeonSource source;
  final PigeonContent content;
  final List<PigeonAttachment> attachments;
  final Map<String, Object?> metadata;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'traceId': traceId,
    'schemaVersion': schemaVersion,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'source': source.toJson(),
    'content': content.toJson(),
    'attachments': attachments.map((item) => item.toJson()).toList(),
    'metadata': metadata,
  };

  factory PigeonMessage.fromJson(Object? value) {
    final json = _map(value, 'message');
    _rejectUnknown(json, const {
      'id',
      'traceId',
      'schemaVersion',
      'createdAt',
      'source',
      'content',
      'attachments',
      'metadata',
    }, 'message');
    final schemaVersion = _integer(json, 'schemaVersion', 'schemaVersion');
    if (schemaVersion != pigeonSchemaVersion) {
      throw PigeonValidationException(
        'schemaVersion',
        'unsupported version $schemaVersion; expected $pigeonSchemaVersion',
      );
    }
    final attachmentsValue = json['attachments'];
    if (attachmentsValue is! List) {
      throw const PigeonValidationException('attachments', 'must be an array');
    }
    final metadata = _map(json['metadata'], 'metadata');
    return PigeonMessage(
      id: _string(json, 'id', 'id'),
      traceId: _string(json, 'traceId', 'traceId'),
      schemaVersion: schemaVersion,
      createdAt: _date(json, 'createdAt', 'createdAt'),
      source: PigeonSource.fromJson(json['source']),
      content: PigeonContent.fromJson(json['content']),
      attachments: [
        for (var index = 0; index < attachmentsValue.length; index++)
          PigeonAttachment.fromJson(attachmentsValue[index], index),
      ],
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
  final Set<PigeonContentType> acceptedContentTypes;
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
    acceptedContentTypes: PigeonContentType.values.toSet(),
    platformBindings: const {'kind': 'null'},
  );

  bool accepts(PigeonMessage message) =>
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
    'timeoutSeconds': timeout.inSeconds,
    'queueLimit': queueLimit,
    'enabled': enabled,
    'platformBindings': platformBindings,
    'catalogVisibility': catalogVisibility,
  };

  factory Work.fromJson(Object? value) {
    final json = _map(value, 'work');
    final allowed = _stringList(
      json['allowedSourceDeviceIds'],
      'allowedSourceDeviceIds',
    );
    final accepted = json['acceptedContentTypes'];
    if (accepted is! List) {
      throw const PigeonValidationException(
        'acceptedContentTypes',
        'must be an array',
      );
    }
    final timeoutSeconds = _integer(json, 'timeoutSeconds', 'timeoutSeconds');
    final queueLimit = _integer(json, 'queueLimit', 'queueLimit');
    if (timeoutSeconds <= 0 || queueLimit <= 0) {
      throw const PigeonValidationException(
        'work',
        'timeout and queueLimit must be positive',
      );
    }
    return Work(
      id: _string(json, 'id', 'id'),
      revision: _integer(json, 'revision', 'revision'),
      name: _string(json, 'name', 'name'),
      ownerDeviceId: _string(json, 'ownerDeviceId', 'ownerDeviceId'),
      allowedSourceDeviceIds: allowed.toSet(),
      acceptedContentTypes: {
        for (var index = 0; index < accepted.length; index++)
          PigeonContentTypeJson.parse(
            accepted[index],
            'acceptedContentTypes[$index]',
          ),
      },
      timeout: Duration(seconds: timeoutSeconds),
      queueLimit: queueLimit,
      enabled: _boolean(json, 'enabled', 'enabled'),
      platformBindings: _map(json['platformBindings'], 'platformBindings'),
      catalogVisibility: _map(json['catalogVisibility'], 'catalogVisibility'),
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
  });

  final String requestId;
  final PigeonMessage message;
  final String workId;
  final int workRevision;
  final String sourceDeviceId;
  final String targetDeviceId;
  final DateTime createdAt;
  final DateTime expiresAt;

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
  };

  factory WorkRequest.fromJson(Object? value) {
    final json = _map(value, 'request');
    return WorkRequest(
      requestId: _string(json, 'requestId', 'requestId'),
      message: PigeonMessage.fromJson(json['message']),
      workId: _string(json, 'workId', 'workId'),
      workRevision: _integer(json, 'workRevision', 'workRevision'),
      sourceDeviceId: _string(json, 'sourceDeviceId', 'sourceDeviceId'),
      targetDeviceId: _string(json, 'targetDeviceId', 'targetDeviceId'),
      createdAt: _date(json, 'createdAt', 'createdAt'),
      expiresAt: _date(json, 'expiresAt', 'expiresAt'),
    );
  }
}

class WorkReceipt {
  const WorkReceipt({
    required this.requestId,
    required this.workId,
    required this.status,
    required this.createdAt,
    this.completedAt,
    this.errorCode,
    this.summary,
  });

  final String requestId;
  final String workId;
  final WorkReceiptStatus status;
  final DateTime createdAt;
  final DateTime? completedAt;
  final String? errorCode;
  final String? summary;

  Map<String, Object?> toJson() => <String, Object?>{
    'requestId': requestId,
    'workId': workId,
    'status': status.value,
    'createdAt': createdAt.toUtc().toIso8601String(),
    if (completedAt != null)
      'completedAt': completedAt!.toUtc().toIso8601String(),
    if (errorCode != null) 'errorCode': errorCode,
    if (summary != null) 'summary': summary,
  };

  factory WorkReceipt.fromJson(Object? value) {
    final json = _map(value, 'receipt');
    return WorkReceipt(
      requestId: _string(json, 'requestId', 'requestId'),
      workId: _string(json, 'workId', 'workId'),
      status: WorkReceiptStatusJson.parse(json['status'], 'status'),
      createdAt: _date(json, 'createdAt', 'createdAt'),
      completedAt: json.containsKey('completedAt')
          ? _date(json, 'completedAt', 'completedAt')
          : null,
      errorCode: _optionalString(json, 'errorCode', 'errorCode'),
      summary: _optionalString(json, 'summary', 'summary'),
    );
  }
}

Map<String, Object?> _map(Object? value, String path) {
  if (value is! Map) {
    throw PigeonValidationException(path, 'must be an object');
  }
  try {
    return Map<String, Object?>.from(value);
  } on TypeError {
    throw PigeonValidationException(path, 'must have string keys');
  }
}

String _string(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw PigeonValidationException(path, 'must be a non-empty string');
  }
  return value;
}

String? _optionalString(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String) {
    throw PigeonValidationException(path, 'must be a string');
  }
  return value;
}

int _integer(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value is! int) {
    throw PigeonValidationException(path, 'must be an integer');
  }
  return value;
}

bool _boolean(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value is! bool) {
    throw PigeonValidationException(path, 'must be a boolean');
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
    throw PigeonValidationException(
      path,
      'contains unknown fields: ${unknown.join(', ')}',
    );
  }
}

DateTime _date(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value is! String) {
    throw PigeonValidationException(path, 'must be an ISO-8601 string');
  }
  final date = DateTime.tryParse(value);
  if (date == null) {
    throw PigeonValidationException(path, 'must be an ISO-8601 string');
  }
  return date.toUtc();
}

List<String> _stringList(Object? value, String path) {
  if (value is! List || value.any((item) => item is! String || item.isEmpty)) {
    throw PigeonValidationException(
      path,
      'must be an array of non-empty strings',
    );
  }
  return List<String>.from(value);
}
