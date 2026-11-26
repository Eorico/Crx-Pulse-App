/// CRX-Pulse — the app's mirror of the firmware's constants.
///
/// Every number here is copied from `hardware/crx_pulse_dev/crx_pulse/
/// crx_pulse.ino` (which in turn carries the bench sketch's calibration
/// verbatim). The app used to hard-code its own, drifted copies in half
/// a dozen files — a fan curve that started at 28 °C when the firmware
/// starts at 25 °C, turbidity "NTU" when the device sends a percentage,
/// ammonia "ppm" when the device sends mg/L. One file now holds them,
/// so firmware and app can only disagree in one place.
///
/// If you change a constant in the .ino, change it here too. The names
/// below deliberately match the firmware's.
library;

/// One selectable speed for the DC rotator, carrying both the percent
/// the user sees and the raw PWM the firmware's setMotor1() wants.
class RotatorSpeed {
  final String label;
  final int percent;
  final int pwm;
  const RotatorSpeed(this.label, this.percent, this.pwm);
}

/// Command `type` values the firmware's pollCommands() understands.
/// Strings, because that is what the `commands.type` column holds.
class DeviceCommand {
  DeviceCommand._();

  /// Dispense feed: `grams` + `rotator_pwm`.
  static const feedNow = 'feed_now';

  /// Test: drive the feeder servo. The firmware auto-closes after
  /// [FirmwareSpec.servoTestAutoClose].
  static const servoOpen = 'servo_open';
  static const servoClose = 'servo_close';

  /// Test: run the DC rotator at `value` PWM (0 stops it). The firmware
  /// auto-stops after [FirmwareSpec.motorTestTimeout].
  static const motorTest = 'motor_test';

  /// Ask the device to mirror its full serial output for `value`
  /// seconds.
  static const logStream = 'log_stream';
}

class FirmwareSpec {
  FirmwareSpec._();

  // ───────────────────────── cloud cadence ─────────────────────────
  /// CLOUD_READING_INTERVAL in the firmware.
  ///
  /// Was 10 s here while the firmware had moved to 3 s. Nothing read it,
  /// so nothing misbehaved — but the offline fallback poller does read
  /// it now, to ask the device's own WiFi at the rate the device would
  /// have pushed to the cloud.
  static const Duration readingInterval = Duration(seconds: 3);

  /// How long a reading counts as live.
  ///
  /// Unchanged at 30 s. That is ten pushes rather than the three the
  /// comment here used to claim, which is deliberately generous: a
  /// reading is only three seconds of the tank's life, and flipping the
  /// whole dashboard to "Not Connected" over one slow insert would be
  /// worse than showing a value a few seconds old.
  static const Duration freshWindow = Duration(seconds: 30);

  // ───────────────────────── cooling fan ─────────────────────────
  // COOLING_START / COOLING_MAX / COOLING_MIN_PWM / COOLING_MAX_PWM.
  //
  //   below 25 °C : off
  //   25 → 40 °C  : ramps 191 → 255
  //   above 40 °C : 255
  //
  // 191 is the lowest duty this fan reliably starts at under load,
  // which is why the ramp begins there instead of at 0.
  static const double coolingStartC = 25.0;
  static const double coolingMaxC = 40.0;
  static const int coolingMinPwm = 191;
  static const int coolingMaxPwm = 255;

  /// Housing temperature at which the app flags "hot": the point where
  /// the firmware has nothing left to give — the fan is already pegged
  /// at 100%. (The app previously used an unexplained 34 °C.)
  static const double housingHotC = coolingMaxC;

  // ───────────────────────── turbidity ─────────────────────────
  // Mirrors TurbidityCalibration in crx_pulse/turbidity_calibration.h.
  // Voltage falls as turbidity rises:
  //
  //   1.36460 V ->   0.0 %
  //   1.33015 V ->  19.9 %   Clear
  //   1.28065 V ->  48.5 %   Slightly Turbid
  //   1.22865 V ->  78.6 %   Turbid
  //   1.19160 V -> 100.0 %   Highly Turbid
  //
  // Nothing in the live path converts volts — the device sends the
  // percentage. This copy is pinned by calibration_test.dart so the
  // app and the firmware cannot drift.
  static const List<double> turbidityCurveVolts = [
    1.36460, 1.33015, 1.28065, 1.22865, 1.19160
  ];
  static const List<double> turbidityCurvePercent = [
    0.0, 19.9, 48.5, 78.6, 100.0
  ];

  static const double turbidityVClear = 1.36460; // 0 %
  static const double turbidityVHigh = 1.19160; // 100 %

