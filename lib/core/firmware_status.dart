/// The firmware's `/api/status` payload, reduced to what the app displays.
///
/// Older builds do not send a build tag, so every read here is optional:
/// a board without one is still a CRX-Pulse board, just not the newest one.
String? buildTagFromStatus(Map<String, dynamic> status) {
  final value = status['build_tag'];
  if (value is! String) return null;
  final tag = value.trim();
  return tag.isEmpty ? null : tag;
}

/// Whether the AP poller should spend another request on `/api/status`.
///
/// The status is static until the board is reflashed, so the first check
/// is enough for an app session; the interval only makes a reflash visible
/// without leaving the app open.
bool shouldRefreshFirmwareTag({
  required DateTime now,
  required DateTime? lastChecked,
  required bool inFlight,
  Duration interval = const Duration(seconds: 60),
}) {
  if (inFlight) return false;
  if (lastChecked == null) return true;
  return now.difference(lastChecked) >= interval;
}
