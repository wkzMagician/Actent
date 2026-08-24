import 'package:dartloom_external_input/dartloom_external_input.dart';

import '../actent_core/actent_models.dart';

typedef ExternalFileMessageImporter = Future<ActentMessage?> Function(
  List<String> paths,
);

/// Translates platform-neutral input into Actent's message model.
///
/// Platform adapters own acquisition and file lifetime. This coordinator only
/// chooses the Actent payload shape that the Work and Workflow picker needs.
final class ActentShareCoordinator {
  ActentShareCoordinator({required this.deviceId, required this._importFiles});

  final String deviceId;
  final ExternalFileMessageImporter _importFiles;
  var _messageSequence = 0;

  Future<List<ActentMessage>> handle(ExternalInputBatch batch) async {
    final messages = <ActentMessage>[];
    final files = batch.items.whereType<ExternalFile>().toList(growable: false);
    if (files.isNotEmpty) {
      final fileMessage = await _importFiles(
        files.map((input) => input.path).toList(growable: false),
      );
      if (fileMessage != null) {
        messages.add(_withExternalSource(fileMessage, batch.source));
      }
    }
    for (final input in batch.items) {
      switch (input) {
        case ExternalText(:final text):
          messages.add(_messageForText(text, batch.source));
        case ExternalUrl(:final url):
          messages.add(_messageForUrl(url, batch.source));
        case ExternalFile():
          break;
      }
    }
    return messages;
  }

  ActentMessage _messageForText(String text, ExternalInputSource source) {
    final now = DateTime.now().toUtc();
    final id = _nextMessageId(now);
    return ActentMessage(
      id: id,
      traceId: id,
      createdAt: now,
      source: _source(source),
      content: ActentContent(
        type: ActentContentType.text,
        data: {'text': text},
      ),
      metadata: {'externalInputSource': source.name},
    );
  }

  ActentMessage _messageForUrl(Uri url, ExternalInputSource source) {
    final now = DateTime.now().toUtc();
    final id = _nextMessageId(now);
    return ActentMessage(
      id: id,
      traceId: id,
      createdAt: now,
      source: _source(source),
      content: ActentContent(
        type: ActentContentType.url,
        data: {'url': url.toString()},
      ),
      metadata: {'externalInputSource': source.name},
    );
  }

  ActentMessage _withExternalSource(
    ActentMessage message,
    ExternalInputSource source,
  ) => ActentMessage(
    id: message.id,
    traceId: message.traceId,
    createdAt: message.createdAt,
    source: _source(source),
    payload: message.payload,
    metadata: {...message.metadata, 'externalInputSource': source.name},
  );

  ActentSource _source(ExternalInputSource source) => ActentSource(
    kind: source.name,
    deviceId: deviceId,
    appName: 'External input',
  );

  String _nextMessageId(DateTime timestamp) =>
      'external-${timestamp.microsecondsSinceEpoch.toRadixString(36)}-${_messageSequence++}';
}
