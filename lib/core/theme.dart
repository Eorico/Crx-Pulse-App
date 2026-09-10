import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

class AppColors {
  static const primary = Color(0xFF3D5A3D);
  static const primaryDark = Color(0xFF2C4530);
  static const primaryLight = Color(0xFF7AA87A);
  static const accent = Color(0xFF8B6F47);
  static const background = Color(0xFFF5F5DC);
  static const surface = Color(0xFFFFFFFF);
  static const border = Color(0xFFE5E7EB);
  static const textPrimary = Color(0xFF0F172A);
  static const textSecondary = Color(0xFF6B7280);
  static const textMuted = Color(0xFF9CA3AF);
  static const success = Color(0xFF22C55E);
  static const warning = Color(0xFFF59E0B);
  static const danger = Color(0xFFEF4444);
}

class AppShadows {
  static List<BoxShadow> card = [
    BoxShadow(color: Colors.black.withValues(alpha: 0.08), offset: const Offset(0, 6), blurRadius: 12),
  ];
}

enum DeviceStatus { online, offline, neverConnected, disabled }

class DeviceStatusStyle {
  final Color color;
  final String label;
  const DeviceStatusStyle(this.color, this.label);

  static const Map<DeviceStatus, DeviceStatusStyle> map = {
    DeviceStatus.online: DeviceStatusStyle(AppColors.success, 'Online'),
    DeviceStatus.offline: DeviceStatusStyle(AppColors.danger, 'Offline'),
    DeviceStatus.neverConnected: DeviceStatusStyle(AppColors.warning, 'Never Connected'),
    DeviceStatus.disabled: DeviceStatusStyle(AppColors.textMuted, 'Disabled'),
  };
}

class SystemStatusStyle {
  final String label;
  final double barFraction;
  final String caption;
  const SystemStatusStyle(this.label, this.barFraction, this.caption);

  static const Map<String, SystemStatusStyle> map = {
    'healthy': SystemStatusStyle('Healthy', 0.85, 'All systems operating normally'),
    'warning': SystemStatusStyle('Warning', 0.50, 'Some parameters need attention'),
    'unknown': SystemStatusStyle('Unknown', 0.20, 'Waiting for sensor data'),
  };
}

class AppTheme {
  static ThemeData light() {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary, primary: AppColors.primary, surface: AppColors.surface),
      // Professional polish: Android's default page transitions are
      // abrupt (a flat fade/slide-up). Using iOS's smooth
      // slide-from-right transition on BOTH platforms gives the app
      // a more premium, consistent feel regardless of which OS it's
      // running on - a small, well-known technique for closing the
      // "this feels like a generic Android app" gap.
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
      splashFactory: InkSparkle.splashFactory,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppColors.border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppColors.border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary, foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.35),
          disabledForegroundColor: Colors.white70,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), elevation: 0,
        ),
      ),
      // These four theme extensions weren't set before - each screen
      // that used a Card, Dialog, SnackBar, or OutlinedButton was
      // falling back to Flutter's generic Material defaults (sharp
      // corners, stark white dialogs) instead of matching the rest
      // of the app's rounded, soft-shadowed language. Setting them
      // once here fixes every occurrence app-wide simultaneously.
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.primary, width: 1.2),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: AppColors.border)),
        margin: EdgeInsets.zero,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titleTextStyle: const TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700),
        contentTextStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 14, height: 1.4),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.textPrimary,
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: AppColors.primary,
        selectionColor: AppColors.primary.withValues(alpha: 0.25),
        selectionHandleColor: AppColors.primary,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.primary),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? AppColors.primary : null),
        trackColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? AppColors.primary.withValues(alpha: 0.4) : null),
      ),
    );
  }
}
