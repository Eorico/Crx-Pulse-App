/// The subset of the device link that feeding and component-test actions
/// need when the tank has no internet at all.
///
/// Both providers already receive a `deviceId` from the UI. This interface
/// exists so they can ask "is the only link the board's own access point?"
/// without importing [LocalEsp32Service] — which would drag Supabase into
/// every test and make the online path impossible to prove untouched.
abstract class OfflineDeviceLink {
  /// True after a reading has actually arrived over the board's AP.
  bool get isOfflineDirect;

  /// Seeds the board's clock from this phone. Needed for dated feeds when
  /// NTP is unreachable.
  Future<bool> seedClock(int epochSeconds);

  Future<bool> feed(int grams, int pwm);

  Future<bool> command(String type, {int? grams, int? pwm, int? value});

  /// The board's cached schedules, in its own index order. Each map has
  /// `index`, `time`, `feed_date` (nullable), `grams`, `rotator_pwm`,
  /// `active` and `device_id` (the board repeats its id on every row so
  /// the transport can reject a stranger's response).
  Future<List<Map<String, dynamic>>?> readSchedules();

  /// Adds a slot, or overwrites [index] when one is given.
  Future<bool> addSchedule({
    required String time,
    String? feedDate,
    required int grams,
    required int pwm,
    bool active = true,
    int? index,
  });

  Future<bool> removeSchedule(int index);
}
