/// Mirrors the firmware's FanController.h exactly:
///   FAN_MIN_DUTY=26 (10%), FAN_MAX_DUTY=255 (100%),
///   FAN_TEMP_LOW=28.0°C, FAN_TEMP_HIGH=40.0°C
/// Verified against the same formula used in the original React
/// Native version - same linear ramp, same clamping at both ends.
class FanSpeedResult {
  final int duty;
  final int percent;
  const FanSpeedResult({required this.duty, required this.percent});
}

const int _fanMinDuty = 26;
const int _fanMaxDuty = 255;
const double _fanTempLow = 28.0;
const double _fanTempHigh = 40.0;

FanSpeedResult computeFanSpeed(double? ambientTempC) {
  if (ambientTempC == null) {
    return FanSpeedResult(duty: _fanMinDuty, percent: ((_fanMinDuty * 100) / 255).round());
  }

  int duty;
  if (ambientTempC <= _fanTempLow) {
    duty = _fanMinDuty;
  } else if (ambientTempC >= _fanTempHigh) {
    duty = _fanMaxDuty;
  } else {
    final ratio = (ambientTempC - _fanTempLow) / (_fanTempHigh - _fanTempLow);
    duty = _fanMinDuty + (ratio * (_fanMaxDuty - _fanMinDuty)).floor();
  }

  return FanSpeedResult(duty: duty, percent: ((duty * 100) / 255).round());
}

/// Maps fan percent to a full-rotation duration - higher percent spins
/// faster (shorter duration), clamped so it's never absurdly fast or
/// nearly stopped.
int fanPercentToSpinDurationMs(int percent) {
  const minDurationMs = 400;
  const maxDurationMs = 2500;
  final clamped = percent.clamp(10, 100);
  final ratio = (clamped - 10) / (100 - 10);
  return (maxDurationMs - ratio * (maxDurationMs - minDurationMs)).round();
}
