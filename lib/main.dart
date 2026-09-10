import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'core/theme.dart';
import 'services/local_esp32_service.dart';
import 'services/floating_widget_position_provider.dart';
import 'services/local_feeding_provider.dart';
import 'services/local_notification_provider.dart';
import 'services/local_analytics_provider.dart';
import 'services/firebase_sync_service.dart';
import 'screens/main_tab_scaffold.dart';
import 'screens/auth/login_screen.dart';
import 'firebase_options.dart';

/// IMPORTANT: firebase_options.dart does NOT exist until you run
/// `flutterfire configure` against your real Firebase project (see
/// the setup guide) - this import will fail to resolve until then.
/// That's expected and correct; it's not something to hand-write.

/// ESP32 <-> Flutter stays local WiFi only, exactly as before -
/// Firebase's ONLY role is account auth (replacing the old JWT
/// backend) and a background sync of SQLite sensor history whenever
/// the phone has internet, for cross-device/cloud access to your
/// data. The ESP32 itself never talks to Firebase at all.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
  ));

  runApp(const CrxPulseApp());
}

class CrxPulseApp extends StatelessWidget {
  const CrxPulseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LocalEsp32Service()),
        ChangeNotifierProvider(create: (_) => FloatingWidgetPositionProvider()),
        ChangeNotifierProvider(create: (_) => LocalFeedingProvider()),
        ChangeNotifierProvider(create: (_) => LocalNotificationProvider()),
        ChangeNotifierProvider(create: (_) => LocalAnalyticsProvider()),
      ],
      child: MaterialApp(
        title: 'CRX-Pulse',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        home: const _AuthGate(),
      ),
    );
  }
}

/// Shows Login when signed out, MainTabScaffold when signed in -
/// FirebaseAuth's own stream handles session persistence across app
/// restarts automatically, no manual token storage needed like the
/// old backend required.
class _AuthGate extends StatefulWidget {
  const _AuthGate();

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  FirebaseSyncService? _syncService;

  void _startSyncIfNeeded(BuildContext context) {
    if (_syncService != null) return;
    _syncService = FirebaseSyncService(context.read<LocalAnalyticsProvider>());
    _syncService!.start();
  }

  @override
  void dispose() {
    _syncService?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator(color: AppColors.primary)));
        }
        if (snapshot.hasData) {
          _startSyncIfNeeded(context);
          return const MainTabScaffold();
        }
        _syncService?.dispose();
        _syncService = null;
        return const LoginScreen();
      },
    );
  }
}
