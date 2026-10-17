import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crx_pulse/core/theme.dart';

/// Regression tests for the feeding time selector looking broken.
///
/// Cause: the app's global [InputDecorationTheme] is a borderless,
/// filled, large-radius "well" meant for form fields. The Material time
/// picker builds its hour and minute boxes out of `InputDecorator`, so
/// it inherited that styling — losing its own shape and fill, and
/// getting 18px of content padding around numbers already sized to fill
/// their box.
///
/// [AppTheme.timePickerBuilder] resets `inputDecorationTheme` for the
/// dialog and themes the picker explicitly instead. These assert that
/// the reset is actually in force, that the explicit theme is applied,
/// and that the dialog lays out without overflowing.
void main() {
  /// Opens a time picker inside the real app theme. [builder] is the
  /// `showTimePicker(builder:)` under test — null reproduces the old,
  /// unfixed behaviour.
  Future<void> openPicker(
    WidgetTester tester, {
    required Widget Function(BuildContext, Widget?)? builder,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showTimePicker(
                  context: context,
                  initialTime: const TimeOfDay(hour: 8, minute: 0),
                  initialEntryMode: TimePickerEntryMode.dial,
                  builder: builder,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('picker opens and lays out with no overflow', (tester) async {
    await openPicker(tester, builder: AppTheme.timePickerBuilder);

    expect(tester.takeException(), isNull);
    // Dial mode shows the hour and minute, and the two actions.
    expect(find.text('08'), findsWidgets);
    expect(find.text('00'), findsWidgets);
    expect(find.text('OK'), findsOneWidget);
  });

  testWidgets('the app InputDecorationTheme does not reach the picker',
      (tester) async {
    await openPicker(tester, builder: AppTheme.timePickerBuilder);

    // Inside the dialog, the effective InputDecorationTheme must be the
    // plain default — not the app's filled, borderless well. `filled`
    // is the single clearest marker: the app sets it true, the default
    // is false.
    final dialogContext = tester.element(find.text('OK'));
    final decoration = Theme.of(dialogContext).inputDecorationTheme;

    expect(decoration.filled, isFalse,
        reason: "the app's filled field styling is leaking into the "
            'time picker, which is what mangled the hour/minute boxes');
    expect(decoration.fillColor, isNull);

    // And confirm the leak is real outside the dialog — otherwise this
    // test would pass even if the reset were removed.
    expect(AppTheme.light().inputDecorationTheme.filled, isTrue,
        reason: 'the app theme is expected to fill its form fields; if it '
            'no longer does, the reset above may be unnecessary');
  });

  testWidgets('picker is themed deliberately, not left to defaults',
      (tester) async {
    await openPicker(tester, builder: AppTheme.timePickerBuilder);

    final dialogContext = tester.element(find.text('OK'));
    final picker = Theme.of(dialogContext).timePickerTheme;

    expect(picker.hourMinuteColor, AppTheme.hourMinuteFill);
    expect(picker.dialHandColor, AppColors.primary);
  });

  testWidgets('24-hour entry, matching the HH:MM the firmware compares',
      (tester) async {
    await openPicker(tester, builder: AppTheme.timePickerBuilder);

    final dialogContext = tester.element(find.text('OK'));
    expect(MediaQuery.of(dialogContext).alwaysUse24HourFormat, isTrue);
    // No AM/PM toggle in 24h mode — entering 8 PM as "08" would store a
    // time the device never reaches.
    expect(find.text('AM'), findsNothing);
    expect(find.text('PM'), findsNothing);
  });
}
