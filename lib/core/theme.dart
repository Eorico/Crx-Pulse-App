import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

/// PALETTE — unchanged. These are exactly the project's existing colors;
/// the Claymorphism restyle changes shadows/shape/softness only, never
/// the hues.
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

  /// Clay surface tint — a hair warmer than pure white so raised clay
  /// reads against the beige background. Still effectively "white".
  static const clayFill = Color(0xFFFFFFFF);

  /// Background color of the mascot artwork on the Dashboard hero card.
  /// The hero card is painted this exact color so the card and the
  /// mascot blend into one seamless panel (no visible square behind the
  /// crayfish). If the mascot's actual backdrop is a different shade,
  /// change ONLY this hex to match it — the card follows automatically.
  static const mascotCardBg = Color(0xFFEAF3E7); // soft sage tint
  /// Text/foreground color used on top of [mascotCardBg].
  static const mascotCardFg = Color(0xFF2C4530); // = primaryDark
}

/// CLAYMORPHISM shadow tokens.
///
/// The clay look is a two-tone soft shadow: a diffuse DARK shadow on the
/// bottom-right and a soft LIGHT highlight on the top-left, with a large
/// corner radius and no hard border — giving surfaces an inflated, soft
/// "pressed from clay" feel. Flutter's BoxShadow can't do a true inner
/// shadow, so raised surfaces use the outer two-tone pair, and "pressed"
/// surfaces swap the direction to fake an inset.
class AppShadows {
  // The light highlight is nearly white; the dark is a soft neutral.
  // Deeper, more inflated clay: a near dark edge, a far ambient dark for
  // depth, and a strong top-left light highlight that makes surfaces look
  // genuinely "pressed from clay".
  static final _dark = Colors.black.withValues(alpha: 0.14);
  static final _darkFar = Colors.black.withValues(alpha: 0.07);
  static final _darkSoft = Colors.black.withValues(alpha: 0.10);
  static final _light = Colors.white.withValues(alpha: 0.95);

  /// Default clay elevation — used everywhere the app previously wrote
  /// `AppShadows.card`, so every existing card inherits the clay look.
  static List<BoxShadow> card = [
    BoxShadow(color: _darkFar, offset: const Offset(12, 16), blurRadius: 34, spreadRadius: 1),
    BoxShadow(color: _dark, offset: const Offset(7, 8), blurRadius: 18, spreadRadius: 1),
    BoxShadow(color: _light, offset: const Offset(-7, -7), blurRadius: 16, spreadRadius: 1),
  ];

  /// Alias for readability at call sites that want to be explicit.
  static List<BoxShadow> get clay => card;

  /// A gentler clay for smaller chips / list rows.
  static List<BoxShadow> claySoft = [
    BoxShadow(color: _darkSoft, offset: const Offset(5, 6), blurRadius: 14, spreadRadius: 0.5),
    BoxShadow(color: _light, offset: const Offset(-5, -5), blurRadius: 12, spreadRadius: 0.5),
  ];

  /// Direction swapped to read as pressed/inset (for toggles, tapped states).
  static List<BoxShadow> clayPressed = [
    BoxShadow(color: _dark, offset: const Offset(-5, -5), blurRadius: 12, spreadRadius: 0.5),
    BoxShadow(color: _light, offset: const Offset(5, 5), blurRadius: 12, spreadRadius: 0.5),
  ];
}

/// Standard clay radii — bigger and softer than before (deeper clay).
class AppRadius {
  static const card = 30.0;
  static const chip = 20.0;
  static const button = 24.0;
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
  /// Pass this as `showTimePicker(builder:)`.
  ///
  /// The app-wide [InputDecorationTheme] below is a borderless, filled,
  /// 20px-radius "well" designed for form fields. The Material time
  /// picker builds its hour and minute boxes out of `InputDecorator`,
  /// so it inherited all of that: no outline, a pale fill on a pale
  /// dialog, and 18px of horizontal content padding squeezing two-digit
  /// numbers that are sized to fill their box — two washed-out, clipped
  /// rectangles where the hour/minute fields should be.
  ///
  /// Resetting `inputDecorationTheme` for the dialog hands the picker
  /// back its own styling; [TimePickerThemeData] then puts it in the
  /// app's palette deliberately instead of by accident. 24-hour entry,
  /// because that is the HH:MM format the firmware compares against.
  ///
  /// Kept here rather than inline at the call site so every picker in
  /// the app gets the same treatment, and so it can be tested.
  static Widget timePickerBuilder(BuildContext context, Widget? child) {
    final base = Theme.of(context);
    return Theme(
      data: base.copyWith(
        inputDecorationTheme: const InputDecorationTheme(),
        timePickerTheme: TimePickerThemeData(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          hourMinuteTextColor: AppColors.primaryDark,
          hourMinuteColor: hourMinuteFill,
          dialHandColor: AppColors.primary,
          dialBackgroundColor: AppColors.primary.withValues(alpha: 0.06),
          dialTextColor: AppColors.textPrimary,
          entryModeIconColor: AppColors.primary,
          helpTextStyle: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
          ),
        ),
      ),
      child: MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
  }

  /// Fill behind the picker's hour/minute numbers. Exposed so a test
  /// can assert the picker really is being themed by the code above
  /// rather than falling back to Material's defaults.
  static final Color hourMinuteFill = AppColors.primary.withValues(alpha: 0.08);

  static ThemeData light() {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary, primary: AppColors.primary, surface: AppColors.surface),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
      splashFactory: InkSparkle.splashFactory,
      // Clay inputs: soft filled wells with no hard outline.
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF1F3EF),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.chip), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.chip), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.chip), borderSide: const BorderSide(color: AppColors.primaryLight, width: 1.5)),
      ),
      // Clay buttons: rounder, chunkier, with a soft colored lift.
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary, foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.30),
          disabledForegroundColor: Colors.white70,
          padding: const EdgeInsets.symmetric(vertical: 17, horizontal: 20),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.button)),
          elevation: 4,
          shadowColor: AppColors.primaryDark.withValues(alpha: 0.5),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.primaryLight, width: 1.4),
          padding: const EdgeInsets.symmetric(vertical: 15),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.button)),
        ),
      ),
      // Clay cards: borderless, large radius (the soft shadow does the work).
      cardTheme: CardThemeData(
        color: AppColors.clayFill,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card)),
        margin: EdgeInsets.zero,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.clayFill,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        titleTextStyle: const TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700),
        contentTextStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 14, height: 1.4),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.textPrimary,
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
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
