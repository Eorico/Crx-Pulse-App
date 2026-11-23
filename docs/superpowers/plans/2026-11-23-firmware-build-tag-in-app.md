# Firmware Build Tag in App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show the flashed firmware's build tag in Device Setup so the motor-first update is verifiable from the app.

**Architecture:** The ESP32 already serves `/api/status` over its SoftAP. Add a non-secret build tag to that JSON, read it with the existing `DeviceApClient`, store it on `LocalEsp32Service`, and render it with a small reusable row. The read is AP-only and throttled because `/api/status` exists only at `192.168.4.1`.

**Tech Stack:** Arduino C++ (ESP32), Flutter/Dart, Provider, `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-11-23-firmware-build-tag-in-app-design.md`

## Global Constraints

- Build tag value is exactly `2026.11.23-motor-first`.
- JSON key is exactly `build_tag`.
- Never open, print, or edit `hardware/crx_pulse_dev/crx_pulse/secrets.h`.
- `DeviceApClient._isStatus` keeps requiring only `device_id`, `ap_active`, `uptime_s`; `build_tag` is optional for backward compatibility.
- Placeholder text is exactly `—`.
- Hint copy is exactly `Connect to the device's WiFi to read the build tag`.
- Status fetch is throttled to at most once every 60 s.
- Do not stage or commit unrelated working-tree changes in either repo.

## Review Focus

- **Old firmware with no `build_tag`** must still pass `/api/status` validation → test in Task 2's `device_ap_client_test.dart` change.
- **Malformed or empty `build_tag`** must not paint a blank or non-string row → test in Task 2's `firmware_status_test.dart`.
- **Phone not joined to the device AP** must show `—` and the hint, not an error → test in Task 4's widget test.
- **Wrong device's AP** must not be trusted → service checks `live['device_id']` before any status read; code review in Task 3.
- **3 s AP poll loop** must not turn into 3 s status requests → 60 s throttle constant in Task 3.

---

### Task 1: Firmware publishes the build tag

**Files:**
- Modify: `hardware/crx_pulse_dev/crx_pulse/crx_pulse.ino:188-190` (constant), `:1447-1458` (status handler)

**Interfaces:**
- Consumes: existing `handleApiStatus()` JSON payload.
- Produces: `build_tag` string in `/api/status`; value `2026.11.23-motor-first`.

- [ ] **1. Add the constant.** Insert immediately after the anon-key comment block (~line 189):

```cpp
// Short build tag shown in the app's Device Setup screen. Kept here rather
// than in secrets.h so it can change without touching credentials.
static const char* FIRMWARE_BUILD_TAG = "2026.11.23-motor-first";
```

- [ ] **2. Add the JSON key.** In `handleApiStatus()`, add `doc["build_tag"] = FIRMWARE_BUILD_TAG;` next to the existing `firmware` key, and raise `StaticJsonDocument<256>` to `StaticJsonDocument<384>` so the longer payload fits.

- [ ] **3. Verify without opening the credential block.** Run `git diff -U2` filtered to the two changed line ranges only; confirm the new constant and the new key are the only firmware edits in this task. Confirm no `secrets.h` content appears.

- [ ] **4. Commit** only `crx_pulse/crx_pulse.ino` in the hardware repo, with message `feat: publish firmware build tag in status API`.

### Task 2: App parses the status defensively

**Files:**
- Create: `mobile/lib/core/firmware_status.dart`
- Create: `mobile/test/firmware_status_test.dart`
- Modify: `mobile/test/device_ap_client_test.dart:25-29,141-149`

**Interfaces:**
- Consumes: `Map<String, dynamic>` from `DeviceApClient.fetchStatus()`.
- Produces: `String? buildTagFromStatus(Map<String, dynamic> status)` — trimmed non-empty string, or `null`.

- [ ] **1. Write failing tests for the parser.** In `mobile/test/firmware_status_test.dart`, cover: valid `build_tag` returns the exact string; whitespace around it is trimmed; missing key returns `null`; non-string value returns `null`; empty/whitespace value returns `null`.

- [ ] **2. Run the failing tests.** Run `flutter test test/firmware_status_test.dart`. Expected: compile/import failure because `firmware_status.dart` does not exist yet.

- [ ] **3. Implement the parser.** Create `mobile/lib/core/firmware_status.dart` with the exact signature above. Read `status['build_tag']`, accept only `String`, `trim()` it, and return `null` when empty.

- [ ] **4. Run the parser tests.** Expected: all pass.

- [ ] **5. Extend the client test.** Add `"build_tag":"2026.11.23-motor-first"` to `statusBody` in `device_ap_client_test.dart`. Assert `s!['build_tag'] == '2026.11.23-motor-first'`. Add a second test that removes `build_tag` from the decoded status body and expects `fetchStatus()` still returns non-null.

