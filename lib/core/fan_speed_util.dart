import 'firmware_spec.dart';

/// Mirrors `controlCoolingMotor()` in crx_pulse.ino exactly:
///
///   housing temp < 25 °C   -> PWM 0   (fan off)
///   25 °C .. 40 °C         -> PWM ramps 191 -> 255
///   housing temp > 40 °C   -> PWM 255 (full)
///
/// This used to carry a *different* curve inherited from an older
/// firmware revision (min duty 26 = 10%, ramping from 28 °C), so the
/// app's estimated fan speed disagreed with the device's actual one —
/// and it never showed the fan as off, because its floor was 10% rather
/// than 0. The four constants now come from [FirmwareSpec], which is
/// the single place they are written down on the app side.
///
/// Only used as a FALLBACK: when the device reports real telemetry
/// (`fan_active` / `fan_percent`), that always wins.
class FanSpeedResult {
  final int duty;
  final int percent;
  const FanSpeedResult({required this.duty, required this.percent});

  bool get isOff => duty == 0;
}

int _percentOf(int duty) => ((duty * 100) / FirmwareSpec.coolingMaxPwm).round();

FanSpeedResult computeFanSpeed(double? ambientTempC) {
  // No housing temperature means the firmware has nothing to ramp on,
  // and it holds the fan OFF rather than guessing. Match that.
  if (ambientTempC == null) {
    return const FanSpeedResult(duty: 0, percent: 0);
  }

  int duty;
  if (ambientTempC < FirmwareSpec.coolingStartC) {
    duty = 0;
  } else if (ambientTempC >= FirmwareSpec.coolingMaxC) {
    duty = FirmwareSpec.coolingMaxPwm;
  } else {
    // Arduino map() on the same inputs: integer maths over tenths of a
    // degree, so the app lands on the same duty the device picks.
    final t = (ambientTempC * 10).round();
    final lo = (FirmwareSpec.coolingStartC * 10).round();
    final hi = (FirmwareSpec.coolingMaxC * 10).round();
    duty = FirmwareSpec.coolingMinPwm +
        ((t - lo) * (FirmwareSpec.coolingMaxPwm - FirmwareSpec.coolingMinPwm)) ~/
            (hi - lo);
  }

  duty = duty.clamp(0, FirmwareSpec.coolingMaxPwm);
  return FanSpeedResult(duty: duty, percent: _percentOf(duty));
}

/// Maps fan percent to a full-rotation duration — a higher percent
/// spins faster (shorter duration), clamped so it is never absurdly
/// fast or visually stalled. 0% returns null: nothing to animate.
int fanPercentToSpinDurationMs(int percent) {
  const minDurationMs = 400;
  const maxDurationMs = 2500;
  // The firmware's ramp floor is 75% of full duty (191/255), so the
  // visible speed range is mapped across 75 → 100% rather than 10 → 100.
  final floor = _percentOf(FirmwareSpec.coolingMinPwm);
  final clamped = percent.clamp(floor, 100);
  final ratio = (clamped - floor) / (100 - floor);
  return (maxDurationMs - ratio * (maxDurationMs - minDurationMs)).round();
}
