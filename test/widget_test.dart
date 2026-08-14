import 'package:flutter_test/flutter_test.dart';

import 'package:najime/app.dart';

void main() {
  testWidgets('app shows onboarding for unauthenticated users', (tester) async {
    await tester.pumpWidget(const NajiMeApp());
    await tester.pumpAndSettle();

    expect(find.text('Welcome to NajiMe'), findsOneWidget);
    expect(find.text('Skip'), findsOneWidget);
  });
}
