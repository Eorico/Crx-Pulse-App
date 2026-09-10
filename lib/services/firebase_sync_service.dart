import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'local_analytics_provider.dart';

/// Watches for internet connectivity and, whenever it's available,
/// pushes any SQLite sensor_history rows not yet synced up to
/// Firestore, under users/{uid}/component-sensors-readings - never
/// any other user's document, since this always writes under the
/// CURRENTLY signed-in user's own UID. This is the ONLY thing that
/// talks to Firebase directly for sensor data - the ESP32 and the
/// rest of the app never touch Firebase at all, matching the
/// architecture diagram exactly (ESP32 -> Flutter -> SQLite always,
/// Firestore only when online).
class FirebaseSyncService {
  final LocalAnalyticsProvider _analytics;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  Timer? _periodicSync;

  FirebaseSyncService(this._analytics);

  void start() {
    // Sync immediately whenever connectivity is regained...
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      if (!results.contains(ConnectivityResult.none)) {
        syncNow();
      }
    });
    // ...and also on a regular timer while already online, in case a
    // connectivity-change event is ever missed.
    _periodicSync = Timer.periodic(const Duration(minutes: 5), (_) => syncNow());
    syncNow();
  }

  Future<void> syncNow() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return; // not signed in - nothing to associate the data with

    final connectivity = await Connectivity().checkConnectivity();
    if (connectivity.contains(ConnectivityResult.none)) return;

    final batch = await _analytics.getUnsyncedBatch();
    if (batch.isEmpty) return;

    final firestore = FirebaseFirestore.instance;
    final collection = firestore.collection('users').doc(user.uid).collection('component-sensors-readings');
    final writeBatch = firestore.batch();
    final syncedIds = <int>[];

    for (final row in batch) {
      final docRef = collection.doc(); // auto-generated ID - local SQLite `id` stays purely local
      writeBatch.set(docRef, {
        'ph': row['ph'],
        'ammonia': row['ammonia'],
        'turbidity': row['turbidity'],
        'waterTempC': row['water_temp_c'],
        'ambientTempC': row['ambient_temp_c'],
        'fanActive': row['fan_active'] == 1,
        'recordedAt': row['recorded_at'],
        'syncedAt': FieldValue.serverTimestamp(),
      });
      syncedIds.add(row['id'] as int);
    }

    try {
      await writeBatch.commit();
      await _analytics.markSynced(syncedIds);
    } catch (_) {
      // Left unsynced - the next periodic attempt or connectivity
      // event will retry automatically. No user-facing error here;
      // this is a background best-effort sync, not a user action.
    }
  }

  void dispose() {
    _connectivitySub?.cancel();
    _periodicSync?.cancel();
  }
}
