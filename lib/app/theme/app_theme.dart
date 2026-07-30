import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_dimens.dart';

/// Builds [ThemeData] from the handoff tokens, with locale-aware typography:
/// Inter for Latin (EN), Cairo for Arabic (AR). Both are bundled variable TTFs,
/// so there is no network fetch and no silent fallback at first paint.
abstract final class AppTheme {
  static const String latinFont = 'Inter';
  static const String arabicFont = 'Cairo';

  static String fontFor(String languageCode) =>
      languageCode == 'ar' ? arabicFont : latinFont;

  static ThemeData light(String languageCode) =>
      _build(languageCode, Brightness.light);

  static ThemeData dark(String languageCode) =>
      _build(languageCode, Brightness.dark);

  /// The type ramp from the handoff. Sizes and weights are fixed; the family
  /// swaps with the locale.
  ///
  /// `labelSmall` is the SECTION LABEL style — uppercase with +6% tracking,
  /// which at 12px is 0.72 logical pixels of letter-spacing.
  static TextTheme _textTheme(Brightness brightness) {
    final Color ink = brightness == Brightness.light
        ? AppColor.ink
        : const Color(0xFFE8F0EA);
    final Color muted = brightness == Brightness.light
        ? AppColor.inkMuted
        : const Color(0xFFA8B6AC);

    return TextTheme(
      // Screen title.
      displayLarge: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: ink),
      // Nav bar title.
      titleMedium: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: ink),
      // Row label.
      bodyLarge: TextStyle(fontSize: 15, fontWeight: FontWeight.w400, color: ink),
      // Secondary text.
      bodyMedium: TextStyle(fontSize: 13, fontWeight: FontWeight.w400, color: muted),
      // SECTION LABEL — uppercase, +6% tracking.
      labelSmall: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 12 * 0.06,
        color: muted,
      ),
      // Meta, counts, timestamps.
      labelMedium: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: muted),
    );
  }

  static ThemeData _build(String languageCode, Brightness brightness) {
    final bool isLight = brightness == Brightness.light;

    final ColorScheme colorScheme = ColorScheme.fromSeed(
      seedColor: AppColor.brand,
      brightness: brightness,
      primary: AppColor.brand,
      error: AppColor.danger,
    );

    final ThemeData base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      fontFamily: fontFor(languageCode),
    );

    return base.copyWith(
      scaffoldBackgroundColor: isLight ? AppColor.groundLight : AppColor.groundDark,
      textTheme: _textTheme(brightness).apply(fontFamily: fontFor(languageCode)),

      // The app bar is brand green with white content on every screen that has
      // one — both the 96 back-nav and the 182 title+search variants.
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColor.brand,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
      ),

      // Dialogs were unthemed, so an AlertDialog title fell through to the M3
      // default derived from a green seed and rendered near-white on the light
      // dialog surface — the "Forgot password?" heading was barely readable.
      dialogTheme: DialogThemeData(
        backgroundColor: isLight ? Colors.white : AppColor.surfaceDark,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          fontFamily: fontFor(languageCode),
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: isLight ? AppColor.ink : Colors.white,
        ),
        contentTextStyle: TextStyle(
          fontFamily: fontFor(languageCode),
          fontSize: 13.5,
          color: isLight ? AppColor.inkMuted : Colors.white70,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusCardLarge),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: isLight ? Colors.white : AppColor.surfaceDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusCardLarge),
        ),
        margin: EdgeInsets.zero,
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColor.brand,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDimens.radiusCard),
          ),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isLight ? AppColor.surfaceAlt : Colors.white10,
        hintStyle: const TextStyle(color: AppColor.inkFaint),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusCard),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusCard),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusCard),
          borderSide: const BorderSide(color: AppColor.brand, width: 1.5),
        ),
      ),

      dividerTheme: DividerThemeData(
        color: isLight ? AppColor.hairline : AppColor.hairlineDark,
        thickness: 1,
        space: 1,
      ),

      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColor.brand,
        foregroundColor: Colors.white,
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: isLight ? Colors.white : AppColor.surfaceDark,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppDimens.radiusCardLarge),
          ),
        ),
      ),
    );
  }
}
