import 'dart:convert';

import '../actent_core/actent_models.dart';

ActentPayload? parseTextWorkOutput(
  Work work,
  String stdout, {
  int maxTextBytes = 1024 * 1024,
}) {
  final value = stdout.trim();
  switch (work.outputType) {
    case ActentContentType.none:
      return null;
    case ActentContentType.text:
      if (stdout.length > maxTextBytes) {
        throw const FormatException('text output exceeds the configured limit');
      }
      return ActentPayload(
        type: ActentContentType.text,
        data: {'text': stdout},
      );
    case ActentContentType.url:
      if (value.isEmpty) throw const FormatException('URL output is empty');
      return ActentPayload(type: ActentContentType.url, data: {'url': value});
    case ActentContentType.json:
      if (value.isEmpty) throw const FormatException('JSON output is empty');
      return ActentPayload(
        type: ActentContentType.json,
        data: {'json': jsonDecode(value)},
      );
    case ActentContentType.image:
    case ActentContentType.file:
      throw const FormatException(
        'file and image outputs require an attachment manifest',
      );
  }
}

ActentPayload? parseDynamicWorkOutput(Work work, Object? value) {
  switch (work.outputType) {
    case ActentContentType.none:
      return null;
    case ActentContentType.text:
      return ActentPayload(
        type: ActentContentType.text,
        data: {'text': '$value'},
      );
    case ActentContentType.url:
      final url = '$value'.trim();
      if (url.isEmpty) throw const FormatException('URL output is empty');
      return ActentPayload(type: ActentContentType.url, data: {'url': url});
    case ActentContentType.json:
      return ActentPayload(type: ActentContentType.json, data: {'json': value});
    case ActentContentType.image:
    case ActentContentType.file:
      throw const FormatException(
        'file and image outputs require an attachment manifest',
      );
  }
}
