import 'package:http/http.dart' as http;

import '../../actent_core/actent_models.dart';
import '../work_runner.dart';
import '../work_output.dart';

enum AndroidAttachmentPlacement { none, stream, streams }

class AndroidIntentSpec {
  const AndroidIntentSpec({
    required this.action,
    this.dataUriTemplate,
    this.mimeType,
    this.categories = const [],
    this.extras = const {},
    this.packageName,
    this.componentName,
    this.chooser = false,
    this.attachmentPlacement = AndroidAttachmentPlacement.none,
  });

  final String action;
  final String? dataUriTemplate;
  final String? mimeType;
  final List<String> categories;
  final Map<String, AndroidExtra> extras;
  final String? packageName;
  final String? componentName;
  final bool chooser;
  final AndroidAttachmentPlacement attachmentPlacement;
}

class AndroidExtra {
  const AndroidExtra._(this.value);

  const AndroidExtra.text(String value) : this._(value);
  const AndroidExtra.number(num value) : this._(value);
  const AndroidExtra.boolean(bool value) : this._(value);
  const AndroidExtra.stringList(List<String> value) : this._(value);
  const AndroidExtra.template(String value) : this._(value);
  AndroidExtra.attachmentUri(int index) : this._(_AttachmentIndex(index));

  final Object value;
}

class _AttachmentIndex {
  const _AttachmentIndex(this.index);

  final int index;
}

class AndroidIntentRequest {
  const AndroidIntentRequest({
    required this.action,
    required this.dataUri,
    required this.mimeType,
    required this.categories,
    required this.extras,
    required this.chooser,
    required this.grantReadPermission,
    this.packageName,
    this.componentName,
  });

  final String action;
  final String? dataUri;
  final String? mimeType;
  final List<String> categories;
  final Map<String, Object?> extras;
  final bool chooser;
  final bool grantReadPermission;
  final String? packageName;
  final String? componentName;
}

abstract interface class AndroidContentUriProvider {
  Future<String> uriFor(ActentAttachment attachment);
}

class AndroidIntentMapper {
  AndroidIntentMapper(this.uriProvider);

  final AndroidContentUriProvider uriProvider;

  Future<AndroidIntentRequest> map(
    ActentMessage message,
    AndroidIntentSpec spec,
  ) async {
    final uris = <String>[];
    for (final attachment in message.attachments) {
      uris.add(await uriProvider.uriFor(attachment));
    }
    final values = <String, Object?>{
      'message.id': message.id,
      'message.traceId': message.traceId,
      'content.type': message.content.type.value,
      'content.text': message.content.data['text'] ?? '',
      'content.url': message.content.data['url'] ?? '',
    };
    final extras = <String, Object?>{};
    for (final entry in spec.extras.entries) {
      extras[entry.key] = await _resolveExtra(entry.value, values, uris);
    }
    if ((spec.action == 'android.intent.action.SEND' ||
            spec.action == 'android.intent.action.SEND_MULTIPLE') &&
        !extras.containsKey('android.intent.extra.TEXT')) {
      final text = message.content.data['text'] ?? message.content.data['url'];
      if (text != null) extras['android.intent.extra.TEXT'] = '$text';
    }
    if (spec.attachmentPlacement == AndroidAttachmentPlacement.stream &&
        uris.length == 1) {
      extras['android.intent.extra.STREAM'] = uris.single;
    } else if (spec.attachmentPlacement == AndroidAttachmentPlacement.streams &&
        uris.isNotEmpty) {
      extras['android.intent.extra.STREAM'] = uris;
    } else if (spec.attachmentPlacement != AndroidAttachmentPlacement.none &&
        uris.isNotEmpty) {
      throw const AndroidWorkException(
        'attachment placement does not match attachment count',
      );
    }
    return AndroidIntentRequest(
      action: spec.action == 'android.intent.action.SEND' && uris.length > 1
          ? 'android.intent.action.SEND_MULTIPLE'
          : spec.action,
      dataUri: spec.dataUriTemplate == null
          ? null
          : SafeWorkTemplate.expand(spec.dataUriTemplate!, values),
      mimeType:
          spec.mimeType ??
          (message.attachments.length == 1 ? 'application/octet-stream' : null),
      categories: List.unmodifiable(spec.categories),
      extras: Map.unmodifiable(extras),
      packageName: spec.packageName,
      componentName: spec.componentName,
      chooser: spec.chooser,
      grantReadPermission: uris.isNotEmpty,
    );
  }

  Future<Object?> _resolveExtra(
    AndroidExtra extra,
    Map<String, Object?> values,
    List<String> uris,
  ) async {
    final value = extra.value;
    if (value is _AttachmentIndex) {
      if (value.index < 0 || value.index >= uris.length) {
        throw const AndroidWorkException(
          'attachment extra index is out of range',
        );
      }
      return uris[value.index];
    }
    if (value is String && value.contains('{{')) {
      return SafeWorkTemplate.expand(value, values);
    }
    return value;
  }
}

class SafeWorkTemplate {
  static String expand(String template, Map<String, Object?> values) {
    final expression = RegExp(r'\{\{([a-zA-Z0-9_.-]+)\}\}');
    return template.replaceAllMapped(expression, (match) {
      final name = match.group(1)!;
      if (!values.containsKey(name)) {
        throw AndroidWorkException('unknown template placeholder: $name');
      }
      return '${values[name]}';
    });
  }
}

abstract interface class AndroidIntentLauncher {
  Future<void> launch(AndroidIntentRequest request);
}

class AndroidIntentRunner implements WorkRunner {
  AndroidIntentRunner({
    required this.spec,
    required AndroidContentUriProvider uriProvider,
    required this.launcher,
  }) : _mapper = AndroidIntentMapper(uriProvider);

