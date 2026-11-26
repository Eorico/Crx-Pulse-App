/// Keeps a single bad pH sample from reaching the dashboard.
///
/// The probe sometimes reports 9–10 for one poll and returns to the normal
/// range on the next. A jump larger than [maxImmediateChange] is therefore
/// held until a second reading agrees with it; a reading that returns near
/// the accepted value discards the candidate instead.
class PhReadingFilter {
  static const double maxImmediateChange = 0.5;

  double? _accepted;
  double? _candidate;

  double? accept(double? reading) {
    if (reading == null || reading.isNaN || reading.isInfinite) {
      reset();
      return null;
    }

    if (_accepted == null ||
        (reading - _accepted!).abs() <= maxImmediateChange) {
      _accepted = reading;
      _candidate = null;
      return reading;
    }

    if (_candidate != null &&
        (reading - _candidate!).abs() <= maxImmediateChange) {
      _accepted = reading;
      _candidate = null;
      return reading;
    }

    _candidate = reading;
    return _accepted;
  }

  /// Seeds the accepted value from a cached reading so the first live
  /// row after startup is compared instead of accepted unconditionally.
  void seed(double? reading) {
    accept(reading);
  }

  void reset() {
    _accepted = null;
    _candidate = null;
  }
}
