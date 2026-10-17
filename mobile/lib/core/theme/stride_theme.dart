import 'package:flutter/material.dart';

import 'tokens.dart';

/// Một nguồn theme dùng chung (D01). Chỉ light theme; màn khóa khi chạy tự dùng nền navy.
ThemeData buildStrideTheme() {
  const scheme = ColorScheme(
    brightness: Brightness.light,
    primary: StrideColors.primary,
    onPrimary: Colors.white,
    secondary: StrideColors.lime,
    onSecondary: StrideColors.textPrimary,
    error: StrideColors.error,
    onError: Colors.white,
    surface: StrideColors.surface,
    onSurface: StrideColors.textPrimary,
    surfaceContainerHighest: StrideColors.subtle,
    outline: StrideColors.borderControl,
    outlineVariant: StrideColors.borderSubtle,
  );

  final controlShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(StrideRadius.control));

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: StrideText.fontFamily,
    scaffoldBackgroundColor: StrideColors.canvas,
    splashFactory: InkRipple.splashFactory,
    textTheme: const TextTheme(
      headlineMedium: StrideText.title,
      titleLarge: StrideText.heading,
      titleMedium: StrideText.subheading,
      bodyLarge: StrideText.body,
      bodyMedium: StrideText.body,
      labelLarge: StrideText.label,
      bodySmall: StrideText.caption,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: StrideColors.canvas,
      foregroundColor: StrideColors.textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: StrideText.heading,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(64, 52)),
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 20)),
        shape: WidgetStatePropertyAll(controlShape),
        textStyle: const WidgetStatePropertyAll(TextStyle(fontFamily: StrideText.fontFamily, fontSize: 16, fontWeight: FontWeight.w600)),
        backgroundColor: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.disabled)) return StrideColors.disabledBg;
          if (s.contains(WidgetState.pressed)) return StrideColors.primaryPressed;
          return StrideColors.primary;
        }),
        foregroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.disabled) ? StrideColors.disabledText : Colors.white),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(64, 52)),
        shape: WidgetStatePropertyAll(controlShape),
        side: const WidgetStatePropertyAll(BorderSide(color: StrideColors.primary, width: 1.5)),
        foregroundColor: const WidgetStatePropertyAll(StrideColors.primary),
        textStyle: const WidgetStatePropertyAll(TextStyle(fontFamily: StrideText.fontFamily, fontSize: 16, fontWeight: FontWeight.w600)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
        foregroundColor: const WidgetStatePropertyAll(StrideColors.primary),
        textStyle: const WidgetStatePropertyAll(TextStyle(fontFamily: StrideText.fontFamily, fontSize: 14, fontWeight: FontWeight.w600)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: StrideColors.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      labelStyle: StrideText.label.copyWith(color: StrideColors.textSecondary, fontWeight: FontWeight.w400),
      floatingLabelStyle: StrideText.label.copyWith(color: StrideColors.primary),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(StrideRadius.control),
        borderSide: const BorderSide(color: StrideColors.borderControl),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(StrideRadius.control),
        borderSide: const BorderSide(color: StrideColors.primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(StrideRadius.control),
        borderSide: const BorderSide(color: StrideColors.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(StrideRadius.control),
        borderSide: const BorderSide(color: StrideColors.error, width: 2),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(StrideRadius.control),
        borderSide: const BorderSide(color: StrideColors.borderSubtle),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: const WidgetStatePropertyAll(Colors.white),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? StrideColors.primary : StrideColors.borderControl),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? StrideColors.primary : Colors.transparent),
      side: const BorderSide(color: StrideColors.borderControl, width: 1.5),
    ),
    dividerTheme: const DividerThemeData(color: StrideColors.borderSubtle, thickness: 1, space: 1),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: StrideColors.surface,
      showDragHandle: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(StrideRadius.sheet))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: StrideColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(StrideRadius.card)),
      titleTextStyle: StrideText.heading,
      contentTextStyle: StrideText.body,
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating, backgroundColor: StrideColors.textPrimary),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: StrideColors.surface,
      indicatorColor: Colors.transparent,
      height: 64,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => StrideText.caption.copyWith(
          color: s.contains(WidgetState.selected) ? StrideColors.primary : StrideColors.textSecondary,
          fontWeight: s.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(color: s.contains(WidgetState.selected) ? StrideColors.primary : StrideColors.textSecondary, size: 24),
      ),
    ),
  );
}
