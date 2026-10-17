# CRX-Pulse — Claymorphism restyle (palette unchanged)

Claymorphism = soft, inflated, borderless surfaces with a two-tone shadow
(a diffuse dark shadow bottom-right + a light highlight top-left) and large
rounded corners. This patch applies that language **through the shared
design tokens**, so it propagates across the whole app without rewriting
every screen. **No colors changed** — `AppColors` is byte-for-byte the same
sage-green / beige palette.

## Files (drop into `lib/`, replacing the same paths)

| File | Change |
|---|---|
| `core/theme.dart` | **Rewritten.** `AppShadows.card` is now the two-tone clay shadow, so every surface already using it becomes clay automatically. Adds `AppShadows.clay/claySoft/clayPressed`, `AppRadius`, and `AppColors.clayFill`. Cards go borderless + radius 26; buttons rounder with a soft green lift; inputs become soft filled wells; dialogs/snackbars rounder. All existing symbols (`AppColors`, `AppShadows.card`, `DeviceStatus*`, `SystemStatusStyle`, `AppTheme`) are preserved. |
| `widgets/clay_container.dart` | **New.** A reusable `ClayContainer` clay panel (raised / `pressed` / `soft`) for any custom-decoration spot. |
| `widgets/floating_bottom_nav.dart` | **Rewritten.** The frosted-glass bar becomes a cream clay pill with the clay shadow; the active tab is a raised green clay disc. Same API and behaviour. |

## What restyles automatically (no edits needed)

Anything that already uses `AppShadows.card` or the themed widgets now reads
as clay: the Management sensor cards, feeding cards, Home summary/range
cards, Device Setup cards, all `ElevatedButton`s, text fields, dialogs, and
snackbars — plus the new clay bottom nav.

## Optional: make the Home hero card clay too

The green "STATUS" hero on Home builds its own `BoxDecoration` with no
shadow, so it stays flat next to its clay siblings. To match, wrap its
contents in `ClayContainer` (import `../../widgets/clay_container.dart`):

```dart
ClayContainer(
  color: AppColors.primary,
  borderRadius: 28,
  padding: const EdgeInsets.all(20),
  child: Row( ... existing hero row ... ),
)
```

(Left as a one-line opt-in rather than editing the Home screen here.)

## Apply order

Layer this **on top of** the 2b Flutter patch — the two don't overlap
(`floating_bottom_nav.dart` isn't in 2b; `theme.dart` wasn't touched by 2b).
Then `flutter analyze` once and run. Not compiler-verified here (no Flutter
toolchain in the authoring environment), so expect to eyeball spacing on a
device and nudge shadow offsets in `AppShadows` to taste.
