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
