import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/metric_bands.dart';
import '../core/supabase_diagnosis.dart';
import 'local_db.dart';
import 'local_esp32_service.dart';

class SensorHistoryPoint {
  final double? ph;
  final double? ammonia;
  final double? turbidity;
  final double? waterTempC;
  final double? ambientTempC;
  final DateTime recordedAt;

  const SensorHistoryPoint({
    required this.ph, required this.ammonia, required this.turbidity,
    required this.waterTempC, required this.ambientTempC, required this.recordedAt,
  });

  /// Tolerant of both row sources.
  ///
  /// SQLite hands back REAL as a Dart double, but PostgREST serialises
  /// `real` columns as JSON numbers — so a pH of exactly 7 arrives as
  /// the int `7`, and the old `as double?` cast threw on it. `as num?`
  /// then .toDouble() accepts either, which is the same thing
  /// [LocalEsp32Service] does for the live reading.
  factory SensorHistoryPoint.fromMap(Map<String, dynamic> m) {
    double? n(String k) => (m[k] as num?)?.toDouble();
    final ts = m['recorded_at'];
    return SensorHistoryPoint(
      ph: n('ph'),
      ammonia: n('ammonia'),
      turbidity: n('turbidity'),
      waterTempC: n('water_temp_c'),
      ambientTempC: n('ambient_temp_c'),
      recordedAt: (ts is String ? DateTime.tryParse(ts) : null)?.toLocal() ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

/// Where the charted history came from.
enum HistorySource {
  /// Every row the device wrote to `readings` in the window.
  cloud,

  /// The phone's own once-a-minute SQLite log — the fallback used when
  /// the cloud can't be reached, so the tab still shows something.
  local,
}

/// Serves the Analytics tab.
///
/// History comes from Supabase `readings` — the table the ESP32 writes
/// to directly, which holds *every* reading it has ever taken. The
/// local SQLite `sensor_history` table is only a fallback: it is
/// written at most once a minute and only while this phone is open and
/// connected, so on its own it misses almost everything the device
/// recorded overnight or while the app was closed.
class LocalAnalyticsProvider extends ChangeNotifier {
  LocalAnalyticsProvider({SupabaseClient? client})
      : _sb = client ?? Supabase.instance.client;

  final SupabaseClient _sb;

  /// Every row in the window, oldest first.
  List<SensorHistoryPoint> history = [];
  bool isLoading = false;

  HistorySource source = HistorySource.cloud;

  /// Set when the cloud read failed and [history] fell back to local.
  SupabaseDiagnosis? diagnosis;

  /// True when the database did the bucketing and counting.
  ///
  /// The fast path: `readings_buckets` averages into time slices
  /// server-side and `readings_zone_counts` counts the distribution
  /// over every row, so the phone receives a few hundred rows instead
  /// of up to [maxPoints]. Requires supabase_performance.sql to have
  /// been run; without it both calls fail and the raw path below takes
  /// over, which is why that path is kept.
  bool serverAggregated = false;

  /// metric column -> count per zone, exact over the whole window.
  /// Empty when the raw path ran, in which case the UI counts the
  /// points it was given.
  Map<String, List<int>> zoneCounts = {};

  /// How many raw readings the window actually held, even when only
  /// bucket averages were transferred.
  int rawSampleCount = 0;

  /// True when [maxPoints] was hit and older rows in the window were
  /// left unread, so the UI can say the window is clipped rather than
  /// quietly showing a partial picture.
  bool truncated = false;

  DateTime? _lastLoggedMinute;

  /// PostgREST caps a single response (1000 rows by default), so a long
  /// window has to be walked a page at a time.
  static const int _pageSize = 1000;

  /// Ceiling on a single fetch. At the firmware's ~5 s publish rate a
  /// 30-day window is ~518k rows; reading them all would exhaust the
  /// phone long before it told the user anything useful. 50k covers
  /// about three days at that rate, or months of slower logging.
  static const int maxPoints = 50000;

  /// Bucket count asked of `readings_buckets`. Matches the app-side
  /// TrendSeries default, so the chart looks the same whichever path
  /// produced the points.
  static const int trendBuckets = 180;

  Future<void> maybeLogReading(LocalEsp32Service esp32) async {
    if (esp32.state != Esp32ConnectionState.connected) return;
    final now = DateTime.now();
    final currentMinute = DateTime(now.year, now.month, now.day, now.hour, now.minute);
    if (_lastLoggedMinute == currentMinute) return;
    _lastLoggedMinute = currentMinute;

    final db = await LocalDb.instance.database;
    await db.insert('sensor_history', {
      'ph': esp32.ph,
      'ammonia': esp32.ammonia,
      'turbidity': esp32.turbidity,
      'water_temp_c': esp32.waterTempC,
      'ambient_temp_c': esp32.ambientTempC,
      'fan_active': esp32.fanActive ? 1 : 0,
      'recorded_at': now.toIso8601String(),
      'synced_to_firebase': 0,
    });
  }

  /// [hoursBack] controls the chart window — 24 for a day, 168 for a
  /// week, 720 for a month. Pass null for everything on record.
  ///
  /// [bands] enables the server-side path: given each metric's zone
  /// boundaries, the database can return bucket averages and exact
  /// zone counts instead of every raw row. Omit it and the raw path
  /// runs, which is what happens before supabase_performance.sql has
  /// been applied.
  Future<void> fetchHistory({
    int? hoursBack = 24,
    Map<String, MetricBands> bands = const {},
  }) async {
    isLoading = true;
    notifyListeners();

    final cutoff = hoursBack == null
        ? null
        : DateTime.now().toUtc().subtract(Duration(hours: hoursBack));

    serverAggregated = false;
    zoneCounts = {};
    rawSampleCount = 0;

    if (bands.isNotEmpty) {
      try {
        await _fetchAggregated(cutoff, bands);
        isLoading = false;
        notifyListeners();
        return;
      } catch (_) {
        // The functions are probably not installed yet. Fall through
        // to the raw path rather than showing an error for something
        // that is only an optimisation.
        serverAggregated = false;
        zoneCounts = {};
      }
    }

    try {
      history = await _fetchFromCloud(cutoff);
      rawSampleCount = history.length;
      source = HistorySource.cloud;
      diagnosis = null;
    } catch (error) {
      // Say which failure this was — a missing table reads very
      // differently from a flat tyre on the network, and the old code
      // made them indistinguishable.
      diagnosis = SupabaseDiagnosis.from(error, what: 'load reading history');
      source = HistorySource.local;
      truncated = false;
      history = await _fetchFromLocal(cutoff);
      rawSampleCount = history.length;
    }

    isLoading = false;
    notifyListeners();
  }

  /// The fast path: let Postgres do the bucketing and the counting.
  ///
  /// Two round trips' worth of work instead of up to 50 pages of raw
  /// rows. At the firmware's 3 s publish rate a 30-day window is
  /// ~864,000 readings; this returns a few hundred bucket rows plus
  /// one small count row per metric, and the counts are exact over
  /// every reading rather than over whatever fitted under [maxPoints].
  ///
  /// Throws if the functions are missing, so the caller can fall back.
  Future<void> _fetchAggregated(
      DateTime? cutoff, Map<String, MetricBands> bands) async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) throw const AuthException('Not signed in.');

    final devices =
        await _sb.from('devices').select('device_id').eq('user_id', uid).limit(1);
    if (devices.isEmpty) {
      history = [];
      source = HistorySource.cloud;
      diagnosis = null;
      serverAggregated = true;
      return;
    }
    final deviceId = devices.first['device_id'] as String;

    // An open-ended window still needs concrete bounds for the SQL.
    // 1970 is safely before any reading this device could hold.
    final from = cutoff ?? DateTime.utc(1970);
    final to = DateTime.now().toUtc().add(const Duration(minutes: 1));

    final rows = await _sb.rpc('readings_buckets', params: {
      'p_device_id': deviceId,
      'p_from': from.toIso8601String(),
      'p_to': to.toIso8601String(),
      'p_buckets': trendBuckets,
    }) as List<dynamic>;

    var samples = 0;
    history = [
      for (final r in rows.cast<Map<String, dynamic>>()) ...[
        SensorHistoryPoint.fromMap({
          'ph': r['ph'],
          'ammonia': r['ammonia'],
          'turbidity': r['turbidity'],
          'water_temp_c': r['water_temp_c'],
          'ambient_temp_c': r['ambient_temp_c'],
          'recorded_at': r['bucket_at'],
        }),
      ],
    ];
    for (final r in rows.cast<Map<String, dynamic>>()) {
      samples += (r['samples'] as num?)?.toInt() ?? 0;
    }
    rawSampleCount = samples;

    // One count call per metric. Each returns a handful of integers,
    // so they go out together rather than one after another.
    final counted = await Future.wait(bands.entries.map((e) async {
      final res = await _sb.rpc('readings_zone_counts', params: {
        'p_device_id': deviceId,
        'p_from': from.toIso8601String(),
        'p_to': to.toIso8601String(),
        'p_metric': e.value.column,
        'p_cuts': e.value.cuts,
        'p_strict': e.value.strict,
      }) as List<dynamic>;

      final counts = List<int>.filled(e.value.zoneCount, 0);
      for (final row in res.cast<Map<String, dynamic>>()) {
        final z = (row['zone'] as num?)?.toInt();
        if (z != null && z >= 0 && z < counts.length) {
          counts[z] = (row['samples'] as num?)?.toInt() ?? 0;
        }
      }
      return MapEntry(e.key, counts);
    }));

    zoneCounts = Map.fromEntries(counted);
    truncated = false;
    source = HistorySource.cloud;
    diagnosis = null;
    serverAggregated = true;
  }

  /// Walks `readings` for the paired device a page at a time.
  Future<List<SensorHistoryPoint>> _fetchFromCloud(DateTime? cutoff) async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) throw const AuthException('Not signed in.');

