import 'package:actent/app/clipboard_external_input_service.dart';
import 'package:dartloom_external_input/dartloom_external_input.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'emits new clipboard content once and persists its change token',
    () async {
      final reader = _TestClipboardReader(
        ClipboardContent(
          changeToken: 'new-token',
          batch: ExternalInputBatch(
            source: ExternalInputSource.clipboard,
            items: [const ExternalText('Copied note')],
          ),
        ),
      );
      final savedTokens = <String>[];
      final service = ClipboardExternalInputService(
        reader: reader,
        initialChangeToken: 'old-token',
        saveChangeToken: (token) async => savedTokens.add(token),
      );
      addTearDown(service.dispose);
      final batches = <ExternalInputBatch>[];
      final subscription = service.inputs.listen(batches.add);
      addTearDown(subscription.cancel);

      await service.poll();
      await Future<void>.delayed(Duration.zero);

      expect(reader.afterChangeTokens, ['old-token']);
      expect(savedTokens, ['new-token']);
      expect(batches.single.source, ExternalInputSource.clipboard);
    },
  );

  test('coalesces concurrent clipboard lifecycle checks', () async {
    final reader = _TestClipboardReader(const ClipboardUnchanged());
    final service = ClipboardExternalInputService(reader: reader);
    addTearDown(service.dispose);

    await Future.wait([service.poll(), service.poll()]);

    expect(reader.afterChangeTokens, [null]);
  });

  test(
    'remembers an empty clipboard token to avoid repeat permission prompts',
    () async {
      final reader = _TestClipboardReader(
        const ClipboardEmpty(changeToken: 'empty-token'),
      );
      final service = ClipboardExternalInputService(reader: reader);
      addTearDown(service.dispose);

      await service.poll();
      await service.poll();

      expect(reader.afterChangeTokens, [null, 'empty-token']);
    },
  );
}

final class _TestClipboardReader implements ClipboardExternalInputReader {
  _TestClipboardReader(this.result);

  final ClipboardReadResult result;
  final afterChangeTokens = <String?>[];

  @override
  Future<ClipboardReadResult> read({String? afterChangeToken}) async {
    afterChangeTokens.add(afterChangeToken);
    return result;
  }
}
