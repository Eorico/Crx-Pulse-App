import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/theme.dart';
import 'core/supabase_config.dart';
import 'services/local_esp32_service.dart';
import 'services/floating_widget_position_provider.dart';
import 'services/local_feeding_provider.dart';
import 'services/local_notification_provider.dart';
import 'services/local_analytics_provider.dart';
import 'services/device_provider.dart';
import 'services/device_log_provider.dart';
import 'services/device_test_provider.dart';
import 'services/auth_service.dart';
import 'screens/main_tab_scaffold.dart';
import 'screens/auth/login_screen.dart';
import 'screens/splash/splash_screen.dart';
import 'widgets/motion.dart';

/// Architecture now: ESP32 -> WiFi router -> Supabase (Postgres +
/// PostgREST + Realtime) -> this app. There is no backend server to
/// deploy — the ESP32 inserts readings straight into the `readings`
/// table and the app subscribes to it live. Feeding schedules and
/// commands are plain rows the app writes and the ESP32 reads.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.anonKey,
  );

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
        ChangeNotifierProvider(create: (_) => DeviceProvider()),
        // Registered at the root, not inside the Settings screen: the
        // log feed must survive that screen being rebuilt as you swipe
        // between tabs, and Settings' dispose() reads it to switch
        // verbose streaming off.
        ChangeNotifierProvider(create: (_) => DeviceLogProvider()),
        ChangeNotifierProvider(create: (_) => DeviceTestProvider()),
      ],
      child: MaterialApp(
        title: 'CRX-Pulse',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        // 3-second in-app splash, then the auth gate.
        home: const SplashScreen(next: _AuthGate()),
      ),
    );
  }
}

/// Shows Login when signed out, MainTabScaffold when signed in — driven
/// by Supabase Auth's session stream.
class _AuthGate extends StatefulWidget {
  const _AuthGate();

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  bool _deviceStarted = false;

  void _onSignedIn(BuildContext context) {
    if (_deviceStarted) return;
    _deviceStarted = true;
    context.read<DeviceProvider>().start();
  }

  void _onSignedOut(BuildContext context) {
    if (!_deviceStarted) return;
    _deviceStarted = false;
    context.read<LocalEsp32Service>().stopPolling();
    context.read<DeviceProvider>().stop();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AuthService.isProcessingRegistration,
      builder: (context, isRegistering, _) {
        if (isRegistering) {
          return const Scaffold(body: Center(child: CircularProgressIndicator(color: AppColors.primary)));
        }

        return StreamBuilder<AuthState>(
          stream: Supabase.instance.client.auth.onAuthStateChange,
          builder: (context, snapshot) {
            final session = Supabase.instance.client.auth.currentSession;
            final signedIn = session != null;

            if (signedIn) {
              WidgetsBinding.instance.addPostFrameCallback((_) => _onSignedIn(context));
            } else {
              WidgetsBinding.instance.addPostFrameCallback((_) => _onSignedOut(context));
            }

            // Signing in and out cross-fades rather than cutting
            // straight from the login form to the dashboard. Keyed on
            // the session state only, so a rebuild for any other reason
            // does not re-run the transition.
            return SwapIn(
              swapKey: signedIn,
              duration: AppMotion.slow,
              child: signedIn ? const MainTabScaffold() : const LoginScreen(),
            );
          },
        );
      },
    );
  }
}