    final devices =
        await _sb.from('devices').select('device_id').eq('user_id', uid).limit(1);
    if (devices.isEmpty) return [];
    final deviceId = devices.first['device_id'] as String;

    final rows = <SensorHistoryPoint>[];
    truncated = false;

    for (int offset = 0; offset < maxPoints; offset += _pageSize) {
      // Re-filtered every page: `.range` is an offset into the ordered
      // result, so the order and the predicate have to be identical on
      // each call or pages would overlap or skip.
      var query = _sb
          .from('readings')
          .select('ph, ammonia, turbidity, water_temp_c, ambient_temp_c, recorded_at')
          .eq('device_id', deviceId);
      if (cutoff != null) {
        query = query.gte('recorded_at', cutoff.toIso8601String());
      }

      // Newest first. If the window holds more than [maxPoints] the
      // readings that get dropped are then the oldest ones, which is
      // the right way round — a clipped chart should still end at the
      // present moment.
      final page = await query
          .order('recorded_at', ascending: false)
          .range(offset, offset + _pageSize - 1);

      rows.addAll(page.map(SensorHistoryPoint.fromMap));

      // A short page is the last page.
      if (page.length < _pageSize) {
        return rows.reversed.toList();
      }
    }

    truncated = true;
    return rows.reversed.toList();
  }

  Future<List<SensorHistoryPoint>> _fetchFromLocal(DateTime? cutoff) async {
    final db = await LocalDb.instance.database;
    // recorded_at is written as a local-time ISO string here, unlike
    // the cloud's UTC timestamptz, so compare against local time.
    final rows = cutoff == null
        ? await db.query('sensor_history', orderBy: 'recorded_at ASC')
        : await db.query(
            'sensor_history',
            where: 'recorded_at >= ?',
            whereArgs: [cutoff.toLocal().toIso8601String()],
            orderBy: 'recorded_at ASC',
          );
    return rows.map(SensorHistoryPoint.fromMap).toList();
  }

  /// Leftover from the Firebase build, where the phone relayed history
  /// to the cloud. Nothing calls these two now: the ESP32 writes every
  /// reading to Supabase itself, so there is no backlog to upload.
  /// Kept because the column they read still exists (see [LocalDb]).
  Future<List<Map<String, dynamic>>> getUnsyncedBatch({int limit = 200}) async {
    final db = await LocalDb.instance.database;
    return db.query('sensor_history', where: 'synced_to_firebase = 0', orderBy: 'recorded_at ASC', limit: limit);
  }

  Future<void> markSynced(List<int> ids) async {
    if (ids.isEmpty) return;
    final db = await LocalDb.instance.database;
    final placeholders = List.filled(ids.length, '?').join(',');
    await db.update('sensor_history', {'synced_to_firebase': 1}, where: 'id IN ($placeholders)', whereArgs: ids);
  }
}
