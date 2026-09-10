import 'package:flutter_test/flutter_test.dart';
import 'package:crx_pulse/main.dart';

void main() {
  testWidgets('App builds without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const CrxPulseApp());
    expect(find.byType(CrxPulseApp), findsOneWidget);
  });
}