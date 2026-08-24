import 'dart:async';

import 'package:dartloom_external_input/dartloom_external_input.dart';

/// Application composition for desktop command-line and second-instance file
/// arguments until Dartloom provides desktop external-input adapters.
final class QueuedExternalInputService implements ExternalInputService {
  QueuedExternalInputService([Iterable<ExternalInputBatch> pending = const []])
    : _pending = List<ExternalInputBatch>.from(pending);

  final StreamController<ExternalInputBatch> _controller =
      StreamController<ExternalInputBatch>.broadcast();
  final List<ExternalInputBatch> _pending;

  @override
  Stream<ExternalInputBatch> get inputs => _controller.stream;

  void addFilePaths(Iterable<String> paths) {
    final items = [
      for (final path in paths)
        if (path.isNotEmpty) ExternalFile(path: path),
    ];
    if (items.isEmpty) return;
    final batch = ExternalInputBatch(
      items: items,
      source: ExternalInputSource.openWith,
    );
    if (_controller.hasListener) {
      _controller.add(batch);
    } else {
      _pending.add(batch);
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
