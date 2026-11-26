/// Timestamp copy shared by the alert toast and the Notifications list.
///
/// Hand-rolled rather than using `intl`: the app has no such dependency and
/// alerts only need two fixed shapes.
const List<String> _monthNames = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String formatNotificationTime(DateTime value) {
  final hour24 = value.hour;
  final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
  final clock = '${hour12.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')} '
      '${hour24 < 12 ? 'AM' : 'PM'}';

  final now = DateTime.now();
  final isToday = value.year == now.year &&
      value.month == now.month &&
      value.day == now.day;
  if (isToday) return 'Today $clock';

  return '${_monthNames[value.month - 1]} ${value.day}, ${value.year} · $clock';
}