- [ ] **6. Run the client tests.** Run `flutter test test/device_ap_client_test.dart`. Expected: all pass.

- [ ] **7. Commit** these four files with message `test: accept optional firmware build tag`.

### Task 3: Service fetches and stores the tag

**Files:**
- Modify: `mobile/lib/services/local_esp32_service.dart:48-57` (fields), `:105-116` (constants), `:352-381` (AP poll)
- Consumes: `buildTagFromStatus()` from Task 2, `DeviceApClient.fetchStatus()`.
- Produces: `String? firmwareBuildTag` on `LocalEsp32Service`, notified through `ChangeNotifier`.

**Interfaces:**
- Consumes: `buildTagFromStatus(status)`.
- Produces: `firmwareBuildTag`, read by Task 4.

- [ ] **1. Add public state and throttle fields.** Add `String? firmwareBuildTag;` beside `lastUpdated`. Add `static const Duration _firmwareTagRefreshInterval = Duration(seconds: 60);`, `DateTime? _firmwareTagCheckedAt;`, and `bool _firmwareTagFetchInFlight = false;` beside `_apProbeMaxGap`.

- [ ] **2. Add a guarded fetch method.** Implement `void _refreshFirmwareBuildTag()`. It must: return if disposed, in flight, or checked within the last 60 s; mark the attempt time and in-flight flag before calling `_ap.fetchStatus()`; on a non-null status apply `buildTagFromStatus()`; set the field and call `notifyListeners()` only when the parsed tag is non-null and different; clear the in-flight flag on success, null, and error.

- [ ] **3. Call it from the AP path.** In `_pollDeviceAp()`, after the paired-device id check (~line 381) and before the reading row is built, call `_refreshFirmwareBuildTag()`. It must be fire-and-forget (`unawaited`) so a slow status response never delays the live reading.

- [ ] **4. Verify.** Run `flutter analyze`. Expected: `No issues found!`. Run `flutter test test/device_ap_client_test.dart test/firmware_status_test.dart`. Expected: all pass. Confirm by grep that `_refreshFirmwareBuildTag` is called only from the AP path and `firmwareBuildTag` is never cleared by `_clearReadings()`.

- [ ] **5. Commit** with message `feat: store firmware build tag from device AP`.

### Task 4: Device Setup shows the tag

**Files:**
- Create: `mobile/lib/widgets/firmware_build_row.dart`
- Create: `mobile/test/firmware_build_row_test.dart`
- Modify: `mobile/lib/screens/devices/device_setup_screen.dart:3-10` (imports), `:114-120` (status card)
- Consumes: `LocalEsp32Service.firmwareBuildTag` from Task 3.

**Interfaces:**
- Consumes: nullable `String` tag.
- Produces: `FirmwareBuildRow({super.key, required this.tag})`.

- [ ] **1. Write failing widget tests.** In `firmware_build_row_test.dart`, pump `FirmwareBuildRow` inside a `MaterialApp`/`Scaffold`. Cover: a tag renders `Firmware build` and `2026.11.23-motor-first`; `null` renders `—` and the exact hint; no exception is thrown in a vertical list.

- [ ] **2. Run the failing tests.** Run `flutter test test/firmware_build_row_test.dart`. Expected: import failure because the widget does not exist.

- [ ] **3. Implement the widget.** Create `FirmwareBuildRow` following the existing `_InfoRow` typography: `Row` with `mainAxisAlignment: spaceBetween`, muted 12px label, primary 12px w600 value. When `tag == null`, show the placeholder and a 4px-gap hint below with the exact copy from Global Constraints. Keep the widget small enough to sit in a `Column` with unbounded height.

- [ ] **4. Run the widget tests.** Expected: all pass.

- [ ] **5. Wire it into Device Setup.** Import the widget and replace the two `_InfoRow(...)` calls in the live status card with the existing rows plus `FirmwareBuildRow(tag: esp32.firmwareBuildTag)` as the last row.

- [ ] **6. Verify.** Run `flutter test`. Expected: the full suite passes. Run `flutter analyze`. Expected: `No issues found!`.

- [ ] **7. Commit** with message `feat: show firmware build tag in Device Setup`.

## Final Verification

- `flutter test` — full suite, 0 failures.
- `flutter analyze` — `No issues found!`.
- Firmware diff review confirms only the two intended hunks, no credential content.
- Report that on-device verification is user-owned: flash, join `CRX-Pulse-XXXXXX`, open Device Setup, confirm `2026.11.23-motor-first`.
