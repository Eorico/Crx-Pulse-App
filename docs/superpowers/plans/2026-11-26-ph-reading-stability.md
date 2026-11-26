# pH Reading Stability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop the live pH value from flickering to 9–10 by rejecting jumps that the next reading does not confirm.

**Architecture:** A stateful pure helper holds the last accepted pH and one pending candidate. `LocalEsp32Service` applies it where the `ph` field is assigned, so every consumer (card, alerts, analytics, cache) sees the same filtered value. No new dependencies.

**Tech Stack:** Dart, Flutter, flutter_test.

**Spec:** `docs/superpowers/specs/2026-11-26-ph-reading-stability-design.md`

## Global Constraints

- No new dependencies.
- Do not touch `hardware/.../secrets.h` or any secret file.
- Leave the existing uncommitted notification-detail changes untouched.
- Do not stage or commit unless asked.
- Filtering must not hide a genuinely unsafe pH once two consecutive readings agree.

## Review Focus

- One-off spike 7 → 10 → 7: value stays at 7 throughout. Test in Task 1, `single spike is held`.
- Two consecutive high readings 7 → 10 → 10.1: 10.1 is accepted after the second. Test in Task 1, `confirmed jump is accepted`.
- Ordinary drift 7 → 7.3: passes on the first reading. Test in Task 1, `small drift passes immediately`.
- First reading after a clear/disconnect is a large value: accepted immediately, not held. Test in Task 1, `reset makes the next reading authoritative`.
- Null / NaN / infinity: value becomes null and filter state resets. Test in Task 1, `non-finite reading clears state`.

---

### Task 1: pH jump filter helper

**Files:**
- Create: `lib/core/ph_reading_filter.dart`
- Test: `test/ph_reading_filter_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: `class PhReadingFilter` with `static const double maxImmediateChange = 0.5`, `double? accept(double? reading)`, and `void reset()`.

- [ ] **Step 1: Write the failing tests**

Create `test/ph_reading_filter_test.dart` with these cases:

```dart
test('single spike is held', () {
  final f = PhReadingFilter();
  expect(f.accept(7.0), 7.0);
  expect(f.accept(10.0), 7.0);
  expect(f.accept(7.1), 7.1);
});
test('confirmed jump is accepted', () {
  final f = PhReadingFilter();
  expect(f.accept(7.0), 7.0);
  expect(f.accept(10.0), 7.0);
  expect(f.accept(10.1), closeTo(10.1, 0.0001));
});
test('small drift passes immediately', () {
  final f = PhReadingFilter();
  expect(f.accept(7.0), 7.0);
  expect(f.accept(7.3), 7.3);
});
test('reset makes the next reading authoritative', () {
  final f = PhReadingFilter();
  expect(f.accept(7.0), 7.0);
  expect(f.accept(10.0), 7.0);
  f.reset();
  expect(f.accept(10.0), 10.0);
});
test('non-finite reading clears state', () {
  final f = PhReadingFilter();
  expect(f.accept(7.0), 7.0);
  expect(f.accept(double.nan), isNull);
  expect(f.accept(10.0), 10.0);
  expect(f.accept(double.infinity), isNull);
  expect(f.accept(7.5), 7.5);
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/ph_reading_filter_test.dart`
Expected: compile failure — `PhReadingFilter` is not defined.

- [ ] **Step 3: Implement `PhReadingFilter`**

In `lib/core/ph_reading_filter.dart`, hold `_accepted` and `_candidate` as nullable doubles. `accept` rules:
- null, NaN or infinite → `reset()`, return null;
- no accepted value → accept and return the reading;
- change from accepted `<= maxImmediateChange` → accept and return the reading, clearing the candidate;
- otherwise store the reading as candidate and return the accepted value; if a candidate already exists and the new reading is within `maxImmediateChange` of it, accept the new reading and clear the candidate.

`reset()` clears both fields.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/ph_reading_filter_test.dart`
Expected: PASS, all 5 cases.

### Task 2: Apply the filter at reading ingestion

**Files:**
- Modify: `lib/services/local_esp32_service.dart` (add field near line 66; change the `ph` assignment at line 539; add a reset call in `_clearReadings` at lines 164–175)

**Interfaces:**
- Consumes: `PhReadingFilter` from Task 1.
- Produces: no new public API; `LocalEsp32Service.ph` is now the filtered value.

- [ ] **Step 1: Add the filter field and wire it in**

Add a `final PhReadingFilter _phFilter = PhReadingFilter();` field. In `_onRows`, replace `ph = ok('ph_valid') ? asNum('ph') : null;` with a local `rawPh` followed by `ph = _phFilter.accept(rawPh);`. In `_clearReadings`, call `_phFilter.reset()`.

- [ ] **Step 2: Verify the whole suite**

Run: `flutter analyze` → `No issues found!`
Run: `flutter test` → all tests pass (181 existing + 5 new).

- [ ] **Step 3: Restore generated files and check the diff**

Flutter commands rewrite `linux/flutter/generated_plugin_registrant.cc`, `linux/flutter/generated_plugin_registrant.h`, `linux/flutter/generated_plugins.cmake`, `macos/Flutter/GeneratedPluginRegistrant.swift`, `windows/flutter/generated_plugin_registrant.cc`, `windows/flutter/generated_plugin_registrant.h`, `windows/flutter/generated_plugins.cmake`. Restore only those with `git checkout -- <paths>`. Then run `git status --short` and `git diff --check`; expected: only intended files changed, no whitespace errors.
