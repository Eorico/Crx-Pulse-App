# CRX-Pulse — mobile app

Flutter app for the CRX-Pulse crayfish aquaculture monitor.

```
ESP32  ->  WiFi router  ->  Supabase (Postgres + PostgREST + Realtime)  ->  this app
```

There is no backend server. The ESP32 inserts readings straight into the
`readings` table and this app subscribes to them live; feeding schedules
and one-shot commands are plain rows the app writes and the device reads.

## Run it

```bash
flutter pub get
flutter run
```

Supabase URL and anon key are in `lib/core/supabase_config.dart`. The
anon key is meant to be public — Row Level Security (`supabase/supabase_schema.sql`)
is what protects the data.

> **Re-run `supabase/supabase_schema.sql` before running this build.** It
> adds the `device_logs` table and the `commands.value`,
> `commands.rotator_pwm` and `schedules.rotator_pwm` columns that Test
> Components and the rotator-speed selector need. The script is
> idempotent, so running it again on an existing project is safe.

## Layout

| Path | What lives there |
|---|---|
| `lib/core/firmware_spec.dart` | **The app's mirror of the firmware's constants.** Cooling-fan curve, turbidity calibration and bands, ammonia bands, feed doses, cloud cadence. |
| `lib/core/fan_speed_util.dart` | The firmware's cooling ramp, for when real fan telemetry has not arrived yet. |
| `lib/core/theme.dart` | Palette, Claymorphism shadow tokens, radii, `ThemeData`. |
| `lib/widgets/motion.dart` | **The motion system.** Durations, curves, and the reusable animations every screen uses. |
| `lib/services/` | Supabase-backed providers (live readings, device pairing, feeding, auth, device log, component tests) plus the local SQLite history. |
| `lib/screens/` | One folder per tab, plus `auth/` and `splash/`. |

## Test Components (Settings tab)

Settings holds a live view of the ESP32's serial output and direct
controls for the feeder servo and the DC rotator.

**The phone has no serial or USB link to the board.** It reaches the
device only through Supabase, so "show the serial output" is implemented
as: the firmware mirrors every line it prints into `device_logs`, and
`DeviceLogProvider` subscribes to that table. The console shows the same
text a serial monitor would.

Volume is managed rather than unbounded:

- **Event lines** (feeds, commands, schedules, WiFi changes, errors) are
  always mirrored, so there is history waiting when you open the screen.
- **Verbose lines** (the sensor block, printed every 2 s) flow only while
  the screen is open. It sends a `log_stream` command on open, renews it
  every 2 minutes, and switches it off on dispose; the device also lets
  it lapse by itself after 5 minutes.

`device_logs` is the one table that grows without bound — see the
retention notes at the bottom of `supabase/supabase_schema.sql`.

The servo and motor controls queue `commands` rows like everything else,
so the device acts on them at its next poll (~5 s) rather than instantly.
Both actuators are bounded **by the firmware**: a test-opened door
force-closes after 10 s and a test-driven motor stops after 30 s. That is
deliberate — an open feeder door keeps dropping feed, and neither should
keep running because somebody closed the app.

## Keeping the app and the firmware in step

Anything the device decides — when the fan runs, what counts as "Turbid",
which feed doses exist, how often a reading arrives — is written down once
in `lib/core/firmware_spec.dart`, copied from
`hardware/crx_pulse_dev/crx_pulse/crx_pulse.ino`.

**If you change one of those constants in the `.ino`, change it in
`firmware_spec.dart` too.** Both files say so at the top. Screens must read
from `FirmwareSpec` rather than writing their own literal, which is how the
two drifted apart before: the app was drawing a fan curve from an older
firmware revision, and labelling ammonia "ppm" and turbidity "NTU" when the
device sends mg/L and a percentage.

## Startup sequence

1. Native launch screen — plain white (Android `launch_background.xml` +
   `styles.xml`, iOS `LaunchScreen.storyboard`), light and dark mode alike.
2. In-app splash phase 1 — the same plain white, so the hand-off is invisible.
3. In-app splash phase 2 — logo and Lottie loader fade up out of that white.
4. Auth gate — Login, or the tab scaffold if there is a session.

Phase durations are `SplashScreen.whiteHold` / `brandedHold`.

## Motion

`lib/widgets/motion.dart` holds the whole vocabulary:

- `AppMotion` — durations (`fast` / `normal` / `slow`) and curves. Use these
  rather than inventing a timing.
- `FadeSlideIn` — the standard entrance. `FadeSlideIn.stagger(children)`
  wraps a list so it arrives in sequence.
- `PressableScale` — makes a surface physically depress under a finger.
- `AnimatedNumber` — counts to a new value instead of snapping.
- `SwapIn` — cross-fade + scale between two states in place.
- `PulseHalo` / `Breathing` — slow ambient motion for "live" and "alert".
- `DrawIn` — a 0→1 progress value, for charts that draw themselves in.

Everything above honours the OS "reduce motion" setting
(`AppMotion.reduced(context)`) by rendering its final state immediately.

## Docs

- `CRX_PULSE_CLAYMORPHISM.md` — the Claymorphism surface language.
- `CRX_PULSE_FLUTTER_CHANGES.md` — history of the React Native → Flutter port.
- `../hardware/crx_pulse_dev/crx_pulse/HARDWARE_WIRING.md` — pin map and
  sensor calibration.
