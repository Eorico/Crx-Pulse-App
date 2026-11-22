# Feeding Calendar Polish — Design

Date: 2026-11-23

## Intent

The date picker works, but its current look is functional rather than considered: flat day tiles, loose floating mode chips, an underlined “today”, and a thin footer. The user asked for a more professional, friendlier feel and chose the **Refined Clay** direction in the visual brainstorm.

## Goals

- Keep the app’s existing green/beige clay identity; improve hierarchy and polish, not replace the design language.
- Make selection state immediately legible, especially for ranges and multi-date picks.
- Reduce the number of taps for common choices with real quick-pick shortcuts.
- Preserve all existing date logic, return values, widget keys, and tests.

## Non-goals

- No Supabase, model, or scheduling-logic changes.
- No new package or dependency.
- No changes to the date editor or overview screens.
- No firmware or database work.

## Anti-goals

- A generic Material date picker dropped into the app — it would fight the clay styling.
- Adding so much information that the calendar feels like a dashboard instead of a date choice.
- Adding colorful status semantics that could be mistaken for feeding state.

## Constraints

- Flutter + Material 3, existing `AppColors`, `AppShadows`, `AppRadius`, `AppMotion`, `PressableScale`.
- Device-today is UTC+8; past dates stay disabled; future dates unbounded.
- Existing tests locate widgets by keys like `feeding-calendar-confirm`, `feeding-mode-*`, and `feeding-day-*`; those must keep working.
- Implementation stays inside `lib/widgets/feeding_calendar.dart` and its existing test file.

## Approaches considered

1. **Refined Clay (chosen).** Keep the clay surfaces and palette, add quick-pick chips, a segmented mode control, a continuous selected-range ribbon, a clearer today marker, and a sticky summary footer. Best fit: feels intentionally designed without abandoning the app’s identity. Costs a moderate rewrite of the calendar build methods.
2. **Clean Editorial.** White, thin-ruled, single-accent scheduling-tool look. More neutral and “professional” in a corporate sense, but it would read as a different app inside the clay UI. Rejected by the user.
3. **Planner Pro.** Month grid plus a selected-dates side rail. Most informative, but denser than this simple choice needs and harder on a phone-width screen. Rejected by the user.

## Chosen design

- **Header:** clear “Select dates” title, small “Device time · UTC+8” badge, close button unchanged.
- **Quick picks:** functional chips for **Today**, **Tomorrow**, **Next 7 days**. Tapping one replaces the current selection with that date set and switches to the mode that best represents it (single for one day, multiple/ranges for the 7-day set as appropriate). Past dates are never produced.
- **Mode control:** Single / Multiple / Range as a segmented control replacing the three separate `ChoiceChip`s. Keys remain `feeding-mode-single`, `feeding-mode-multiple`, `feeding-mode-range`.
- **Month navigation:** same behavior, tighter vertical rhythm, stronger month/year typography.
- **Day grid:** slightly larger tap targets; selected days render as a continuous range ribbon in multiple/range modes — pale green fill through the middle, darker rounded end caps; single selections remain a solid green circle. Today gets a small dot/ring instead of an underline. Past days are muted but clearly disabled.
- **Footer:** sticky summary with count and first/last date when useful; Confirm stays disabled on empty selection. Keys unchanged.
- **Motion:** existing `AppMotion` durations only; no new animation package. Respect reduced-motion through the app’s existing `PressableScale` behavior.

## Builder calls already made

- Quick-pick chips are functional, not decorative.
- Range ribbon is purely visual; `_selected` remains an explicit list of date strings.
- No new public API: `showFeedingCalendar` signature is unchanged.
- New widget tests cover the quick picks and the range-ribbon selection state; existing tests must stay green.

## Left to the implementation plan

Exact widget decomposition inside `feeding_calendar.dart`, the test cases to add, and the verification commands.
