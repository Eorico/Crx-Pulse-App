/// The zone boundaries for one metric, as data rather than a closure.
///
/// This used to be a `zoneOf` function per metric. It became data so
/// that the same numbers can be handed to the `readings_zone_counts`
/// SQL function, which counts the distribution over every row in the
/// window instead of making the phone download them all. One
/// definition, used by both sides — a second copy written out in SQL
/// would drift, and a distribution chart quietly disagreeing with the
/// sensor cards is worse than a slow one.
class MetricBands {
  /// Column name in `readings`, and the metric key the SQL function
  /// takes.
  final String column;

  /// Ascending boundaries. N cuts describe N+1 zones.
  final List<double> cuts;

  /// Whether each cut is strict (`v < cut`) or inclusive (`v <= cut`).
  ///
  /// The bands genuinely mix the two, so this cannot be one global
  /// rule. pH 6.5 is the BOTTOM of safe, so 6.5 belongs to Optimal and
  /// the cut is strict. Turbidity's 19.9% is the TOP of Clear, so 19.9
  /// belongs to Clear and the cut is inclusive. Values land exactly on
  /// these boundaries often — the firmware reports 1–2 decimals — so
  /// getting it uniform would visibly misfile readings.
  final List<bool> strict;

  const MetricBands({
    required this.column,
    required this.cuts,
    required this.strict,
  });

  int get zoneCount => cuts.length + 1;

  /// Which zone [v] falls in. Must agree exactly with the SQL
  /// function's rule, which is why both read the same two lists.
  int zoneOf(double v) {
    for (int i = 0; i < cuts.length; i++) {
      if (strict[i] ? v < cuts[i] : v <= cuts[i]) return i;
    }
    return cuts.length;
  }
}
