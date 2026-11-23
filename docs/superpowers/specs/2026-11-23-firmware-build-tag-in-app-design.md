# Firmware Build Tag in App — Design

Date: 2026-11-23

## Intent

The user wants to **see the latest firmware update** in the app. Concretely: after flashing the motor-first feed cycle, the app should show which firmware build the board is running, so the update is verifiable without a serial cable.

## Goals

- Publish a short, non-secret build tag from `crx_pulse.ino` in the existing `/api/status` JSON.
- Read that tag through the existing `DeviceApClient.fetchStatus()` route.
- Surface it in Device Setup as a **Firmware build** row next to **Paired device** and **Last reading**.
- Keep working with older firmware that has no build tag: show a placeholder instead of failing the offline-device check.

## Non-goals

- No OTA, no version comparison, no auto-update prompt.
- No change to the cloud `readings` schema or the Supabase payload.
- No edit to `secrets.h`; the existing `firmware` value stays where it is. The new tag is a separate constant inside `crx_pulse.ino`.
- No new Flutter dependency.

## Constraints

- `/api/status` only exists on the ESP32 SoftAP (`192.168.4.1`). The tag can only be read while the phone is joined to the device's WiFi; elsewhere the UI shows `—`.
- `DeviceApClient` fails quietly by design; a missing status response must not change connection state or raise an error.
- `_apPollInterval` is 3 s. Fetching status on every AP poll would double the HTTP traffic and add latency, so the status read is throttled.
- The hardware repo has unrelated uncommitted work; do not stage or commit it.

## Decisions

- **Tag value:** `2026.11.23-motor-first` — the date plus the change that produced this build.
- **Firmware key:** `build_tag`, added alongside the existing `firmware` key in `handleApiStatus()`.
- **Where the constant lives:** a new `const char*` near the top of `crx_pulse.ino`, away from the credential block. This avoids reading or editing `secrets.h`.
- **App storage:** `LocalEsp32Service.firmwareBuildTag`, populated from the AP status response. It is exposed through the existing `ChangeNotifier`, so Device Setup rebuilds automatically.
- **Fetch policy:** attempt a status read on the first successful AP contact, then at most once every 60 s. A null/old response leaves the field unchanged; it never blocks the live reading path.
- **UI copy:** one `_InfoRow` labelled `Firmware build`. Placeholder is `—`; a short hint under the card says `Connect to the device's WiFi to read the build tag` only when no tag is known.
- **Backward compatibility:** `DeviceApClient._isStatus` keeps its current required keys. `build_tag` is read defensively with a string check.

## Verification

- `flutter test` including new tests for the status key and the build-tag row.
- `flutter analyze`.
- Firmware diff reviewed in narrow hunks; no credential block opened.
- On-device check remains user-owned: flash, join `CRX-Pulse-XXXXXX`, open Device Setup, confirm `2026.11.23-motor-first`.
