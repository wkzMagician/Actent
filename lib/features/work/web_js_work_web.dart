import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import '../actent_core/actent_models.dart';
import 'work_runner.dart';

@JS('eval')
external JSAny? _evaluate(JSString source);

class WebJsWorkConfig {
  const WebJsWorkConfig({required this.source, this.allowedHosts = const []});

  final String source;
  final List<String> allowedHosts;
}

class WebJsWorkRunner implements WorkRunner {
  const WebJsWorkRunner(this.config);

  final WebJsWorkConfig config;

  @override
  String get id => 'web-js';

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
    if (config.source.trim().isEmpty) {
      return const WorkRunResult.failure(errorCode: 'script_empty');
    }
    final input = jsonEncode(message.toJson()).replaceAll('</', '<\\/');
    final source = jsonEncode(config.source).replaceAll('</', '<\\/');
    final hosts = jsonEncode(config.allowedHosts);
    final expression =
        '''
(async function () {
  const input = JSON.parse($input);
  const allowedHosts = new Set($hosts);
  const originalFetch = globalThis.fetch;
  const originalWebSocket = globalThis.WebSocket;
  const restrictedFetch = async function (resource, init) {
    const url = new URL(resource, globalThis.location.href);
    if (!allowedHosts.has(url.host)) {
      throw new Error('network permission denied for ' + url.host);
    }
    return originalFetch(resource, init);
  };
  globalThis.fetch = restrictedFetch;
  globalThis.WebSocket = undefined;
  try {
    const api = Object.freeze({ input });
    const fn = new Function('input', 'actent', $source);
    const value = await fn(input, api);
    return JSON.stringify(value === undefined ? null : value);
  } finally {
    globalThis.fetch = originalFetch;
    globalThis.WebSocket = originalWebSocket;
  }
})()
''';
    try {
      final raw = _evaluate(expression.toJS);
      final resolved = await (raw as JSPromise<JSAny?>).toDart;
      if (cancellation.isCancelled) {
        return const WorkRunResult.failure(errorCode: 'cancelled');
      }
      final value = resolved?.dartify();
      return WorkRunResult.success(
        summary: value is String && value.length > 512
            ? value.substring(0, 512)
            : '$value',
      );
    } on Object catch (error) {
      return WorkRunResult.failure(
        errorCode: 'script_error',
        summary: error.toString(),
      );
    }
  }
}
