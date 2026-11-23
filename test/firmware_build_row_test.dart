import 'package:crx_pulse/widgets/firmware_build_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Device Setup's status card lives in a vertical list, so this row has to
/// work with unbounded height. It is also the only place the app says
/// which firmware build is actually on the board.
void main() {
  Future<void> pumpInList(WidgetTester tester, String? tag) =>
      tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(children: [FirmwareBuildRow(tag: tag)]),
          ),
        ),
      ));

  testWidgets('shows the build tag the device reported', (tester) async {
    await pumpInList(tester, '2026.11.23-motor-first');

    expect(find.text('Firmware build'), findsOneWidget);
    expect(find.text('2026.11.23-motor-first'), findsOneWidget);
  });

  testWidgets('shows a placeholder and hint when the tag is unknown',
      (tester) async {
    await pumpInList(tester, null);

    expect(find.text('Firmware build'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
    expect(
      find.text("Connect to the device's WiFi to read the build tag"),
      findsOneWidget,
    );
  });

  testWidgets('lays out inside a vertical list without overflowing',
      (tester) async {
    await pumpInList(tester, '2026.11.23-motor-first');

    expect(tester.takeException(), isNull);
  });
}
