import 'package:flutter/services.dart';

import '../../actent_core/actent_models.dart';
import '../work_runner.dart';

/// iOS is intentionally not registered in the first release. This shared
/// contract keeps future Intent/HTTP implementations from changing Core.
abstract interface class IOSWorkRunner implements WorkRunner {}

class IOSRunnerPlaceholder implements IOSWorkRunner {
  const IOSRunnerPlaceholder();

  @override
  String get id => 'ios-placeholder';

  @override
  Future<WorkRunResult> run(
    Work work,
    ActentMessage message, {
    required String requestId,
    required CancellationToken cancellation,
  }) async => const WorkRunResult.failure(errorCode: 'ios_not_registered');
}

/// Opens an iOS application through its URL scheme or universal link.
///
/// The URL is deliberately user-configured: iOS does not provide an Android-
/// style general Intent API. Templates may reference message fields such as
/// `{{content.text}}` and `{{content.url}}`.
class IosUrlWorkRunner implements IOSWorkRunner {
  IosUrlWorkRunner({required this.urlTemplate, MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('actent/ios_work');

  final String urlTemplate;
  final MethodChannel _channel;

  @override
  String get id => 'ios-url';

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
      final url = _expandTemplate(urlTemplate, message);
      if (Uri.tryParse(url)?.hasScheme != true) {
        return const WorkRunResult.failure(errorCode: 'invalid_url');
      }
      final opened = await _channel.invokeMethod<bool>('openUrl', {'url': url});
      return opened == true
          ? const WorkRunResult.success(summary: 'url_opened')
          : const WorkRunResult.failure(errorCode: 'application_unavailable');
    } on PlatformException catch (error) {
      return WorkRunResult.failure(
        errorCode: error.code,
        summary: error.message,
      );
    } on Object catch (error) {
      return WorkRunResult.failure(
        errorCode: 'application_launch_failed',
        summary: error.toString(),
      );
    }
  }

  String _expandTemplate(String template, ActentMessage message) {
    final values = <String, Object?>{
      'message.id': message.id,
      'message.traceId': message.traceId,
      'content.type': message.content.type.value,
      'content.text': message.content.data['text'] ?? '',
      'content.url': message.content.data['url'] ?? '',
    };
    return template.replaceAllMapped(RegExp(r'\{\{([a-zA-Z0-9_.-]+)\}\}'), (
      match,
    ) {
      final name = match.group(1)!;
      if (!values.containsKey(name)) {
        throw FormatException('unknown template placeholder: $name');
      }
      return Uri.encodeComponent('${values[name]}');
    });
  }
}
