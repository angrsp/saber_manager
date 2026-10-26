import 'package:flutter_test/flutter_test.dart';

import 'package:saber_manager/main.dart';

void main() {
  testWidgets('L\'app si avvia sulla home, disconnessa', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('Saber Manager'), findsOneWidget);
    expect(find.text('Disconnected'), findsOneWidget);
    expect(find.text('Connect Saber'), findsOneWidget);
  });
}
