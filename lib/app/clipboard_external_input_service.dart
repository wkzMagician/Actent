import 'dart:async';

import 'package:dartloom_external_input/dartloom_external_input.dart';

/// Converts explicitly requested clipboard reads into ordinary external-input
/// batches. Application composition owns when [poll] is called.
final class ClipboardExternalInputService implements ExternalInputService {
  ClipboardExternalInputService({
    required this._reader,
    String? initialChangeToken,
    this._saveChangeToken,
  }) : _changeToken = initialChangeToken;

  final ClipboardExternalInputReader _reader;
  final Future<void> Function(String token)? _saveChangeToken;
  final StreamController<ExternalInputBatch> _controller =
      StreamController<ExternalInputBatch>.broadcast();
  final List<ExternalInputBatch> _pending = [];
  String? _changeToken;
  Future<void>? _polling;

  @override
  Stream<ExternalInputBatch> get inputs => _controller.stream;

  /// Checks the clipboard once. Concurrent lifecycle events are coalesced.
  Future<void> poll({bool force = false}) {
    final active = _polling;
    if (active != null) return active;
    final operation = _poll(force: force);
    _polling = operation;
    return operation.whenComplete(() {
      _polling = null;
    });
  }

  Future<void> _poll({required bool force}) async {
    final result = await _reader.read(
      afterChangeToken: force ? null : _changeToken,
    );
    if (result case ClipboardEmpty(:final changeToken?)) {
      await _rememberChangeToken(changeToken);
      return;
    }
    if (result is! ClipboardContent) return;
    await _rememberChangeToken(result.changeToken);
    if (_controller.hasListener) {
      _controller.add(result.batch);
    } else {
      _pending.add(result.batch);
    }
  }

  Future<void> _rememberChangeToken(String token) async {
    _changeToken = token;
    try {
      await _saveChangeToken?.call(token);
    } on Object {
      // Clipboard routing remains available if durable de-duplication fails.
    }
  }

  @override
  Future<List<ExternalInputBatch>> takePending() async {
    final result = List<ExternalInputBatch>.from(_pending);
    _pending.clear();
    return result;
  }

  Future<void> dispose() => _controller.close();
}
