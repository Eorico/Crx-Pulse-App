import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/firmware_spec.dart';
import '../core/firmware_status.dart';
import '../core/ph_reading_filter.dart';
import 'device_ap_client.dart';
import 'offline_device_link.dart';
import 'offline_reading_store.dart';
import 'offline_sync_service.dart';
import 'reading_cache.dart';

/// Live sensor readings, over whichever of two links is carrying them:
///
///   ESP32 -> Supabase readings table -> this .stream() -> the UI
///   ESP32 -> its own WiFi -> /api/live -> this poller -> the UI
///
/// The first is the normal path. The second is for when the tank has no
/// WiFi: the firmware raises its own access point (see
/// serviceAccessPoint() in crx_pulse.ino), the phone joins it, and the
/// readings come straight off the device — stored on this phone and
/// pushed up the moment there is internet again.
///
/// Both paths end in the same [_onRows], so there is exactly one place
/// that decides what a reading means: one freshness rule, one set of
/// per-sensor validity gates, one cache write. The second link adds a
/// source, not a second set of rules.
///
/// The class name, public fields, and the Esp32ConnectionState enum are
/// unchanged, so every screen that reads them keeps working. Connection
/// semantics are identical: anything other than a fresh reading clears
/// every value to null so the UI shows "Not Connected" everywhere rather
/// than a stale number.
enum Esp32ConnectionState { connecting, connected, unreachable }

/// Which link carried the reading on screen.
///
/// Recorded rather than inferred from [Esp32ConnectionState], because a
/// reading off the device's own WiFi makes the service `connected` too —
/// and if that counted as the cloud being alive, the fallback poller
/// would switch itself off after its first success.
enum ReadingSource { cloud, deviceAp }

/// A reading counts as live if it arrived within this window: three of
/// the firmware's push intervals, so one dropped or slow insert does
/// not read as a disconnection. Defined in [FirmwareSpec] alongside the
/// firmware's own CLOUD_READING_INTERVAL so the two stay in step.
const Duration _freshWindow = FirmwareSpec.freshWindow;

class LocalEsp32Service extends ChangeNotifier implements OfflineDeviceLink {
  LocalEsp32Service({
    ReadingCache cache = const ReadingCache(),
    DeviceApClient apClient = const DeviceApClient(),
    OfflineReadingStore offlineStore = const OfflineReadingStore(),
    OfflineSyncService? sync,
  })  : _cache = cache,
        _ap = apClient,
        _offline = offlineStore,
        _sync = sync ?? OfflineSyncService(store: offlineStore);

  final SupabaseClient _sb = Supabase.instance.client;

  Esp32ConnectionState state = Esp32ConnectionState.connecting;
  String? errorMessage;

  // Six readings the app displays.
  double? ph;
  double? ammonia;        // mg/L estimate
  double? turbidity;      // percent (0 = clear, 100 = highly turbid)
  String? turbidityStatus;
  double? waterTempC;
  double? ambientTempC;   // DHT11 — the app's "Housing Temperature"
  bool fanActive = false;
  int fanDutyPercent = 0;

  String? macAddress;     // retained for API compatibility; unused now
  DateTime? lastUpdated;

  /// Build tag read from the device's `/api/status` while on its own WiFi.
  /// Null until that endpoint answers, or forever on older firmware.
  String? firmwareBuildTag;

  /// True while the values above came from the on-device cache rather
  /// than from a live reading. The UI labels them with their age so a
  /// remembered value is never mistaken for a current one.
  bool isShowingCached = false;

  /// True while the readings on screen arrived over the device's own
  /// WiFi instead of through the cloud.
  ///
  /// Not the same as [isShowingCached]: these readings are live, taken
  /// seconds ago. What is missing is the cloud, so they exist only on
  /// this phone until [pendingUploadCount] drains.
  @override
  bool isOfflineDirect = false;

  /// Readings captured off the device's own WiFi that have not reached
  /// Supabase yet.
  int get pendingUploadCount => _sync.pending;

  final ReadingCache _cache;
  final DeviceApClient _ap;
  final OfflineReadingStore _offline;
  final OfflineSyncService _sync;
  final PhReadingFilter _phFilter = PhReadingFilter();