  final AndroidIntentSpec spec;
  final AndroidIntentLauncher launcher;
  final AndroidIntentMapper _mapper;

  @override
  String get id => 'android-intent';

  @override
  Future<WorkRunResult> run(
    Work work,
    ActentMessage message, {
    required String requestId,
    required CancellationToken cancellation,
  }) async {
    if (cancellation.isCancelled) {
      return const WorkRunResult.failure(errorCode: 'cancelled');
    }
    try {
      final intent = await _mapper.map(message, spec);
      await launcher.launch(intent);
      return const WorkRunResult.success(summary: 'launch_attempted');
    } on AndroidWorkException catch (error) {
      return WorkRunResult.failure(
        errorCode: error.code,
        summary: error.message,
      );
    } catch (error) {
      return WorkRunResult.failure(
        errorCode: 'launch_failed',
        summary: error.toString(),
      );
    }
  }
}

class AndroidHttpSpec {
  const AndroidHttpSpec({
    required this.urlTemplate,
    this.method = 'POST',
    this.headers = const {},
    this.bodyTemplate,
    this.timeout = const Duration(seconds: 30),
  });

  final String urlTemplate;
  final String method;
  final Map<String, String> headers;
  final String? bodyTemplate;
  final Duration timeout;
}

class HttpExecutionResult {
  const HttpExecutionResult({
    required this.statusCode,
    this.safeSummary,
    this.body,
  });

  final int statusCode;
  final String? safeSummary;
  final String? body;
}

abstract interface class AndroidHttpClient {
  Future<HttpExecutionResult> execute({
    required Uri url,
    required String method,
    required Map<String, String> headers,
    required String? body,
    required Duration timeout,
  });
}

class IoAndroidHttpClient implements AndroidHttpClient {
  IoAndroidHttpClient({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;

  @override
  Future<HttpExecutionResult> execute({
    required Uri url,
    required String method,
    required Map<String, String> headers,
    required String? body,
    required Duration timeout,
  }) async {
    final request = http.Request(method, url)
      ..headers.addAll(headers)
      ..body = body ?? '';
    final response = await _client.send(request).timeout(timeout);
    final responseBody = await response.stream.bytesToString();
    return HttpExecutionResult(
      statusCode: response.statusCode,
      safeSummary: responseBody.length > 256
          ? responseBody.substring(0, 256)
          : responseBody,
      body: responseBody,
    );
  }
}

abstract interface class SecretResolver {
  Future<String?> resolve(String name);
}

class AndroidHttpRunner implements WorkRunner {
  AndroidHttpRunner({
    required this.spec,
    required this.client,
    required this.secrets,
  });

  final AndroidHttpSpec spec;
  final AndroidHttpClient client;
  final SecretResolver secrets;

  @override
  String get id => 'android-http';

  @override
  Future<WorkRunResult> run(
    Work work,
    ActentMessage message, {
    required String requestId,
    required CancellationToken cancellation,
  }) async {
    if (cancellation.isCancelled) {
      return const WorkRunResult.failure(errorCode: 'cancelled');
    }
    final values = <String, Object?>{
      'message.id': message.id,
      'message.traceId': message.traceId,
      'content.type': message.content.type.value,
      'content.text': message.content.data['text'] ?? '',
      'content.url': message.content.data['url'] ?? '',
    };
    try {
      final headers = <String, String>{};
      for (final entry in spec.headers.entries) {
        headers[entry.key] = await _expandSecretOrTemplate(entry.value, values);
      }
      final result = await client.execute(
        url: Uri.parse(SafeWorkTemplate.expand(spec.urlTemplate, values)),
        method: spec.method.toUpperCase(),
        headers: headers,
        body: spec.bodyTemplate == null
            ? null
            : SafeWorkTemplate.expand(spec.bodyTemplate!, values),
        timeout: spec.timeout,
      );
      final succeeded = result.statusCode >= 200 && result.statusCode < 300;
      if (!succeeded) {
        return WorkRunResult.failure(
          errorCode: 'http_${result.statusCode}',
          summary: result.safeSummary,
        );
      }
      try {
        return WorkRunResult.success(
          summary: 'http_${result.statusCode}',
          output: parseTextWorkOutput(work, result.body ?? ''),
        );
      } on Object catch (error) {
        return WorkRunResult.failure(
          errorCode: 'output_contract_violated',
          summary: error.toString(),
        );
      }
    } catch (error) {
      return WorkRunResult.failure(
        errorCode: 'http_failed',
        summary: error.toString(),
      );
    }
  }

  Future<String> _expandSecretOrTemplate(
    String value,
    Map<String, Object?> values,
  ) async {
    final secretPattern = RegExp(r'^\{\{secret:([a-zA-Z0-9_.-]+)\}\}$');
    final match = secretPattern.firstMatch(value);
    if (match != null) {
      final secret = await secrets.resolve(match.group(1)!);
      if (secret == null) {
        throw const AndroidWorkException(
          'secret is unavailable',
          code: 'secret_unavailable',
        );
      }
      return secret;
    }
    return SafeWorkTemplate.expand(value, values);
  }
}

class AndroidWorkException implements Exception {
  const AndroidWorkException(this.message, {this.code = 'invalid_intent'});

  final String message;
  final String code;

  @override
  String toString() => message;
}

class AndroidShareWork {
  const AndroidShareWork();

  AndroidIntentSpec get spec => const AndroidIntentSpec(
    action: 'android.intent.action.SEND',
    chooser: true,
    attachmentPlacement: AndroidAttachmentPlacement.streams,
  );
}

class MemoryAndroidUriProvider implements AndroidContentUriProvider {
  @override
  Future<String> uriFor(ActentAttachment attachment) async =>
      'content://actent/${Uri.encodeComponent(attachment.id)}';
}
