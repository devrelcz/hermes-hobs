import 'package:flutter/material.dart';
import 'package:wolt_modal_sheet/wolt_modal_sheet.dart';

/// "Moss and lantern": soft moss-tinted neutrals, a moss-green accent for
/// actions and your own messages, and warm lantern yellow kept for the happy
/// moments (unread, approvals). Neutrals stay quiet so the hobs' own avatar
/// colors carry the color on the list.
///
/// Shape rule: buttons and chips are pills, text fields 14, cards and list
/// rows 16, sheets and dialogs 24 (full-screen sheets on phones are square).
abstract final class HobsTheme {
  /// Geist for all text, Geist Mono for code and SOUL.md (bundled, see
  /// pubspec.yaml).
  static const fontFamily = 'Geist';
  static const monoFamily = 'GeistMono';

  static const _moss = Color(0xFF2F6B4A);

  static final ColorScheme light =
      ColorScheme.fromSeed(
        seedColor: _moss,
        brightness: Brightness.light,
      ).copyWith(
        primary: _moss,
        onPrimary: const Color(0xFFFBFDF9),
        primaryContainer: const Color(0xFFCDEBD6),
        onPrimaryContainer: const Color(0xFF0F3A24),
        secondary: const Color(0xFF56685C),
        onSecondary: const Color(0xFFFBFDF9),
        secondaryContainer: const Color(0xFFDCE8DE),
        onSecondaryContainer: const Color(0xFF15261B),
        // The amber of the HobCrew mark (the hat in the logo).
        tertiary: const Color(0xFFFFAC02),
        onTertiary: const Color(0xFF2B1E00),
        tertiaryContainer: const Color(0xFFFFE7B3),
        onTertiaryContainer: const Color(0xFF4A3300),
        error: const Color(0xFFB3382B),
        onError: const Color(0xFFFFFBFA),
        errorContainer: const Color(0xFFFBDAD4),
        onErrorContainer: const Color(0xFF5C150D),
        surface: const Color(0xFFF5F8F3),
        onSurface: const Color(0xFF1C2620),
        onSurfaceVariant: const Color(0xFF4E5C52),
        surfaceDim: const Color(0xFFD9E0D6),
        surfaceBright: const Color(0xFFFCFDFB),
        surfaceContainerLowest: const Color(0xFFFCFDFB),
        surfaceContainerLow: const Color(0xFFF0F4EE),
        surfaceContainer: const Color(0xFFEBF0E8),
        surfaceContainerHigh: const Color(0xFFE5ECE2),
        surfaceContainerHighest: const Color(0xFFDFE7DC),
        // Dark enough for small text (times, hints): 4.5:1 on the surfaces.
        outline: const Color(0xFF5F6E63),
        outlineVariant: const Color(0xFFD3DDD0),
        inverseSurface: const Color(0xFF2B352E),
        onInverseSurface: const Color(0xFFEDF2EA),
        inversePrimary: const Color(0xFF8FD3A8),
        surfaceTint: Colors.transparent,
      );

  static final ColorScheme dark =
      ColorScheme.fromSeed(
        seedColor: _moss,
        brightness: Brightness.dark,
      ).copyWith(
        primary: const Color(0xFF8FD3A8),
        onPrimary: const Color(0xFF06371E),
        primaryContainer: const Color(0xFF1F4F35),
        onPrimaryContainer: const Color(0xFFCDEBD6),
        secondary: const Color(0xFFB7CCBC),
        onSecondary: const Color(0xFF223529),
        secondaryContainer: const Color(0xFF2E3F33),
        onSecondaryContainer: const Color(0xFFD3E4D6),
        tertiary: const Color(0xFFFFAC02),
        onTertiary: const Color(0xFF3A2A00),
        tertiaryContainer: const Color(0xFF5A4100),
        onTertiaryContainer: const Color(0xFFFFE7B3),
        error: const Color(0xFFF2A093),
        onError: const Color(0xFF5C150D),
        errorContainer: const Color(0xFF7A2318),
        onErrorContainer: const Color(0xFFFBDAD4),
        surface: const Color(0xFF121813),
        onSurface: const Color(0xFFE3EBE4),
        onSurfaceVariant: const Color(0xFFB5C2B8),
        surfaceDim: const Color(0xFF121813),
        surfaceBright: const Color(0xFF323C35),
        surfaceContainerLowest: const Color(0xFF0D120E),
        surfaceContainerLow: const Color(0xFF161D18),
        surfaceContainer: const Color(0xFF1A221C),
        surfaceContainerHigh: const Color(0xFF222C25),
        surfaceContainerHighest: const Color(0xFF2B362E),
        outline: const Color(0xFF879489),
        outlineVariant: const Color(0xFF344038),
        inverseSurface: const Color(0xFFE3EBE4),
        onInverseSurface: const Color(0xFF1C2620),
        inversePrimary: _moss,
        surfaceTint: Colors.transparent,
      );