  /// Id reported by the board's own AP. Offline actions need the real
  /// DEVICE_ID in their body; the paired id from Supabase may not exist
  /// yet on a phone that has never been online.
  String? apDeviceId;

  String? get _actionDeviceId => apDeviceId ?? _deviceId;

  // ---- Offline actions (OfflineDeviceLink) ---------------------------
  //
  // Thin forwards. The board checks the device id in every request body,
  // so a stranger on 192.168.4.1 cannot drive the actuators even if the
  // app is briefly pointed at one.

  @override
  Future<bool> seedClock(int epochSeconds) =>
      _ap.postTime(epochSeconds, _actionDeviceId ?? '');

  @override
  Future<bool> feed(int grams, int pwm) =>
      _ap.postFeed(_actionDeviceId ?? '', grams, pwm);

  @override
  Future<bool> command(String type, {int? grams, int? pwm, int? value}) =>
      _ap.postCommand(_actionDeviceId ?? '', type,
          grams: grams, pwm: pwm, value: value);

  @override
  Future<List<Map<String, dynamic>>?> readSchedules() =>
      _ap.fetchSchedules();

  @override
  Future<bool> addSchedule({
    required String time,
    String? feedDate,
    required int grams,
    required int pwm,
    bool active = true,
    int? index,
  }) =>
      _ap.postSchedule(_actionDeviceId ?? '',
          time: time,
          feedDate: feedDate,
          grams: grams,
          pwm: pwm,
          active: active,
          index: index);

  @override
  Future<bool> removeSchedule(int index) =>
      _ap.deleteSchedule(_actionDeviceId ?? '', index);

  StreamSubscription<List<Map<String, dynamic>>>? _sub;
  Timer? _staleTimer;
  bool _disposed = false;
  bool _starting = false;
  String? _deviceId;

  // ---- offline fallback ---------------------------------------------

  /// How often to ask the device's own WiFi for a reading: the same
  /// cadence the firmware pushes to the cloud, so the dashboard updates
  /// at the same rate offline as online and the buffer fills at the rate
  /// the cloud would have been filled.
  static const Duration _apPollInterval = FirmwareSpec.readingInterval;

  /// Longest gap between probes once nothing is answering on the
  /// device's AP address — which is the ordinary case, every time this
  /// phone is on the tank's real WiFi.
  static const Duration _apProbeMaxGap = Duration(seconds: 15);

  /// The build tag is static until a reflash. One read at first contact is
  /// enough; the interval only makes a reflash visible without a restart.
  static const Duration _firmwareTagRefreshInterval = Duration(seconds: 60);
  DateTime? _firmwareTagCheckedAt;
  bool _firmwareTagFetchInFlight = false;

  /// Bumped on sign-out. A status request already in flight belongs to
  /// the board we just left, so its answer must never paint the next one.
  int _firmwareTagEpoch = 0;

  /// Retry the cloud after this many buffered readings — about once a
  /// minute at the poll interval above.
  ///
  /// A phone can be joined to the device's access point on WiFi and
  /// still have a route out over cellular. Nothing available here tells
  /// that apart from being genuinely offline, so the buffer would
  /// otherwise grow for hours with the cloud reachable the whole time.
  static const int _flushEveryNBuffered = 20;

  Timer? _apTimer;
  StreamSubscription<List<ConnectivityResult>>? _conn;
  bool _apPollInFlight = false;

  // The board has no battery-backed clock. Keep trying until the phone's
  // seed is acknowledged; otherwise one dropped POST silently disables
  // every dated feed until the app is restarted.
  bool _clockSeedAcknowledged = false;
  bool _clockSeedInFlight = false;
  DateTime? _nextApProbe;
  int _apMisses = 0;
  int _bufferedSinceFlush = 0;

  /// When the last reading that came through the CLOUD was recorded.
  /// Drives [_cloudIsFresh]; never set from an offline reading.
  DateTime? _lastCloudAt;

  bool get isTracking => state == Esp32ConnectionState.connected;

  /// Whether the cloud stream is currently feeding us fresh readings.
  ///
  /// While this holds, the fallback poller stays silent: there is
  /// nothing it could add, and probing an address that is not there
  /// would cost a timeout every few seconds.
  bool get _cloudIsFresh =>
      _lastCloudAt != null &&
      DateTime.now().difference(_lastCloudAt!).abs() <= _freshWindow;

