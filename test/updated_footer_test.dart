import 'package:crx_pulse/screens/home/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The footer is the only place on the dashboard that says the readings
/// are coming straight off the device and are not in the cloud yet.
///
/// It also sits in a vertical list, so its Column has unbounded height
/// to work with. A greedy Column there throws during layout — which is
/// the kind of thing that only shows up when the tank's WiFi actually
/// goes down, which is the worst time to find out.
void main() {
  final at = DateTime(2026, 11, 20, 9, 5, 3);

  /// Puts the footer where the dashboard puts it: inside a Column, where
  /// the height constraint is infinite.
  Future<void> pumpInList(WidgetTester tester, Widget footer) =>
      tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(children: [const SizedBox(height: 20), footer]),
          ),
        ),
      ));

  testWidgets('lays out inside a vertical list without overflowing',
      (tester) async {
    await pumpInList(tester, UpdatedFooter(at: at));
    expect(tester.takeException(), isNull);
  });

  testWidgets('and still does so with the offline lines showing',
      (tester) async {
    await pumpInList(
        tester, UpdatedFooter(at: at, offlineDirect: true, pending: 412));
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows the reading time, zero-padded', (tester) async {
    await pumpInList(tester, UpdatedFooter(at: at));
    expect(find.text('Updated 09:05:03'), findsOneWidget);
  });

  testWidgets('says nothing about being offline when it is not',
      (tester) async {
    // The online dashboard must not acquire a second line of chrome.
    await pumpInList(tester, UpdatedFooter(at: at, pending: 7));
    expect(find.textContaining('Direct from device'), findsNothing);
  });

  testWidgets('says where the readings came from when offline',
      (tester) async {
    await pumpInList(
        tester, UpdatedFooter(at: at, offlineDirect: true, pending: 412));
    expect(find.textContaining('Direct from device'), findsOneWidget);
    expect(find.textContaining('412 readings waiting'), findsOneWidget);
  });

  group('the queue line', () {
    test('is singular for one reading', () {
      expect(UpdatedFooter.noteFor(1), contains('1 reading waiting'));
      expect(UpdatedFooter.noteFor(1), isNot(contains('readings')));
    });

    test('is plural for more', () {
      expect(UpdatedFooter.noteFor(2), contains('2 readings waiting'));
    });

    test('is dropped entirely once the queue is empty', () {
      // Right after a flush. "0 readings waiting to upload" would be a
      // worrying way to say everything is fine.
      expect(UpdatedFooter.noteFor(0), isNot(contains('waiting')));
      expect(UpdatedFooter.noteFor(0), contains('Direct from device'));
    });

    test('never shows a negative count', () {
      expect(UpdatedFooter.noteFor(-1), isNot(contains('waiting')));
    });
  });

  group('hms', () {
    test('pads every field to two digits', () {
      expect(UpdatedFooter.hms(DateTime(2026, 1, 2, 3, 4, 5)), '03:04:05');
    });

    test('is 24-hour, matching the device clock', () {
      expect(UpdatedFooter.hms(DateTime(2026, 1, 2, 23, 59, 59)), '23:59:59');
    });
  });
}
