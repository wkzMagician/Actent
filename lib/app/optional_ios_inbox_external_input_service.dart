import 'package:dartloom_external_input/dartloom_external_input.dart';
import 'package:flutter/services.dart';

/// Makes the App Group inbox optional for side-loaded iOS builds.
///
/// Some signing tools remove the App Group entitlement. The native adapter
/// reports that as a missing container; it must not look like a failed file
/// selection every time Actent starts. Other inbox failures are preserved.
final class OptionalIosInboxExternalInputService
    implements ExternalInputService {
  OptionalIosInboxExternalInputService(this._delegate);

  final ExternalInputService _delegate;
  Stream<ExternalInputBatch>? _inputs;

  @override
  Stream<ExternalInputBatch> get inputs =>
      _inputs ??= _delegate.inputs.handleError(
        (_) {},
        test: (error) =>
            error is PlatformException && _isMissingContainer(error),
      );

  @override
  Future<List<ExternalInputBatch>> takePending() async {
    try {
      return await _delegate.takePending();
    } on PlatformException catch (error) {
      if (_isMissingContainer(error)) return const [];
      rethrow;
    }
  }

  static bool _isMissingContainer(PlatformException error) {
    if (error.code != 'external_input_inbox_error') return false;
    final message = error.message?.toLowerCase() ?? '';
    return message.contains("doesn't exist") ||
        message.contains('does not exist') ||
        message.contains('no such file');
  }
}
