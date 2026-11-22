import 'package:supabase_flutter/supabase_flutter.dart';

import 'offline_reading_store.dart';

/// Pushes readings buffered while offline up to Supabase.
///
/// Called whenever there is evidence the phone has internet again: a
/// connectivity change, or simply a live reading arriving from the cloud
/// stream, which is proof by itself. Nothing here runs on a timer of its
/// own — a timer would be a second opinion about whether the network is
/// up, and the ones above are better informed.
///
/// The push is an upsert that ignores duplicates, against the uuid the
/// buffer assigned each row. That makes a retry safe: if a batch reached
/// the database but its response was lost, the rows come back on the
/// next attempt and collide on the primary key instead of arriving
/// twice.
class OfflineSyncService {
  OfflineSyncService({
    OfflineReadingStore store = const OfflineReadingStore(),
    SupabaseClient? client,
  })  : _store = store,
        _sb = client ?? Supabase.instance.client;

  final OfflineReadingStore _store;
  final SupabaseClient _sb;

  /// Rows per request. Small enough that a flaky reconnection loses
  /// little work on failure, large enough that draining hours of buffer
  /// is not thousands of round trips.
  static const int batchSize = 200;

  /// Ceiling on one flush, so draining a full buffer cannot hold the
  /// single `_flushing` slot for minutes. Whatever is left is picked up
  /// by the next flush, which the live cloud stream triggers every few
  /// seconds once it is running.
  static const int maxPerFlush = 2000;

  bool _flushing = false;
  bool _counted = false;
  int _pending = 0;

  /// Readings waiting to go up. Zero until [refresh] or [noteBuffered]
  /// has been called, so treat it as display-only.
  int get pending => _pending;

  bool get isFlushing => _flushing;

  /// Reads the real queue depth from disk. Worth calling once at
  /// startup, so a queue left over from a previous run is visible before
  /// anything is pushed.
  Future<int> refresh() async {
    try {
      _pending = await _store.count();
      _counted = true;
    } catch (_) {
      // A database that will not open is the store's problem to report;
      // here it only means we cannot say how deep the queue is.
    }
    return _pending;
  }

  /// Records a depth the caller already knows — [OfflineReadingStore.add]
  /// returns it — so the common path needs no COUNT query.
  void noteBuffered(int total) {
    _pending = total;
    _counted = true;
  }

  /// Pushes what it can and returns how many rows went up.
  ///
  /// Returns 0 without touching the network when there is nothing
  /// queued, nobody signed in, or a flush already running. Any failure
  /// stops the flush and leaves the remaining rows buffered; they are
  /// not lost and not reordered.
  Future<int> flush() async {
    if (_flushing) return 0;
    if (_counted && _pending == 0) return 0;
    // Buffered rows are inserted as this user, so a signed-out app has
    // to wait: the rows keep until it signs back in.
    if (_sb.auth.currentUser == null) return 0;

    _flushing = true;
    var pushed = 0;
    try {
      if (!_counted) await refresh();

      while (pushed < maxPerFlush) {
        final batch = await _store.nextBatch(limit: batchSize);
        if (batch.isEmpty) break;

        await _sb.from('readings').upsert(batch, ignoreDuplicates: true);
        await _store.remove(batch.map((r) => r['id'] as String));

        pushed += batch.length;
        _pending = _pending > batch.length ? _pending - batch.length : 0;
      }
      // Only trust the arithmetic once the queue claims to be empty;
      // then confirm it against disk.
      if (_pending == 0) await refresh();
    } catch (_) {
      // Offline again mid-flush, RLS refusal, malformed row — all leave
      // the untransmitted rows where they are. The count may now be
      // stale, so re-read it rather than guess.
      await refresh();
    } finally {
      _flushing = false;
    }
    return pushed;
  }
}