  /// The firmware's own curve, so the app and the device agree on what
  /// a voltage means.
  static double turbidityPercentOf(double volts) {
    if (volts >= turbidityCurveVolts.first) return 0.0;
    if (volts <= turbidityCurveVolts.last) return 100.0;
    for (var i = 0; i < turbidityCurveVolts.length - 1; i++) {
      final vHi = turbidityCurveVolts[i];
      final vLo = turbidityCurveVolts[i + 1];
      if (volts <= vHi && volts >= vLo) {
        return turbidityCurvePercent[i] +
            (vHi - volts) *
                (turbidityCurvePercent[i + 1] - turbidityCurvePercent[i]) /
                (vHi - vLo);
      }
    }
    return 100.0;
  }

  /// Band edges as PERCENT — which is what `readings.turbidity` holds.
  ///
  /// Stated directly rather than derived from voltage thresholds. The
  /// firmware now decides the band from the percentage too, so the two
  /// cannot drift apart the way they could when one was computed from
  /// volts and the other from percent.
  static const double turbidityClearMax = 19.9;
  static const double turbiditySlightlyMax = 48.5;
  static const double turbidityTurbidMax = 78.6;

  /// The firmware's four status words, from a percentage.
  ///
  /// Each cut is the TOP of its band, so equality stays in the band the
  /// standard names: 19.9 is Clear, 48.5 is Slightly, 78.6 is Turbid.
  static String turbidityStatusOf(double percent) {
    if (percent <= turbidityClearMax) return 'Clear';
    if (percent <= turbiditySlightlyMax) return 'Slightly Turbid';
    if (percent <= turbidityTurbidMax) return 'Turbid';
    return 'Highly Turbid';
  }

  /// "Needs attention" starts where the firmware says "Turbid".
  static bool turbidityIsSafe(double percent) => percent <= turbiditySlightlyMax;

  // ───────────────────────── ammonia (mg/L) ─────────────────────────
  // getAmmoniaStatus() in the firmware: < 0.25 Safe, < 0.50 Warning,
  // else Critical. The device reports mg/L — never ppm.
  static const double ammoniaSafeMax = 0.25;
  static const double ammoniaWarningMax = 0.50;

  /// Top of the MQ-137's calibrated span (AmmoniaConfig::C2).
  ///
  /// The firmware clamps to this rather than extrapolating, so the app
  /// never receives a value above it — and a reported 0.53 may mean
  /// "at least 0.53", not exactly 0.53. The sensor's reading is also
  /// clamped UP to 0.00 at the bottom, so `ammonia` is never null for
  /// an out-of-band reading any more; it used to arrive as null with
  /// ammonia_valid false, which the dashboard showed as "Not
  /// Connected".
  ///
  /// The reconstructed sensor voltage, which is what distinguishes a
  /// genuine 0.53 from a clamped one, is not in `readings` — it is on
  /// the LCD and in the device log console.
  static const double ammoniaCalibratedMax = 0.53;

  static const String ammoniaUnit = ' mg/L';

  static bool ammoniaIsSafe(double mgL) => mgL < ammoniaWarningMax;

  static String ammoniaStatusOf(double mgL) {
    if (mgL < ammoniaSafeMax) return 'Safe';
    if (mgL < ammoniaWarningMax) return 'Warning';
    return 'Critical';
  }

  // ───────────────────────── feeder ─────────────────────────
  // gramsToOpenMs() has a calibrated open time for exactly these six
  // doses; anything else falls back to the 10 g timing, so the app
  // must only ever offer these.
  static const List<int> feedGramOptions = [5, 10, 15, 20, 25, 30];

  /// SERVO open time per dose, in milliseconds — shown in the app so
  /// the dose dropdown explains itself.
  static const Map<int, int> feedOpenMs = {
    5: 400,
    10: 800,
    15: 1200,
    20: 1600,
    25: 2000,
    30: 2400,
  };

  /// FEED_SETTLE_MS + ROTATOR_RUN_MS: after the door closes the feed is
  /// given 1.5 s to drop, then the rotator spins for 12 s — long enough
  /// to complete a turn, where the old 2 s was not.
  ///
  /// The firmware runs that 12 s as a deadline serviced from loop(),
  /// not a delay(), so readings keep flowing during a feed and the app
  /// does not briefly see the device as offline.
  static const Duration feedSettle = Duration(milliseconds: 1500);
  static const Duration rotatorRun = Duration(milliseconds: 12000);

