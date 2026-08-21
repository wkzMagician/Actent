import 'package:flutter_test/flutter_test.dart';

import 'package:actent/app/app.dart';

void main() {
  testWidgets('shows the Actent app shell', (tester) async {
    await tester.pumpWidget(const DartloomApp());
    await tester.pumpAndSettle();
    expect(find.text('Activity'), findsNWidgets(2));
    expect(
      find.text('Inputs and Work execution history will appear here.'),
      findsOneWidget,
    );
  });
}
