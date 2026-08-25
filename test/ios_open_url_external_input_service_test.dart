import 'package:actent/app/ios_open_url_external_input_service.dart';
import 'package:dartloom_external_input/dartloom_external_input.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('reads pending open-file and open-URL batches from iOS', () async {
    const methods = MethodChannel('actent/ios_open_url/methods');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(methods, (call) async {
      expect(call.method, 'takePending');
      return [
        {
          'source': 'openWith',
          'items': [
            {'type': 'file', 'path': '/tmp/example.pdf', 'name': 'example.pdf'},
          ],
        },
        {
          'source': 'deepLink',
          'items': [
            {'type': 'url', 'url': 'https://example.com/article'},
          ],
        },
      ];
    });
    addTearDown(() => messenger.setMockMethodCallHandler(methods, null));

    final batches = await IosOpenUrlExternalInputService(methods: methods)
        .takePending();

    expect(batches.map((batch) => batch.source), [
      ExternalInputSource.openWith,
      ExternalInputSource.deepLink,
    ]);
    expect(
      batches.first.items.single,
      const ExternalFile(path: '/tmp/example.pdf', name: 'example.pdf'),
    );
    expect(
      batches.last.items.single,
      ExternalUrl(Uri.parse('https://example.com/article')),
    );
  });
}