  /// Total wall-clock time one feed takes on the device.
  static Duration feedCycleFor(int grams) =>
      Duration(milliseconds: feedOpenMs[grams] ?? 800) + feedSettle + rotatorRun;

  /// FEED_COMMAND_MAX_AGE_S: a queued Feed Now older than this is
  /// dropped by the device instead of dispensed, so a tank that was
  /// offline does not get every missed feed at once on reconnect.
  static const Duration feedCommandMaxAge = Duration(minutes: 10);

  /// NTP_GMT_OFFSET — the device fires schedules on its own clock, at
  /// UTC+8, whether or not the phone is in that zone.
  static const int deviceUtcOffsetHours = 8;
  static const String deviceTimezoneLabel = 'device time (UTC+8)';

  // ───────────────────── rotator (DC motor) ─────────────────────
  // setMotor1() in the firmware drives Motor 1 — the DC rotator that
  // runs after each feed — by raw PWM. These five levels are the bench
  // sketch's own manual test steps (serial keys 2..6), so the app
  // offers exactly the speeds the firmware was validated at.
  static const List<RotatorSpeed> rotatorSpeeds = [
    RotatorSpeed('Off', 0, 0),
    RotatorSpeed('25%', 25, 90),
    RotatorSpeed('50%', 50, 128),
    RotatorSpeed('75%', 75, 191),
    RotatorSpeed('100%', 100, 255),
  ];

  /// What a feed uses when nothing else is chosen — full speed, which
  /// is what the firmware did unconditionally before the speed became
  /// selectable.
  static const int rotatorDefaultPwm = 255;

  static RotatorSpeed rotatorSpeedForPwm(int pwm) => rotatorSpeeds.firstWhere(
        (s) => s.pwm == pwm,
        orElse: () => rotatorSpeeds.last,
      );

  /// MOTOR_TEST_MAX_MS: the firmware stops a test-driven motor by
  /// itself after this long, so a forgotten test cannot leave it
  /// running. Shown in the UI so the behaviour is not a surprise.
  static const Duration motorTestTimeout = Duration(seconds: 30);

  // ───────────────────────── servo ─────────────────────────
  // SERVO_OPEN_ANGLE / SERVO_CLOSED_ANGLE.
  static const int servoOpenAngle = 160;
  static const int servoClosedAngle = 180;

  /// SERVO_TEST_MAX_OPEN_MS: an open feeder door drops feed, so the
  /// firmware force-closes it after this long if a test left it open.
  static const Duration servoTestAutoClose = Duration(seconds: 10);

  // ───────────────────── log streaming ─────────────────────
  // The device always publishes its event lines (feeds, commands, WiFi
  // changes, errors). The full serial output — including the sensor
  // block it prints every SENSOR_INTERVAL — is only mirrored while the
  // app has asked for it, so the log table is not filled around the
  // clock by a console nobody is watching.

  /// How long one `log_stream` request keeps verbose output flowing.
  /// The console screen renews it well before this lapses.
  static const Duration logStreamWindow = Duration(minutes: 5);

  /// How often the console renews that request while it is open.
  static const Duration logStreamRenew = Duration(minutes: 2);

  /// Lines held in the console. The firmware's own ring buffer is much
  /// smaller (MAX_LOG_LINES); this is the app-side scrollback.
  static const int logScrollback = 400;

  // ───────────────── app-side water-quality ranges ─────────────────
  // These are NOT in the firmware — the device measures, it does not
  // judge. They are the aquaculture ranges the app alerts on, kept
  // here so every screen uses one definition.
  static const double phSafeMin = 6.5;
  static const double phSafeMax = 8.5;

  // ---- The device's 3-point calibration, for reference ----
  //
  // The app never computes pH (the device sends it), but these record
  // the explicit standard buffers the firmware is anchored to. They are
  // named 6.86 / 4.01 / 9.18, not 7.00 / 4.00 / 10.00.
  static const double phBufferNeutral = 6.86;
  static const double phBufferAcid = 4.01;
  static const double phBufferBase = 9.18;
  static const double phVoltNeutral = 1.950;
  static const double phVoltAcid = 2.447;
  static const double phVoltBase = 1.425;
  static bool phIsSafe(double ph) => ph >= phSafeMin && ph <= phSafeMax;

  static const double waterTempSafeMinC = 20.0;
  static const double waterTempSafeMaxC = 30.0;
  static bool waterTempIsSafe(double c) =>
      c >= waterTempSafeMinC && c <= waterTempSafeMaxC;

  static bool housingTempIsSafe(double c) => c < housingHotC;
}
