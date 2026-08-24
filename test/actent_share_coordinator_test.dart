import 'package:actent/features/actent_core/actent_models.dart';
import 'package:actent/features/share/actent_share_coordinator.dart';
import 'package:dartloom_external_input/dartloom_external_input.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('maps text and URL inputs without platform details', () async {
    final coordinator = ActentShareCoordinator(
      deviceId: 'phone',
      importFiles: (_) async => null,
    );

    final messages = await coordinator.handle(
      ExternalInputBatch(
        source: ExternalInputSource.share,
        items: [
          const ExternalText('A note'),
          ExternalUrl(Uri.parse('https://example.com')),
        ],
      ),
    );

    expect(messages.map((message) => message.content.type), [
      ActentContentType.text,
      ActentContentType.url,
    ]);
    expect(messages.every((message) => message.source.kind == 'share'), isTrue);
  });
}
