import 'local_esp32_service.dart';

/// No-op in the Supabase build.
///
/// In the old Firebase build the phone mirrored the current reading into
/// Realtime Database. That is unnecessary now: the ESP32 writes every
/// reading straight into Supabase, and the app subscribes to it live, so
/// there is nothing for the phone to relay. Kept as a stub so the single
/// call site (MainTabScaffold) compiles unchanged.
class RealtimeSyncService {
  Future<void> pushCurrentReading(LocalEsp32Service esp32) async {
    // Intentionally does nothing — the device is the writer now.
  }
}