  void _clearReadings() {
    _phFilter.reset();
    ph = null;
    ammonia = null;
    turbidity = null;
    turbidityStatus = null;
    waterTempC = null;
    ambientTempC = null;
    fanActive = false;
    fanDutyPercent = 0;
    isShowingCached = false;
    isOfflineDirect = false;
    _clockSeedAcknowledged = false;
  }

  /// Paint the last known reading before the network is touched.
  ///
  /// This is the whole point of the cache: resolving the paired device
  /// and opening the subscription are two round trips, and until they
  /// finish the dashboard has nothing to draw. Restoring here means the
  /// values are on screen in the time it takes to read one row of
  /// SQLite, and the live stream simply overwrites them when it opens.
  ///
  /// Only restores a reading that is still inside [_freshWindow].
  ///
  /// That keeps the standing rule intact: when the device is not being
  /// tracked, no last reading is shown. An older cached value would be
  /// cleared by the staleness check within seconds anyway, so painting
  /// it first would only produce a flash of a number the dashboard is
  /// required not to display.
  ///
  /// Never upgrades the connection state — a remembered value is not
  /// evidence the device is reachable now.
  Future<void> _restoreFromCache() async {
    if (lastUpdated != null) return;   // a live reading already won

    final cached = await _cache.load();
    if (cached == null || _disposed || lastUpdated != null) return;

    final age = DateTime.now().difference(cached.recordedAt).abs();
    if (age > _freshWindow) return;

    _phFilter.seed(cached.ph);
    ph              = cached.ph;
    ammonia         = cached.ammonia;
    turbidity       = cached.turbidity;
    turbidityStatus = cached.turbidityStatus;
    waterTempC      = cached.waterTempC;
    ambientTempC    = cached.ambientTempC;
    fanActive       = cached.fanActive;
    fanDutyPercent  = cached.fanDutyPercent;
    lastUpdated     = cached.recordedAt;
    isShowingCached = true;
    notifyListeners();
  }

  /// Kept named startPolling() so call sites don't change. Resolves the
  /// user's paired device, then opens a live stream of its newest reading.
  /// Safe to call again after pairing — the early-return paths below do
  /// not create a subscription, so a later call re-attempts cleanly.
  Future<void> startPolling() async {
    // Four screens call this, pull-to-refresh calls it, and the
    // connectivity watch below now calls it too. `_sub != null` alone
    // does not keep them apart: two callers can both get past it while
    // the first is still awaiting the device lookup, and end up opening
    // two subscriptions to the same table.
    if (_sub != null || _starting) return;
    _starting = true;
    try {
      await _openCloudStream();
    } finally {
      _starting = false;
    }
  }

  Future<void> _openCloudStream() async {
    // Before any await, so the dashboard fills immediately rather than
    // after the device lookup and the subscription handshake.
    await _restoreFromCache();

    // Deliberately ahead of every early return below. All three of them
    // — no session, no paired device, no internet — are exactly the
    // situations in which the device's own WiFi is the only link there
    // is, so the fallback cannot be set up after them.
    _startOfflineFallback();

    final uid = _sb.auth.currentUser?.id;
    if (uid == null) {
      _clearReadings();
      lastUpdated = null;
      unawaited(_cache.clear());
      state = Esp32ConnectionState.unreachable;
      errorMessage = 'Not signed in.';
      notifyListeners();
      return;
    }

    // Which device is paired to this user?
    try {
      final devs = await _sb.from('devices').select('device_id').eq('user_id', uid).limit(1);
      if (devs.isEmpty) {
        _clearReadings();
        lastUpdated = null;
        unawaited(_cache.clear());
        state = Esp32ConnectionState.unreachable;
        errorMessage = 'No paired device yet — pair one in Setup.';
        notifyListeners();
        return;
      }
      _deviceId = devs.first['device_id'] as String?;
    } catch (_) {
      // Being unable to reach the cloud says nothing about the DEVICE.
      // If the fallback poller is already feeding us straight off its
      // access point, those readings are seconds old and live, and a
      // failed cloud lookup must not wipe them off the screen.
      if (!isOfflineDirect) {
        _clearReadings();
        state = Esp32ConnectionState.unreachable;
        errorMessage =
            "Can't reach the cloud. Check this phone's internet connection.";
        notifyListeners();
      }
      return;
    }

    _sub = _sb
        .from('readings')
        .stream(primaryKey: ['id'])
        .eq('device_id', _deviceId!)
        .order('recorded_at', ascending: false)
        .limit(1)
        .listen(_onRows, onError: (_) {
      if (isOfflineDirect) return;   // see the catch above
      _clearReadings();
      state = Esp32ConnectionState.unreachable;
      errorMessage = "Can't reach the cloud. Check this phone's internet connection.";
      if (!_disposed) notifyListeners();
    });

    // Flip to "Not Connected" by the clock when the device stops sending.
    _staleTimer ??= Timer.periodic(const Duration(seconds: 5), (_) => _reevaluate());
  }

