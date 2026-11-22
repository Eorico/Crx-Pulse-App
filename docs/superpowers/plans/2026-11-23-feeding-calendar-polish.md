# Feeding Calendar Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restyle the feeding date picker into the approved “Refined Clay” direction with functional quick picks, a segmented mode control, a range ribbon, and a clearer summary, without changing date logic.

**Architecture:** All changes stay in `lib/widgets/feeding_calendar.dart`; its public `showFeedingCalendar` signature and returned `List<String>` are unchanged. Existing state (`_selected`, `_mode`, `_rangeStart`, `_pages`) keeps driving behavior; the new UI is a presentation layer over that state, plus three quick-pick shortcuts that write the same state.

**Tech Stack:** Flutter / Dart, Material 3, existing `AppColors`, `AppShadows`, `AppRadius`, `AppMotion`, `PressableScale`. No new package.

**Spec:** `docs/superpowers/specs/2026-11-23-feeding-calendar-polish-design.md`

## Global Constraints

- Keep the app’s existing green/beige palette and clay shadow tokens; do not introduce new colors or a new package.
- Device-today remains UTC+8 via `deviceTodayDate(now: widget.now)`; past dates stay disabled; future dates unbounded.
- `showFeedingCalendar(BuildContext, {DateTime? now, List<String> selected, FeedingCalendarMode initialMode})` signature is unchanged.
- Existing keys `feeding-calendar-confirm`, `feeding-calendar-cancel`, `feeding-mode-single`, `feeding-mode-multiple`, `feeding-mode-range`, and `feeding-day-YYYY-MM-DD` must keep working.
- `_selected` remains an explicit sorted `List<String>` of `YYYY-MM-DD` keys; no new data model.
- Only `lib/widgets/feeding_calendar.dart` and `test/feeding_calendar_test.dart` change.

## Review Focus

- Quick pick replaces an existing selection instead of appending to it — pinned by `quick pick replaces the existing selection` in Task 1.
- “Next 7 days” crosses a month boundary and still yields seven consecutive dates — pinned by `next 7 days crosses the month boundary` in Task 1.
- Range selection across a month boundary returns every day — pinned by `range mode returns every day across a month boundary` in Task 1.
- Today marker appears only on the UTC+8 today — pinned by `today marker appears only on the device-today cell` in Task 2.
- Empty selection shows a clear summary and keeps Confirm disabled — pinned by `empty selection shows a summary and disables Confirm` in Task 2.

---

### Task 1: Quick picks and segmented mode control

**Files:**
- Modify: `lib/widgets/feeding_calendar.dart`
- Test: `test/feeding_calendar_test.dart`

**Interfaces:**
- Consumes: `_today`, `_selected`, `_mode`, `_changeMode(FeedingCalendarMode)`, `_selectDay(String)`, `deviceTodayDate(now:)`.
- Produces: keys `feeding-quick-today`, `feeding-quick-tomorrow`, `feeding-quick-next-7`; mode keys `feeding-mode-single`, `feeding-mode-multiple`, `feeding-mode-range` preserved by wrapping each `ButtonSegment` label in `KeyedSubtree`.

- [ ] **Step 1: Write the failing tests**

Add to `test/feeding_calendar_test.dart`, using the existing `_CalendarHarness`:

```dart
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
```

