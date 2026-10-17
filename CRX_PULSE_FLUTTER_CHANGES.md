# CRX-Pulse — Flutter app: live-from-Firebase readings + feeding

This patch switches the app from polling the ESP32's local AP to the new
cloud architecture: **ESP32 → Cloud Function → Firestore → app (live)**,
with feeding written to Firestore and picked up by the ESP32.

> Not compiler-verified: unlike the backend TypeScript (which was built
> with `tsc`), there's no Flutter toolchain in the authoring environment,
> so these files are hand-verified (symbol/brace/icon checks) — run
> `flutter analyze` once after dropping them in.

## Files (drop into `lib/`, replacing the same paths)

| File | Change |
|---|---|
| `services/local_esp32_service.dart` | **Rewritten.** Same class name, fields, and `Esp32ConnectionState` enum, but readings now stream live from `users/{uid}/component-sensors-readings` (newest doc). Adds `turbidityStatus` and honours the firmware's per-sensor `*Valid` flags (invalid → "Not Connected"). `connected` = a reading arrived in the last 30 s. |
| `services/local_feeding_provider.dart` | **Rewritten.** Firestore-backed schedules (`feeding-schedules`) + `feedNow(deviceId, grams)` (writes a `device-commands` doc). `FeedingSchedule` now `{id, time, grams, active}`. Scheduled feeding runs on the ESP32 now, so `checkDueSchedules` is a no-op. |
| `services/device_provider.dart` | **New.** Resolves the user's paired device from `devices` (where `userId == me`) and pairs via the `pairDevice` callable (returns the key once). |
| `widgets/sensor_card.dart` | **Rewritten.** Adds an optional `subtitle` (used for the turbidity status word). |
| `widgets/local_feeding_section.dart` | **Rewritten.** Grams **dropdown** (5/10/15/20/25/30), **Feed Now**, time field + **Add Schedule**, and a live schedule list with toggle/delete. Disabled with a hint until a device is paired. |
| `screens/management/local_management_screen.dart` | **Rewritten.** Six readings: Ammonia (mg/L), Turbidity (% + status), pH, Water Temp (°C), Housing Temp (°C), Rotating Fan. |
| `screens/devices/local_device_setup_screen.dart` | **Rewritten.** Pairing flow (mint a one-time device key, copy it into the firmware) + live connection status. |
| `main.dart` | **Rewritten.** Registers `DeviceProvider`; starts/stops it with auth; no longer auto-starts `FirebaseSyncService` (the ESP32 now owns reading writes). |

Everything else in `lib/` is untouched — `main_tab_scaffold`, `home`,
analytics/notification providers, `realtime_sync_service`, and the thermal
widget all keep working because `LocalEsp32Service`'s public surface and
the `Esp32ConnectionState` enum were kept identical.

## One dependency to add (`pubspec.yaml`, under `dependencies:`)

```yaml
  cloud_functions:
```

Then `flutter pub get`. (Used only by `DeviceProvider.pairDevice` to call
the `pairDevice` Cloud Function.)

## Wiring it to the backend + firmware

- Firebase project is `crx-pulse-1d07f`, so the firmware's
  `FIREBASE_FN_BASE` is
  `https://us-central1-crx-pulse-1d07f.cloudfunctions.net`.
- Pair a device in **Device Setup** → paste the returned key into the
  firmware's `DEVICE_KEY` and set the same `DEVICE_ID` → flash. Readings
  then appear live, and Feed Now / schedules reach the device.

## Two cleanups to finish the migration

1. **Tighten the Firestore rule:** now that the phone no longer writes
   readings, change the `component-sensors-readings` rule from
   `allow create` to **read-only** (the exact line is flagged in
   `firestore.rules`).
2. **Old test docs:** earlier phone-sync wrote `recordedAt` as an ISO
   string; the ESP32 writes a real Timestamp. If you have old string-typed
   docs from testing, clear them so the newest-first ordering is clean.

## Optional cosmetic follow-up

`home` screen's 24-hour range still labels ammonia "ppm" and turbidity
"NTU"; update those strings to "mg/L" and "%" when convenient (left out
here to avoid touching an unrelated screen).