  void stopPolling() {
    _sub?.cancel();
    _sub = null;
    _staleTimer?.cancel();
    _staleTimer = null;
    _apTimer?.cancel();
    _apTimer = null;
    _conn?.cancel();
    _conn = null;
    _lastCloudAt = null;
    _nextApProbe = null;
    _apMisses = 0;
    _bufferedSinceFlush = 0;
    _deviceId = null;
    apDeviceId = null;
    firmwareBuildTag = null;
    _firmwareTagCheckedAt = null;
    _firmwareTagFetchInFlight = false;
    _firmwareTagEpoch++;
    _clearReadings();
    state = Esp32ConnectionState.connecting;
    notifyListeners();

    // Buffered readings are NOT dropped here. stopPolling() runs on
    // sign-out, and those readings are the tank's history, not this
    // session's: each one carries the device_id it was taken from, so
    // whenever somebody signs in again they go up to the account that
    // owns that device.
  }

  // =====================================================================
  // OFFLINE FALLBACK — readings straight off the device's own WiFi
  // =====================================================================

  /// Starts the fallback poller, the connectivity watch and the stale
  /// check. Idempotent: every call site of [startPolling] reaches it,
  /// including pull-to-refresh.
  void _startOfflineFallback() {
    _apTimer ??=
        Timer.periodic(_apPollInterval, (_) => unawaited(_pollDeviceAp()));
    _conn ??=
        Connectivity().onConnectivityChanged.listen(_onConnectivityChanged);

    // The stale check used to be started only on the success path. It
    // has to run here too, or an offline reading would never age out of
    // the dashboard once the phone leaves the tank's AP. It is a no-op
    // while lastUpdated is null, so starting it early changes nothing
    // for the cloud path.
    _staleTimer ??=
        Timer.periodic(const Duration(seconds: 5), (_) => _reevaluate());

    // Don't wait for the first tick. If the phone is already on the
    // device's AP when the app opens, the dashboard should fill now.
    unawaited(_pollDeviceAp());

    // Surface a queue left over from a previous run before anything is
    // pushed, so the number on screen is the real one.
    unawaited(_sync.refresh().then((n) {
      if (n > 0 && !_disposed) notifyListeners();
    }));
  }

  /// Reads the device's build tag without holding up the live reading.
  ///
  /// A failed status request is ordinary — the firmware only serves it on
  /// its own WiFi — so it leaves the previous tag alone and never changes
  /// connection state.
  void _refreshFirmwareBuildTag() {
    if (_disposed) return;

    final now = DateTime.now();
    if (!shouldRefreshFirmwareTag(
      now: now,
      lastChecked: _firmwareTagCheckedAt,
      inFlight: _firmwareTagFetchInFlight,
      interval: _firmwareTagRefreshInterval,
    )) {
      return;
    }

    final epoch = _firmwareTagEpoch;
    _firmwareTagCheckedAt = now;
    _firmwareTagFetchInFlight = true;
    unawaited(_ap.fetchStatus().then((status) {
      if (_disposed || epoch != _firmwareTagEpoch) return;
      _firmwareTagFetchInFlight = false;
      if (status == null) return;
      final tag = buildTagFromStatus(status);
      if (tag == null || tag == firmwareBuildTag) return;
      firmwareBuildTag = tag;
      notifyListeners();
    }, onError: (_) {
      if (_disposed || epoch != _firmwareTagEpoch) return;
      _firmwareTagFetchInFlight = false;
    }));
  }