Note: add an optional `now` parameter to `_CalendarHarness.open` so the cross-month test can control device-today; default remains `DateTime.utc(2026, 10, 22, 16, 30)`.

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/feeding_calendar_test.dart`
Expected: FAIL with “No widgets found with key: feeding-quick-today” (and the cross-month range failure if the pager does not expose the day).

- [ ] **Step 3: Implement quick picks and the segmented control**

In `lib/widgets/feeding_calendar.dart`:

- Add `Widget _buildQuickPicks()` above `_buildModeSelector()` in the build column. It renders three `ActionChip`s with keys `feeding-quick-today`, `feeding-quick-tomorrow`, `feeding-quick-next-7`, styled with `AppColors.surface`/`AppColors.primary.withValues(alpha: 0.12)` and `AppRadius.chip`.
- Add `void _applyQuickPick(int days)` that computes dates from `_parseDay(_today)` using `DateTime.utc(...)`, formats them with `_formatDay`, filters out anything before `_today`, and sets state atomically:
  - `days == 1` → `_mode = single`, `_selected = [date]`, `_rangeStart = null`.
  - `days == 2` → `_mode = single`, `_selected = [tomorrow]`, `_rangeStart = null`.
  - `days == 7` → `_mode = range`, `_selected = seven dates`, `_rangeStart = null`.
  - Also animate `_pages` to the page of the first selected date when it differs from `_page`.
- Replace the three `ChoiceChip`s in `_buildModeSelector()` with `SegmentedButton<FeedingCalendarMode>`. Wrap each segment label in `KeyedSubtree(key: Key('feeding-mode-${mode.name}'), child: Text(_modeLabel(mode)))` so existing key-based tests keep working. Keep `onSelectionChanged: (values) => _changeMode(values.first)`.
- Keep `_modeLabel` unchanged (`Single`, `Multiple`, `Range`).

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/feeding_calendar_test.dart`
Expected: PASS, including the five pre-existing calendar tests.

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/feeding_calendar.dart test/feeding_calendar_test.dart
git commit -m "feat: add calendar quick picks and segmented mode control"
```

### Task 2: Range ribbon, today marker, and summary polish

**Files:**
- Modify: `lib/widgets/feeding_calendar.dart`
- Test: `test/feeding_calendar_test.dart`

**Interfaces:**
- Consumes: `_selected`, `_today`, `_mode`, `_isPast(String)`, `_formatDay(DateTime)`, `_page`, `_monthNames`.
- Produces: keys `feeding-calendar-today-marker` and `feeding-calendar-summary`; no public API change.

- [ ] **Step 1: Write the failing tests**

```dart
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

  expect(find.byKey(const Key('feeding-calendar-today-marker')), findsOneWidget);
  final markerParent = tester.ancestor(
    find.byKey(const Key('feeding-calendar-today-marker')),
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/feeding_calendar_test.dart`
Expected: FAIL for the new summary/marker keys.

- [ ] **Step 3: Implement the visual polish**

In `lib/widgets/feeding_calendar.dart`:

- `_buildHeader`: keep the close button and title, change the subtitle to an uppercase `DEVICE TIME · UTC+8` badge using `AppColors.primary` on `AppColors.primary.withValues(alpha: 0.10)` with `AppRadius.chip`.
- `_buildDay`: introduce `BoxDecoration _dayDecoration(String date, bool past, bool selected)`.
  - Single mode selected → `AppColors.primary`, circular `BorderRadius.circular(21)`, `AppShadows.claySoft`.
  - Multiple/range selected → pale `AppColors.primary.withValues(alpha: 0.16)` fill; when the day is the first or last selected date, use darker `AppColors.primary` fill with white text and rounded end caps; interior days keep `AppColors.primaryDark` text. Determine first/last from `_selected.first`/`_selected.last` only when `_mode != single`.
  - Past → `AppColors.background`, muted text, no shadow.
  - Unselected future → `AppColors.surface` with `AppShadows.claySoft`.
  - Increase cell height from `42` to `46` and keep `PressableScale` + Semantics + `Key('feeding-day-$date')`.
- Add a 5px dot below the day number when `date == _today`, wrapped in `KeyedSubtree(key: const Key('feeding-calendar-today-marker'), child: ...)`. Remove the underline decoration from the day text.
- `_buildFooter`: wrap the summary `Text` in `KeyedSubtree(key: const Key('feeding-calendar-summary'), child: Text(_selectionSummary(), ...))`. Keep the existing `_selectionSummary()` strings but change the single-date case to `1 date selected · ${_selected.first}` (already present) and the range case to `${_selected.length} days · ${_selected.first} – ${_selected.last}` (already present).
- Do not change `_confirm`, `_selectDay`, `_changeMode`, or any numeric date logic.

- [ ] **Step 4: Run targeted tests**

Run: `flutter test test/feeding_calendar_test.dart`
Expected: PASS.

- [ ] **Step 5: Full verification**

Run: `flutter test`
Expected: `All tests passed!`

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add lib/widgets/feeding_calendar.dart test/feeding_calendar_test.dart
git commit -m "feat: polish feeding calendar range ribbon and summary"
```

## Self-Review

- Spec coverage: header badge → Task 2 Step 3; quick picks → Task 1 Steps 1/3; segmented control → Task 1 Step 3; range ribbon → Task 2 Steps 1/3; today marker → Task 2 Steps 1/3; sticky summary → Task 2 Steps 1/3; no logic/API changes → Global Constraints and Task 2 Step 3.
- Step scan: each step produces one test, one failing run, one implementation, one passing run, or one commit.
- Type consistency: all new keys are literal strings matching test finders; `_selectionSummary()` still returns `String`; `showFeedingCalendar` unchanged.
- Review Focus: all five listed inputs have a named test in Task 1 or Task 2.
- Proportion: plan is shorter than the widget it modifies; no full widget bodies are transcribed.
