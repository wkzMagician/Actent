import 'dart:io';

import 'package:actent/features/actent_core/actent_models.dart';
import 'package:actent/features/actent_platform/work_input_file_picker_io.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('imports an iOS Share Extension text handoff as text', () async {
    final root = await Directory.systemTemp.createTemp('actent-ios-share-');
    addTearDown(() => root.delete(recursive: true));
    final source = File(
      '${root.path}${Platform.pathSeparator}note.actent-text',
    );
    await source.writeAsString('Shared from Notes');

    final message = await importLocalWorkInputFiles(
      paths: [source.path],
      attachmentDirectory: root.path,
      deviceId: 'phone',
    );

    expect(message, isNotNull);
    expect(message!.content.type, ActentContentType.text);
    expect(message.content.data['text'], 'Shared from Notes');
    expect(message.source.kind, 'share');
  });
}