  /// Asks the device's access point for its current reading, buffers it,
  /// and paints it.
  ///
  /// Does nothing at all when the cloud is feeding us, when a probe is
  /// already in flight, or while backing off from an address that is not
  /// answering.
  Future<void> _pollDeviceAp() async {
    if (_disposed || _apPollInFlight) return;
    if (_cloudIsFresh) return;
    if (_nextApProbe != null && DateTime.now().isBefore(_nextApProbe!)) return;

    _apPollInFlight = true;
    try {
      final live = await _ap.fetchLive();
      if (_disposed) return;

      if (live == null) {
        _apMisses++;
        // 3 s, 6 s, 12 s, then 15 s. On the tank's normal WiFi nothing
        // will ever answer, and this is the cost of asking.
        final gap = _apPollInterval * (1 << (_apMisses > 3 ? 3 : _apMisses));
        _nextApProbe =
            DateTime.now().add(gap > _apProbeMaxGap ? _apProbeMaxGap : gap);
        return;
      }

      _apMisses = 0;
      _nextApProbe = null;

      // Joining the wrong tank's access point must not file its readings
      // under this account. When the paired device is known, refuse any
      // other; when the app has never been online it cannot know, and
      // the AP's WPA2 password is the only authentication available —
      // the same one the user needed to get onto the network.
      final liveDeviceId = live['device_id'] as String?;
      if (_deviceId != null && liveDeviceId != _deviceId) return;
      if (apDeviceId != liveDeviceId) {
        apDeviceId = liveDeviceId;
        _clockSeedAcknowledged = false;   // a different board, a different clock
      }

      // Only after the device id check: a stranger on 192.168.4.1 must
      // never be asked for, or believed about, its firmware version.
      _refreshFirmwareBuildTag();

      // NTP needs internet, so an offline board has no clock. The phone is
      // the only trustworthy clock in the room. Retry on later contacts
      // while the seed is unacknowledged; never overlap two seed requests.
      if (!_clockSeedAcknowledged && !_clockSeedInFlight) {
        _clockSeedInFlight = true;
        unawaited(seedClock(
          DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000,
        ).then((ok) {
          _clockSeedInFlight = false;
          if (ok && !_disposed) _clockSeedAcknowledged = true;
        }));
      }

      final row = Map<String, dynamic>.from(live);
      // The firmware sends no timestamp on purpose: offline it has no
      // trustworthy clock, since NTP needs internet. This phone's clock
      // is the only real one in the room, and the row cannot be stored
      // or pushed without one.
      row['recorded_at'] = DateTime.now().toUtc().toIso8601String();

      // Stored BEFORE it is painted. If the app is killed in the next
      // instant, a reading on disk is worth more than a reading that was
      // briefly on screen.
      _sync.noteBuffered(await _offline.add(row));
      if (_disposed) return;

      if (++_bufferedSinceFlush >= _flushEveryNBuffered) {
        _bufferedSinceFlush = 0;
        unawaited(_flushOffline());   // fails harmlessly with no route
      }

      // Buffering happens whether or not anybody is signed in: these
      // readings belong to the tank, not to the session, and they are
      // still owed to the cloud. Showing them is a different question —
      // a signed-out app shows nothing, which is the rule startPolling()
      // has already applied, and repainting here would undo it.
      if (_sb.auth.currentUser == null) return;

      _onRows([row], source: ReadingSource.deviceAp);
    } catch (_) {
      // A failed buffer write must not take the poller down with it; the
      // next tick tries again.
    } finally {
      _apPollInFlight = false;
    }
  }

  void _onConnectivityChanged(List<ConnectivityResult> results) {
    if (_disposed) return;
    if (results.every((r) => r == ConnectivityResult.none)) return;

    // Having an interface is not having internet — the device's own
    // access point is a wifi interface with nothing behind it — so both
    // of these are written to fail harmlessly when there is no route
    // out, rather than being gated on a guess about which network this
    // is.
    unawaited(_flushOffline());
    if (_sub == null) unawaited(startPolling());

    // The network changed underneath us, so don't serve out a backoff
    // earned on the previous one.
    _apMisses = 0;
    _nextApProbe = null;
    unawaited(_pollDeviceAp());
  }

