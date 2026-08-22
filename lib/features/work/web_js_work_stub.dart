import 'dart:convert';

import 'package:flutter_js/flutter_js.dart';

import '../actent_core/actent_models.dart';
import 'work_runner.dart';

class WebJsWorkConfig {
  const WebJsWorkConfig({required this.source, this.allowedHosts = const []});

  final String source;
  final List<String> allowedHosts;
}

class WebJsWorkRunner implements WorkRunner {
  WebJsWorkRunner(this.config, {this._runtime});

  final WebJsWorkConfig config;
  JavascriptRuntime? _runtime;

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
    final input = jsonEncode(message.toJson());
    final source = jsonEncode(config.source);
    final expression =
        '''
(function () {
  const input = JSON.parse($input);
  const source = JSON.parse($source);
  const api = Object.freeze({ input });
  const fn = new Function('input', 'actent', source);
  const value = fn(input, api);
  return JSON.stringify(value === undefined ? null : value);
})()
''';
    try {
      final result = (_runtime ??= getJavascriptRuntime()).evaluate(expression);
      if (cancellation.isCancelled) {
        return const WorkRunResult.failure(errorCode: 'cancelled');
      }
      final summary = result.stringResult;
      return WorkRunResult.success(
        summary: summary.length > 512 ? summary.substring(0, 512) : summary,
      );
    } on Object catch (error) {
      return WorkRunResult.failure(
        errorCode: 'script_error',
        summary: error.toString(),
      );
    }
  }
}
