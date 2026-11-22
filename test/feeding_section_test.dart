import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:crx_pulse/core/feeding_schedule.dart';
import 'package:crx_pulse/services/device_provider.dart';
import 'package:crx_pulse/services/local_feeding_provider.dart';
import 'package:crx_pulse/widgets/feeding_section.dart';

void main() {
  // Device dates are UTC+8 calendar days. Derive them from device "today" so
  // the calendar never rejects them as the wall clock moves on.
  final today = DateTime.parse(deviceTodayDate());
  final firstDate = _futureDate(today, 2);
  final secondDate = _futureDate(today, 3);
  final movedDate = _futureDate(today, 4);
  final thirdDate = _futureDate(today, 5);
  final fourthDate = _futureDate(today, 6);
  final convertDate = _futureDate(today, 7);

  setUpAll(() async {
    // Supabase's auth storage uses shared_preferences, which has no test
    // implementation. An in-memory channel is enough to construct the
    // DeviceProvider the section watches; no auth call is made here.
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/shared_preferences'),
      (call) async {
        if (call.method == 'getAll') return <String, Object>{};
        return null;
      },
    );
    await Supabase.initialize(
      url: 'http://localhost:54321',
      publishableKey: 'test-key',
    );
  });

  final harness = _FeedingHarness();
  setUp(() => harness.reset());

  testWidgets('overview groups two dates plus the legacy every-day group',
      (tester) async {
    await harness.pump(tester);

    expect(find.text(firstDate), findsOneWidget);
    expect(find.text(secondDate), findsOneWidget);
    expect(find.text('Every day'), findsOneWidget);
    expect(find.byKey(Key('feeding-overview-group-$firstDate')),
        findsOneWidget);
    expect(find.byKey(const Key('feeding-overview-group-every-day')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Edit opens the editor prefilled with that date only',
      (tester) async {
    await harness.pump(tester);

    await harness.tapKey(tester, Key('feeding-overview-edit-$firstDate'));

    expect(find.byKey(Key('feeding-date-section-$firstDate')),
        findsOneWidget);
    expect(find.byKey(Key('feeding-date-section-$secondDate')),
        findsNothing);
    expect(find.byKey(Key('feeding-feed-row-$firstDate-0')),
        findsOneWidget);
    expect(
      tester
          .widget<DropdownButton<int>>(
            find.byKey(Key('feeding-feed-grams-$firstDate-0')),
          )
          .value,
      15,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('saving a field edit rewrites only the edited date group',
      (tester) async {
    await harness.pump(tester);
    await harness.openEditor(tester, firstDate);

    await harness.selectGrams(tester, firstDate, 0, '25 grams');
    await harness.saveEditor(tester);

    expect(harness.feeding.updates, hasLength(1));
    final call = harness.feeding.updates.single;
    expect(call.date, firstDate);
    expect(call.original.map((s) => s.id), orderedEquals(['a1', 'a2']));
    expect(call.edited.map((d) => d.id), orderedEquals(['a1', 'a2']));
    expect(call.edited.first.grams, 25);
    expect(call.edited.last.grams, 15);
    expect(call.edited.map((d) => d.id),
        isNot(containsAll(['b1', 'legacy-1'])),
        reason: 'another date group must not be rewritten');
    expect(harness.feeding.deletes, isEmpty);
    expect(harness.feeding.creates, isEmpty);
  });

  testWidgets('changing the date in the editor moves only that group',
      (tester) async {
    await harness.pump(tester);
    await harness.openEditor(tester, firstDate);

    await tester
        .tap(find.byKey(Key('feeding-date-change-$firstDate')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('feeding-calendar-confirm')), findsOneWidget,
        reason: 'the calendar did not open');
    await navigateCalendarMonth(tester, movedDate);
    await tester.tap(find.byKey(Key('feeding-day-$movedDate')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('feeding-calendar-confirm')));
    await tester.pumpAndSettle();
    await harness.saveEditor(tester);

    expect(harness.feeding.updates, hasLength(1));
    final call = harness.feeding.updates.single;
    expect(call.date, movedDate);
    expect(call.edited.map((d) => d.feedDate), everyElement(movedDate));
    expect(call.edited.map((d) => d.id), orderedEquals(['a1', 'a2']));
    expect(call.edited.map((d) => d.grams), orderedEquals([15, 15]));
  });

  testWidgets('Delete calls deleteSchedules with every id in the group',
      (tester) async {
    await harness.pump(tester);

    await harness.tapKey(
        tester, Key('feeding-overview-delete-$firstDate'));

    expect(harness.feeding.deletes, hasLength(1));
    expect(harness.feeding.deletes.single, unorderedEquals(['a1', 'a2']));
    expect(harness.feeding.updates, isEmpty);
    expect(harness.feeding.creates, isEmpty);
  });

  testWidgets('Choose dates opens calendar then editor then creates one '
      'draft per date/feed pair', (tester) async {
    await harness.pump(tester);

    await harness.tapKey(tester, const Key('feeding-choose-dates'));
    expect(find.byKey(const Key('feeding-calendar-confirm')), findsOneWidget,
        reason: 'the calendar did not open');

    await tester.tap(find.byKey(const Key('feeding-mode-multiple')));
    await tester.pumpAndSettle();
    for (final date in [thirdDate, fourthDate]) {
      await navigateCalendarMonth(tester, date);
      await tester.tap(find.byKey(Key('feeding-day-$date')));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byKey(const Key('feeding-calendar-confirm')));
    await tester.pumpAndSettle();

    expect(find.byKey(Key('feeding-date-section-$thirdDate')),
        findsOneWidget);
    expect(find.byKey(Key('feeding-date-section-$fourthDate')),
        findsOneWidget);

    await harness.selectGrams(tester, thirdDate, 0, '25 grams');
    await harness.saveEditor(tester);

    expect(harness.feeding.creates, hasLength(1));
    final drafts = harness.feeding.creates.single;
    expect(drafts.map((d) => d.feedDate),
        orderedEquals([thirdDate, fourthDate]));
    expect(drafts.map((d) => d.time), orderedEquals(['08:00', '08:00']));
    expect(drafts.map((d) => d.grams), orderedEquals([25, 10]));
    expect(harness.feeding.updates, isEmpty);
    expect(harness.feeding.deletes, isEmpty);
  });

  testWidgets('another device schedule is hidden and cannot block a save',
      (tester) async {
    await harness.pump(
      tester,
      extraSchedules: [
        FeedingSchedule(
          id: 'other-1',
          deviceId: 'other-device',
          feedDate: thirdDate,
          time: '08:00',
          grams: 5,
          rotatorPwm: 255,
          active: true,
        ),
      ],
    );

    expect(find.byKey(Key('feeding-overview-group-$thirdDate')),
        findsNothing,
        reason: 'another device must not appear in the overview');
    expect(find.text(thirdDate), findsNothing);

    await harness.tapKey(tester, const Key('feeding-choose-dates'));
    await tester.tap(find.byKey(const Key('feeding-mode-multiple')));
    await tester.pumpAndSettle();
    await navigateCalendarMonth(tester, thirdDate);
    await tester.tap(find.byKey(Key('feeding-day-$thirdDate')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('feeding-calendar-confirm')));
    await tester.pumpAndSettle();
    expect(find.byKey(Key('feeding-date-section-$thirdDate')),
        findsOneWidget);
    await harness.saveEditor(tester);

    expect(harness.feeding.creates, hasLength(1),
        reason: 'a different device must not block the save at 08:00');
    expect(harness.feeding.creates.single.single.feedDate, thirdDate);
    expect(harness.feeding.creates.single.single.time, '08:00');
  });

  testWidgets('an overview row toggle pauses that schedule', (tester) async {
    await harness.pump(tester);

    await harness.tapKey(tester, const Key('feeding-overview-toggle-a1'));

    expect(harness.feeding.toggles, [
      (id: 'a1', active: false),
    ], reason: 'a1 starts active, so the switch must turn it off');
  });

  testWidgets('a paused row is dimmed while an active row is not',
      (tester) async {
    await harness.pump(
      tester,
      extraSchedules: [
        FeedingSchedule(
          id: 'paused',
          feedDate: firstDate,
          time: '12:00',
          grams: 10,
          rotatorPwm: 255,
          active: false,
        ),
      ],
    );

    expect(
      tester
          .widget<AnimatedOpacity>(
            find.byKey(const Key('feeding-overview-row-paused')),
          )
          .opacity,
      0.55,
    );
    expect(
      tester
          .widget<AnimatedOpacity>(
            find.byKey(const Key('feeding-overview-row-a1')),
          )
          .opacity,
      1.0,
    );
  });

  testWidgets('no row toggle is available while no device is paired',
      (tester) async {
    await harness.pump(tester);
    harness.device.deviceId = null;
    harness.device.notifyListeners();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('feeding-overview-toggle-a1')), findsNothing);
  });

  testWidgets('empty Save is disabled and creates nothing', (tester) async {
    await harness.pump(tester);
    await harness.chooseDates(tester, [thirdDate]);
    await tester.tap(find.byKey(Key('feeding-remove-feed-$thirdDate-0')));
    await tester.pumpAndSettle();

    final save = find.byKey(const Key('feeding-date-editor-save'));
    expect(tester.widget<ElevatedButton>(save).onPressed, isNull);
    await harness.saveEditor(tester);

    expect(harness.feeding.creates, isEmpty);
    expect(find.byKey(const Key('feeding-date-editor-save')), findsOneWidget);
  });

  testWidgets('empty Save cannot silently delete a date group',
      (tester) async {
    await harness.pump(tester);
    await harness.openEditor(tester, firstDate);
    await tester.tap(find.byKey(Key('feeding-remove-feed-$firstDate-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('feeding-remove-feed-$firstDate-0')));
    await tester.pumpAndSettle();

    final save = find.byKey(const Key('feeding-date-editor-save'));
    expect(tester.widget<ElevatedButton>(save).onPressed, isNull);
    await harness.saveEditor(tester);

    expect(harness.feeding.updates, isEmpty);
    expect(harness.feeding.deletes, isEmpty);
    expect(find.byKey(const Key('feeding-date-editor-save')), findsOneWidget);
  });

  testWidgets('Convert to date rewrites the legacy group with that date',
      (tester) async {
    await harness.pump(tester);

    await harness.tapKey(
        tester, const Key('feeding-overview-convert-every-day'));
    expect(find.byKey(const Key('feeding-calendar-confirm')), findsOneWidget,
        reason: 'the calendar did not open');
    await navigateCalendarMonth(tester, convertDate);
    await tester.tap(find.byKey(Key('feeding-day-$convertDate')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('feeding-calendar-confirm')));
    await tester.pumpAndSettle();

    expect(harness.feeding.updates, hasLength(1));
    final call = harness.feeding.updates.single;
    expect(call.date, convertDate);
    expect(call.original.map((s) => s.id), orderedEquals(['legacy-1']));
    expect(call.edited.single.feedDate, convertDate);
  });

  testWidgets('legacy every-day Edit keeps feed_date null on save',
      (tester) async {
    await harness.pump(tester);
    await harness.openEditor(tester, everyDayKey);

    expect(find.byKey(const Key('feeding-date-section-$everyDayKey')),
        findsOneWidget);
    await harness.selectGrams(tester, everyDayKey, 0, '25 grams');
    await harness.saveEditor(tester);

    expect(harness.feeding.updates, hasLength(1));
    final call = harness.feeding.updates.single;
    expect(call.date, isNull);
    expect(call.original.map((s) => s.id), orderedEquals(['legacy-1']));
    expect(call.edited.single.feedDate, isNull);
    expect(call.edited.single.grams, 25);
  });

  testWidgets('a failed create shows a failure and no success message',
      (tester) async {
    harness.feeding.failWrite = 'create';
    await harness.pump(tester);
    await harness.chooseDates(tester, [thirdDate]);
    await harness.saveEditor(tester);

    expect(find.textContaining('Could not save feeds'), findsOneWidget);
    expect(find.textContaining('Added '), findsNothing);
  });

  testWidgets('a failed group edit shows a failure message', (tester) async {
    harness.feeding.failWrite = 'update';
    await harness.pump(tester);
    await harness.openEditor(tester, firstDate);
    await harness.saveEditor(tester);

    expect(find.textContaining('Could not update feeds'), findsOneWidget);
  });

  testWidgets('a failed conversion shows a failure message', (tester) async {
    harness.feeding.failWrite = 'update';
    await harness.pump(tester);
    await harness.convertEveryDay(tester, convertDate);

    expect(find.textContaining('Could not convert the date'), findsOneWidget);
  });

  testWidgets('a failed delete shows a failure message', (tester) async {
    harness.feeding.failWrite = 'delete';
    await harness.pump(tester);

    await harness.tapKey(
        tester, Key('feeding-overview-delete-$firstDate'));

    expect(find.textContaining('Could not delete the date'), findsOneWidget);
  });

  testWidgets('a failed toggle shows a failure message', (tester) async {
    harness.feeding.failWrite = 'toggle';
    await harness.pump(tester);

    await harness.tapKey(tester, const Key('feeding-overview-toggle-a1'));

    expect(find.textContaining('Could not update this feed'), findsOneWidget);
  });
}

/// One group edit captured by the fake provider.
class UpdateCall {
  const UpdateCall(this.date, this.original, this.edited);

  final String? date;
  final List<FeedingSchedule> original;
  final List<FeedingDraft> edited;
}

/// Stubs every write the new UI can make, and keeps the schedules in memory
/// so each test starts from the same three groups. [failWrite] makes one
/// write kind throw so the UI error path can be exercised.
class FakeFeedingProvider extends LocalFeedingProvider {
  FakeFeedingProvider(SupabaseClient client) : super(client: client);

  final List<UpdateCall> updates = [];
  final List<Set<String>> deletes = [];
  final List<List<FeedingDraft>> creates = [];
  final List<({String id, bool active})> toggles = [];

  String? failWrite;

  @override
  Future<void> fetchSchedules() async {}

  @override
  Future<void> createSchedules(String deviceId, List<FeedingDraft> drafts) async {
    creates.add(List<FeedingDraft>.unmodifiable(drafts));
    if (failWrite == 'create') throw Exception('simulated write failure');
  }

  @override
  Future<void> updateScheduleGroup(
    String deviceId,
    String? date,
    List<FeedingSchedule> original,
    List<FeedingDraft> edited,
  ) async {
    updates.add(UpdateCall(
      date,
      List<FeedingSchedule>.unmodifiable(original),
      List<FeedingDraft>.unmodifiable(edited),
    ));
    if (failWrite == 'update') throw Exception('simulated write failure');
  }

  @override
  Future<void> deleteSchedules(Set<String> ids) async {
    deletes.add(Set<String>.unmodifiable(ids));
    if (failWrite == 'delete') throw Exception('simulated write failure');
  }

  @override
  Future<void> toggleSchedule(String id, bool active) async {
    toggles.add((id: id, active: active));
    if (failWrite == 'toggle') throw Exception('simulated write failure');
  }
}

class _FeedingHarness {
  late FakeFeedingProvider feeding;
  late DeviceProvider device;

  void reset() {
    feeding = FakeFeedingProvider(
      SupabaseClient('http://localhost:54321', 'test-key'),
    );
    device = DeviceProvider();
  }

  Future<void> pump(
    WidgetTester tester, {
    List<FeedingSchedule> extraSchedules = const [],
  }) async {
    final today = DateTime.parse(deviceTodayDate());
    feeding.schedules = [
      FeedingSchedule(
        id: 'a1',
        feedDate: _futureDate(today, 2),
        time: '08:00',
        grams: 15,
        rotatorPwm: 255,
        active: true,
      ),
      FeedingSchedule(
        id: 'a2',
        feedDate: _futureDate(today, 2),
        time: '10:00',
        grams: 15,
        rotatorPwm: 255,
        active: true,
      ),
      FeedingSchedule(
        id: 'b1',
        feedDate: _futureDate(today, 3),
        time: '09:00',
        grams: 10,
        rotatorPwm: 128,
        active: true,
      ),
      const FeedingSchedule(
        id: 'legacy-1',
        time: '07:30',
        grams: 20,
        rotatorPwm: 255,
        active: true,
      ),
      ...extraSchedules,
    ];
    device.deviceId = 'device-1';

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<LocalFeedingProvider>.value(value: feeding),
          ChangeNotifierProvider<DeviceProvider>.value(value: device),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: LocalFeedingSection()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The section is tall, so overview controls need scrolling into view
  /// before the pointer can hit them in a test viewport.
  Future<void> tapKey(WidgetTester tester, Key key) async {
    final finder = find.byKey(key);
    expect(finder, findsOneWidget, reason: 'no widget for $key');
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> openEditor(WidgetTester tester, String date) async {
    await tapKey(tester, Key('feeding-overview-edit-$date'));
    expect(find.byKey(Key('feeding-date-section-$date')), findsOneWidget,
        reason: 'the editor did not open for $date');
  }

  Future<void> chooseDates(WidgetTester tester, List<String> dates) async {
    await tapKey(tester, const Key('feeding-choose-dates'));
    expect(find.byKey(const Key('feeding-calendar-confirm')), findsOneWidget,
        reason: 'the calendar did not open');
    for (final date in dates) {
      await navigateCalendarMonth(tester, date);
      await tester.tap(find.byKey(Key('feeding-day-$date')));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byKey(const Key('feeding-calendar-confirm')));
    await tester.pumpAndSettle();
  }

  Future<void> convertEveryDay(WidgetTester tester, String date) async {
    await tapKey(tester, const Key('feeding-overview-convert-every-day'));
    expect(find.byKey(const Key('feeding-calendar-confirm')), findsOneWidget,
        reason: 'the calendar did not open');
    await navigateCalendarMonth(tester, date);
    await tester.tap(find.byKey(Key('feeding-day-$date')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('feeding-calendar-confirm')));
    await tester.pumpAndSettle();
  }

  Future<void> selectGrams(
    WidgetTester tester,
    String date,
    int index,
    String label,
  ) async {
    await tester.tap(find.byKey(Key('feeding-feed-grams-$date-$index')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  Future<void> saveEditor(WidgetTester tester) async {
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