  Future<void> _flushOffline() async {
    final pushed = await _sync.flush();
    if (pushed > 0 && !_disposed) notifyListeners();
  }

  /// The one place a reading becomes what the dashboard shows,
  /// whichever link brought it.
  ///
  /// [source] defaults to the cloud so this is still assignable to
  /// `.listen()` as it was; the fallback poller passes it explicitly.
  void _onRows(List<Map<String, dynamic>> rows,
      {ReadingSource source = ReadingSource.cloud}) {
    if (_disposed) return;

    if (rows.isEmpty) {
      _clearReadings();
      state = Esp32ConnectionState.connecting;
      errorMessage = 'Waiting for the first reading from your device.';
      notifyListeners();
      return;
    }

    final d = rows.first;
    final ts = d['recorded_at'];
    final readingTime = ts is String ? (DateTime.tryParse(ts) ?? DateTime.now()) : DateTime.now();

    final fresh = DateTime.now().difference(readingTime).abs() <= _freshWindow;
    if (!fresh) {
      // A stale cloud row means the device has not reached the cloud
      // lately — which is exactly the situation the fallback exists for.
      // It says nothing about the readings coming off the device's own
      // WiFi, and those are the newer information.
      if (source == ReadingSource.cloud && isOfflineDirect) return;
      lastUpdated = readingTime.toLocal();
      _clearReadings();
      state = Esp32ConnectionState.unreachable;
      errorMessage = 'Not Connected — no live readings from your device.';
      notifyListeners();
      return;
    }

    double? asNum(String k) => (d[k] as num?)?.toDouble();
    // A sensor the firmware flagged invalid is shown as "Not Connected".
    bool ok(String k) => d[k] is bool ? d[k] as bool : true;

    ph              = ok('ph_valid') ? _phFilter.accept(asNum('ph')) : null;
    ammonia         = ok('ammonia_valid') ? asNum('ammonia') : null;
    turbidity       = ok('turbidity_valid') ? asNum('turbidity') : null;
    turbidityStatus = d['turbidity_status'] as String?;
    waterTempC      = ok('water_temp_valid') ? asNum('water_temp_c') : null;
    ambientTempC    = ok('ambient_valid') ? asNum('ambient_temp_c') : null;
    fanActive       = d['fan_active'] as bool? ?? false;
    fanDutyPercent  = (d['fan_percent'] as num?)?.toInt() ?? 0;

    lastUpdated = readingTime.toLocal();
    isShowingCached = false;
    isOfflineDirect = source == ReadingSource.deviceAp;

    if (source == ReadingSource.cloud) {
      _lastCloudAt = readingTime;
      // A reading that arrived through the cloud is proof this phone has
      // internet — better proof than any connectivity API gives — so
      // this is where a buffered queue gets drained. Cheap when there is
      // nothing queued: the service returns without touching the
      // network or the database.
      unawaited(_flushOffline());
    }

    // Remember it for the next cold start. Fire-and-forget: a failed
    // cache write must not delay or disturb the live update.
    unawaited(_cache.save(CachedReading(
      ph: ph,
      ammonia: ammonia,
      turbidity: turbidity,
      turbidityStatus: turbidityStatus,
      waterTempC: waterTempC,
      ambientTempC: ambientTempC,
      fanActive: fanActive,
      fanDutyPercent: fanDutyPercent,
      recordedAt: lastUpdated!,
    )));

    _reevaluate(justReceived: true);
  }

  void _reevaluate({bool justReceived = false}) {
    if (_disposed || lastUpdated == null) return;

    final fresh = DateTime.now().difference(lastUpdated!).abs() <= _freshWindow;

    if (!fresh) {
      if (state != Esp32ConnectionState.unreachable) {
        _clearReadings();
        state = Esp32ConnectionState.unreachable;
        errorMessage = 'Not Connected — no live readings from your device.';
        notifyListeners();
      }
      return;
    }

    const next = Esp32ConnectionState.connected;
    errorMessage = null;
    if (next != state || justReceived) {
      state = next;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _sub?.cancel();
    _staleTimer?.cancel();
    _apTimer?.cancel();
    _conn?.cancel();
    super.dispose();
  }
}
