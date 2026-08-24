import 'package:actent/features/actent_core/actent_home_page.dart';
import 'package:actent/features/actent_core/actent_models.dart';
import 'package:actent/features/actent_core/actent_store.dart';
import 'package:actent/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('workflow editor survives a missing referenced Work', (
    tester,
  ) async {
    final repository = ActentRepository(MemoryActentJsonStore());
    await repository.saveWorkflow(
      Workflow(
        id: 'workflow',
        revision: 1,
        name: 'Broken workflow',
        ownerDeviceId: 'local-device',
        steps: const [
          WorkflowStep(
            id: 'step-1',
            workId: 'removed-work',
            workRevision: 1,
            deviceId: 'local-device',
          ),
        ],
        acceptedContentTypes: ActentContentType.values.toSet(),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ActentHomePage(repository: repository, deviceId: 'local-device'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Workflows').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit').last);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final dialog = tester.widget<AlertDialog>(find.byType(AlertDialog));
    expect(dialog.scrollable, isTrue);
    final nameField = tester.widget<TextField>(find.byType(TextField).first);
    expect(nameField.controller?.text, 'Broken workflow');
  });
}
