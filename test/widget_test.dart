import 'package:flutter_test/flutter_test.dart';

import 'package:pengion/app/app.dart';

void main() {
  testWidgets('shows the Pigeon app shell', (tester) async {
    await tester.pumpWidget(const DartloomApp());
    await tester.pumpAndSettle();
    expect(find.text('Inbox'), findsNWidgets(2));
    expect(
      find.text('Shared content and Work receipts will appear here.'),
      findsOneWidget,
    );
  });
}
