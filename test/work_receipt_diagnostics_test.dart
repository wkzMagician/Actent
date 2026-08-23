import 'package:actent/features/actent_core/actent_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('keeps raw diagnostics local while limiting remote summaries', () {
    final receipt = WorkReceipt(
      requestId: 'request',
      workId: 'work',
      status: WorkReceiptStatus.failed,
      createdAt: DateTime.utc(2026),
      summary: 'a' * 32,
      diagnostics: WorkExecutionDiagnostics(
        stage: 'exited',
        exitCode: 1,
        stdout: 'private stdout',
        stderr: 'private stderr',
      ),
    );

    final local = receipt.toJson();
    final remote = receipt.toRemoteJson(maxSummaryCharacters: 8);

    expect(local['diagnostics'], isNotNull);
    expect(remote['diagnostics'], isNull);
    expect(remote['summary'], endsWith('[truncated]'));
  });
}
