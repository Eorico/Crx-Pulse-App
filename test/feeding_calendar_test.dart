import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crx_pulse/widgets/feeding_calendar.dart';

void main() {
  final harness = _CalendarHarness();
  setUp(() => harness.result = null);

  testWidgets('opens on the device-today month', (tester) async {
    await harness.open(tester);

    // The phone clock reads 2026-10-22 16:30 UTC, but the device fires on
    // UTC+8 where it is already 2026-10-23. The grid must follow the device.
    expect(find.text('October 2026'), findsOneWidget);
    expect(find.byKey(const Key('feeding-day-2026-10-23')), findsOneWidget);
    expect(find.byKey(const Key('feeding-day-2026-10-24')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('single mode returns the one tapped day', (tester) async {
    await harness.open(tester);
    await harness.tapDay(tester, '2026-10-24');

    expect(await harness.confirm(tester), ['2026-10-24']);
  });

  testWidgets('multiple mode returns both taps sorted', (tester) async {
    await harness.open(tester, mode: FeedingCalendarMode.multiple);
    await harness.tapDay(tester, '2026-10-25');
    await harness.tapDay(tester, '2026-10-24');

    expect(await harness.confirm(tester), ['2026-10-24', '2026-10-25']);
  });

  testWidgets('a day before the UTC+8 today cannot be selected', (tester) async {
    await harness.open(tester, mode: FeedingCalendarMode.multiple);
    await harness.tapDay(tester, '2026-10-22');

    expect(
      tester
          .widget<ElevatedButton>(
            find.byKey(const Key('feeding-calendar-confirm')),
          )
          .onPressed,
      isNull,
      reason: 'tapping a past day must leave the selection empty',
    );

    // The next day is today on the device and is selectable, proving the
    // past tap was ignored rather than the whole grid being inert.
    await harness.tapDay(tester, '2026-10-23');
    expect(await harness.confirm(tester), ['2026-10-23']);
  });

  testWidgets('range mode returns every day between the two taps',
      (tester) async {
    await harness.open(tester, mode: FeedingCalendarMode.range);
    await harness.tapDay(tester, '2026-10-24');
    await harness.tapDay(tester, '2026-10-27');

    expect(await harness.confirm(tester), [
      '2026-10-24',
      '2026-10-25',
      '2026-10-26',
      '2026-10-27',
    ]);
  });

  testWidgets('today quick pick replaces the existing selection', (tester) async {
    await harness.open(tester,
        mode: FeedingCalendarMode.multiple,
        selected: const ['2026-10-24', '2026-10-25']);

    await tester.tap(find.byKey(const Key('feeding-quick-today')));
    await tester.pumpAndSettle();

    expect(await harness.confirm(tester), ['2026-10-23']);
  });

  testWidgets('tomorrow quick pick selects only the next day', (tester) async {
    await harness.open(tester, mode: FeedingCalendarMode.multiple);

    await tester.tap(find.byKey(const Key('feeding-quick-tomorrow')));
    await tester.pumpAndSettle();

    expect(await harness.confirm(tester), ['2026-10-24']);
  });

  testWidgets('next 7 days crosses the month boundary', (tester) async {
    await harness.open(tester, now: DateTime.utc(2026, 10, 30, 16, 30));

    await tester.tap(find.byKey(const Key('feeding-quick-next-7')));
    await tester.pumpAndSettle();

    expect(await harness.confirm(tester), [
      '2026-10-31', '2026-11-01', '2026-11-02', '2026-11-03',
      '2026-11-04', '2026-11-05', '2026-11-06',
    ]);
  });

  testWidgets('range mode returns every day across a month boundary',
      (tester) async {
    await harness.open(tester,
        now: DateTime.utc(2026, 9, 29, 16, 30),
        mode: FeedingCalendarMode.range);
    await harness.tapDay(tester, '2026-09-30');
    await tester.tap(find.byKey(const Key('feeding-calendar-next-month')));
    await tester.pumpAndSettle();
    await harness.tapDay(tester, '2026-10-02');

    expect(await harness.confirm(tester), [
      '2026-09-30', '2026-10-01', '2026-10-02',
    ]);
  });

  testWidgets('empty selection shows a summary and disables Confirm',
      (tester) async {
    await harness.open(tester);

    expect(find.byKey(const Key('feeding-calendar-summary')), findsOneWidget);
    expect(find.text('No dates selected'), findsOneWidget);
    expect(
      tester
          .widget<ElevatedButton>(
            find.byKey(const Key('feeding-calendar-confirm')),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('today marker appears only on the device-today cell',
      (tester) async {
    await harness.open(tester, mode: FeedingCalendarMode.multiple);

    expect(
      find.byKey(const Key('feeding-calendar-today-marker')),
      findsOneWidget,
    );
    final markerParent = find.ancestor(
      of: find.byKey(const Key('feeding-calendar-today-marker')),
      matching: find.byKey(const Key('feeding-day-2026-10-23')),
    );
    expect(markerParent, findsOneWidget);
  });

  testWidgets('range summary names the first and last date', (tester) async {
    await harness.open(tester, mode: FeedingCalendarMode.range);
    await harness.tapDay(tester, '2026-10-24');
    await harness.tapDay(tester, '2026-10-27');

    expect(
      find.text('4 days · 2026-10-24 – 2026-10-27'),
      findsOneWidget,
    );
  });

  testWidgets('tomorrow quick pick jumps to the next month at a boundary',
      (tester) async {
    await harness.open(tester, now: DateTime.utc(2026, 10, 30, 16, 30));

    await tester.tap(find.byKey(const Key('feeding-quick-tomorrow')));
    await tester.pumpAndSettle();

    expect(find.text('November 2026'), findsOneWidget);
    expect(await harness.confirm(tester), ['2026-11-01']);
  });

  testWidgets('mode control switches from single to multiple', (tester) async {
    await harness.open(tester);

    await tester.tap(find.byKey(const Key('feeding-mode-multiple')));
    await tester.pumpAndSettle();
    await harness.tapDay(tester, '2026-10-24');
    await harness.tapDay(tester, '2026-10-25');

    expect(await harness.confirm(tester), ['2026-10-24', '2026-10-25']);
  });

  testWidgets('calendar fits on a short viewport', (tester) async {
    tester.view.physicalSize = const Size(800, 560);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await harness.open(tester, mode: FeedingCalendarMode.range);
    await harness.tapDay(tester, '2026-10-27');

    expect(tester.takeException(), isNull);
  });
}

/// Drives the real [showFeedingCalendar] entry point and captures what it
/// returns, the same way a caller in the app would.
class _CalendarHarness {
  List<String>? result;

  Future<void> open(
    WidgetTester tester, {
    DateTime? now,
    FeedingCalendarMode mode = FeedingCalendarMode.single,
    List<String> selected = const [],
  }) async {
    result = null;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await showFeedingCalendar(
                    context,
                    now: now ?? DateTime.utc(2026, 10, 22, 16, 30),
                    selected: selected,
                    initialMode: mode,
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('feeding-calendar-confirm')),
      findsOneWidget,
      reason: 'the calendar dialog did not open',
    );
  }

  Future<void> tapDay(WidgetTester tester, String date) async {
    final finder = find.byKey(Key('feeding-day-$date'));
    expect(finder, findsOneWidget, reason: 'day $date is not in the grid');
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<List<String>?> confirm(WidgetTester tester) async {
    final finder = find.byKey(const Key('feeding-calendar-confirm'));
    expect(
      tester.widget<ElevatedButton>(finder).onPressed,
      isNotNull,
      reason: 'Confirm must be enabled once a day is selected',
    );
    await tester.tap(finder);
    await tester.pumpAndSettle();
    return result;
  }
}
