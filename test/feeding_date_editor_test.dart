import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crx_pulse/core/feeding_schedule.dart';
import 'package:crx_pulse/services/local_feeding_provider.dart';
import 'package:crx_pulse/widgets/feeding_date_editor.dart';

void main() {
  // The calendar refuses past device dates, so derive future dates from the
  // device's UTC+8 "today" rather than freezing the clock in the tests.
  final today = DateTime.parse(deviceTodayDate());
  final firstDate = _futureDate(today, 2);
  final secondDate = _futureDate(today, 3);
  final newDate = _futureDate(today, 4);

  final harness = _EditorHarness();
  setUp(() => harness.result = null);

  testWidgets('opens one section per date', (tester) async {
    await harness.open(tester, dates: [firstDate, secondDate]);

    expect(find.byKey(Key('feeding-date-section-$firstDate')), findsOneWidget);
    expect(find.byKey(Key('feeding-date-section-$secondDate')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Add another feed appends a row only on that date', (tester) async {
    await harness.open(tester, dates: [firstDate, secondDate]);

    await tester.tap(find.byKey(Key('feeding-add-feed-$firstDate')));
    await tester.pumpAndSettle();

    expect(find.byKey(Key('feeding-feed-row-$firstDate-1')), findsOneWidget);
    expect(find.byKey(Key('feeding-feed-row-$secondDate-1')), findsNothing);
  });

  testWidgets('each feed keeps its own dose and rotator speed', (tester) async {
    await harness.open(tester, dates: [firstDate, secondDate]);
    await tester.tap(find.byKey(Key('feeding-add-feed-$firstDate')));
    await tester.pumpAndSettle();

    await selectDropdown(
      tester,
      Key('feeding-feed-grams-$firstDate-0'),
      '25 grams',
    );
    await selectDropdown(
      tester,
      Key('feeding-feed-rotator-$firstDate-0'),
      'Off — no rotation',
    );
    await selectDropdown(
      tester,
      Key('feeding-feed-grams-$firstDate-1'),
      '15 grams',
    );

    await harness.save(tester);

    final drafts = harness.result![firstDate]!;
    expect(drafts, hasLength(2));
    expect(drafts[0].grams, 25);
    expect(drafts[0].rotatorPwm, 0);
    expect(drafts[1].grams, 15);
    expect(drafts[1].rotatorPwm, 255);
  });

  testWidgets('a time colliding with a saved row blocks Save', (tester) async {
    await harness.open(
      tester,
      dates: [firstDate, secondDate],
      existing: [
        FeedingSchedule(
          id: 'saved-1',
          feedDate: firstDate,
          time: '08:00',
          grams: 10,
          rotatorPwm: 255,
          active: true,
        ),
      ],
    );
    await tester.tap(find.byKey(Key('feeding-add-feed-$firstDate')));
    await tester.pumpAndSettle();

    await harness.save(tester);

    expect(harness.result, isNull, reason: 'a conflict must not close the editor');
    expect(find.byKey(const Key('feeding-date-editor-conflict')), findsOneWidget);
    expect(find.textContaining('$firstDate · 08:00'), findsOneWidget);
    expect(find.byKey(const Key('feeding-date-editor-save')), findsOneWidget);
  });

  testWidgets('excluded saved rows do not block Save', (tester) async {
    await harness.open(
      tester,
      dates: [firstDate, secondDate],
      existing: [
        FeedingSchedule(
          id: 'saved-1',
          feedDate: firstDate,
          time: '09:00',
          grams: 10,
          rotatorPwm: 255,
          active: true,
        ),
      ],
      excludedIds: const {'saved-1'},
    );

    await harness.save(tester);

    expect(harness.result, isNotNull);
  });

  testWidgets('Change date moves a section under the chosen date',
      (tester) async {
    await harness.open(tester, dates: [firstDate, secondDate]);

    await tester.tap(find.byKey(Key('feeding-date-change-$firstDate')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('feeding-calendar-confirm')), findsOneWidget,
        reason: 'the calendar did not open');

    await navigateCalendarMonth(tester, newDate);
    await tester.tap(find.byKey(Key('feeding-day-$newDate')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('feeding-calendar-confirm')));
    await tester.pumpAndSettle();

    expect(find.byKey(Key('feeding-date-section-$newDate')), findsOneWidget);
    expect(find.byKey(Key('feeding-date-section-$firstDate')), findsNothing);

    await harness.save(tester);

    final saved = harness.result!;
    expect(saved.keys, containsAll([newDate, secondDate]));
    expect(saved.keys, isNot(contains(firstDate)));
    expect(saved[newDate]!.single.feedDate, newDate);
  });

  testWidgets('Save returns the drafts for every date', (tester) async {
    await harness.open(tester, dates: [firstDate, secondDate]);

    await harness.save(tester);

    final saved = harness.result!;
    expect(saved.keys, unorderedEquals([firstDate, secondDate]));
    expect(saved[firstDate]!.single.time, '09:00');
    expect(saved[secondDate]!.single.time, '09:30');
  });

  testWidgets('Save is disabled when every date section is empty',
      (tester) async {
    await harness.open(tester, dates: [firstDate, secondDate]);

    await tester.tap(find.byKey(Key('feeding-remove-feed-$firstDate-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('feeding-remove-feed-$secondDate-0')));
    await tester.pumpAndSettle();

    final save = find.byKey(const Key('feeding-date-editor-save'));
    expect(tester.widget<ElevatedButton>(save).onPressed, isNull);
    await harness.save(tester);
    expect(harness.result, isNull, reason: 'an empty result must not close');
    expect(find.byKey(const Key('feeding-date-editor-save')), findsOneWidget);
  });
}

/// Drives the real [showFeedingDateEditor] entry point and captures what it
/// returns, the same way a caller in the app would.
class _EditorHarness {
  Map<String, List<FeedingDraft>>? result;

  Future<void> open(
    WidgetTester tester, {
    required List<String> dates,
    Map<String, List<FeedingDraft>>? initialByDate,
    List<FeedingSchedule> existing = const [],
    Set<String> excludedIds = const {},
  }) async {
    final initial = initialByDate ?? {
      for (final date in dates)
        date: [
          FeedingDraft(
            feedDate: date,
            time: date == dates.first ? '09:00' : '09:30',
            grams: 10,
            rotatorPwm: 255,
          ),
        ],
    };

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await showFeedingDateEditor(
                    context,
                    dates: dates,
                    initialByDate: initial,
                    existing: existing,
                    excludedIds: excludedIds,
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
    expect(find.byKey(const Key('feeding-date-editor-save')), findsOneWidget,
        reason: 'the editor did not open');
  }

  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('feeding-date-editor-save')));
    await tester.pumpAndSettle();
  }
}

String _futureDate(DateTime from, int daysAhead) {
  final date = from.add(Duration(days: daysAhead));
  return '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

Future<void> selectDropdown(
  WidgetTester tester,
  Key key,
  String label,
) async {
  await tester.tap(find.byKey(key));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

Future<void> navigateCalendarMonth(WidgetTester tester, String target) async {
  final today = DateTime.parse(deviceTodayDate());
  final chosen = DateTime.parse(target);
  final monthsAhead =
      (chosen.year - today.year) * 12 + chosen.month - today.month;
  for (var i = 0; i < monthsAhead; i++) {
    await tester.tap(find.byKey(const Key('feeding-calendar-next-month')));
    await tester.pumpAndSettle();
  }
}