  static ThemeData lightTheme() => _build(light, HobsColors.light);
  static ThemeData darkTheme() => _build(dark, HobsColors.dark);

  static ThemeData _build(ColorScheme cs, HobsColors extra) {
    const pill = StadiumBorder();
    final field = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: cs.outlineVariant),
    );
    return ThemeData(
      colorScheme: cs,
      fontFamily: fontFamily,
      scaffoldBackgroundColor: cs.surface,
      extensions: [
        extra,
        // Sheets, side sheets and their dialogs (see sheets.dart) share
        // the bottom sheet's surface and the 24 corner of the shape rule.
        WoltModalSheetThemeData(
          backgroundColor: cs.surfaceContainerLow,
          surfaceTintColor: Colors.transparent,
          modalBarrierColor: cs.scrim.withValues(alpha: 0.32),
          dragHandleColor: cs.outline,
          topBarShadowColor: Colors.transparent,
          topBarElevation: 0,
          shadowColor: cs.shadow.withValues(alpha: 0.18),
          modalElevation: 8,
          hasTopBarLayer: false,
          useSafeArea: true,
        ),
      ],
      appBarTheme: AppBarTheme(
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: cs.surfaceContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(shape: pill),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(shape: pill, elevation: 0),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: pill,
          side: BorderSide(color: cs.outline),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(shape: pill),
      ),
      // Choice chips (filters, reasoning level): flat, the picked one in
      // moss. Plain chips keep a hairline.
      chipTheme: ChipThemeData(
        shape: pill,
        side: BorderSide(color: cs.outlineVariant),
        showCheckmark: false,
        selectedColor: cs.primary,
        secondarySelectedColor: cs.primary,
        // Spelled out in full: a chip's label style replaces the theme's
        // (labelLarge in Geist). The second one is for the picked chip.
        labelStyle: TextStyle(
          fontFamily: fontFamily,
          fontSize: 14,
          height: 20 / 14,
          letterSpacing: 0.1,
          fontWeight: FontWeight.w500,
          color: cs.onSurfaceVariant,
        ),
        secondaryLabelStyle: TextStyle(
          fontFamily: fontFamily,
          fontSize: 14,
          height: 20 / 14,
          letterSpacing: 0.1,
          fontWeight: FontWeight.w600,
          color: cs.onPrimary,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cs.surfaceContainerLowest,
        border: field,
        enabledBorder: field,
        focusedBorder: field.copyWith(
          borderSide: BorderSide(color: cs.primary, width: 2),
        ),
        errorBorder: field.copyWith(borderSide: BorderSide(color: cs.error)),
      ),
      dividerTheme: DividerThemeData(color: cs.outlineVariant, space: 1),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: cs.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: cs.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}

/// Status colors outside the Material roles, tuned for contrast on the
/// moss surfaces (text 4.5:1, dots 3:1).
@immutable
class HobsColors extends ThemeExtension<HobsColors> {
  const HobsColors({required this.working, required this.lantern});

  /// A hob that is online or busy; also used as text ("pracuje").
  final Color working;

  /// Lantern glow for small marks on the surface: unread, connecting.
  final Color lantern;

  static const light = HobsColors(
    working: Color(0xFF1A7449),
    lantern: Color(0xFFA86F08),
  );

  static const dark = HobsColors(
    working: Color(0xFF6FD49B),
    lantern: Color(0xFFFFAC02),
  );

  static HobsColors of(BuildContext context) =>
      Theme.of(context).extension<HobsColors>() ?? light;

  @override
  HobsColors copyWith({Color? working, Color? lantern}) => HobsColors(
    working: working ?? this.working,
    lantern: lantern ?? this.lantern,
  );

  @override
  HobsColors lerp(HobsColors? other, double t) {
    if (other == null) return this;
    return HobsColors(
      working: Color.lerp(working, other.working, t)!,
      lantern: Color.lerp(lantern, other.lantern, t)!,
    );
  }
}

/// A height for a bar holding text: [rest] (padding, icons) plus [text]
/// grown with the system text size, so large text never clips. At 100 %
/// it is simply `text + rest`.
double textBarHeight(
  BuildContext context, {
  required double text,
  required double rest,
}) => MediaQuery.textScalerOf(context).scale(text) + rest;
