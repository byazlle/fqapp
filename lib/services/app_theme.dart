import 'package:flutter/material.dart';

import 'brand.dart';

/// Persisted theme-mode preference key: 'theme_mode' = 'light'|'dark'|'system'.
const themeModeKey = 'theme_mode';

/// Brand seed color for the whole app (also used by the player slider and
/// the detail page's accent text).
const appSeedColor = Brand.primary;

/// Global theme-mode notifier; the settings page writes it, MaterialApp
/// rebuilds with the new mode.
final ValueNotifier<ThemeMode> themeModeNotifier = ValueNotifier(
  ThemeMode.system,
);

/// Persisted e-ink mode key: 'eink_mode' = bool.
/// #15/#9：墨水屏模式。开启时全应用纯黑白、无毛玻璃、无过渡动画，
/// 避免墨水屏量化灰阶 / 残影。关闭后恢复原主题。
const einkModeKey = 'eink_mode';

/// Global e-ink mode notifier; the settings page writes it, MaterialApp
/// rebuilds with the e-ink theme.
final ValueNotifier<bool> einkModeNotifier = ValueNotifier(false);

/// No page transition: e-ink screens ghost on every animated frame, so
/// route changes must swap instantly instead of sliding / fading.
class _NoPageTransitionBuilder extends PageTransitionsBuilder {
  const _NoPageTransitionBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => child;
}

ThemeMode themeModeFromName(String? name) {
  switch (name) {
    case 'light':
      return ThemeMode.light;
    case 'dark':
      return ThemeMode.dark;
    default:
      return ThemeMode.system;
  }
}

/// Unified design system and theme factory for 流光.
class AppTheme {
  static const Color accent = Brand.primary;
  static const Color accentStrong = Brand.primaryDeep;
  static const Color accentDark = Brand.primarySoft;

  /// Pure black-on-white theme for e-ink (#15/#9). No tonal / seed palette,
  /// no grey scale except black-on-white, no ripple, no page transition.
  /// Dark mode is intentionally not honoured here: inverted e-ink pages
  /// ghost badly and the issue asks for #FFFFFF surface / #000000 text.
  static ThemeData _createEinkTheme() {
    const scheme = ColorScheme(
      brightness: Brightness.light,
      primary: Colors.black,
      onPrimary: Colors.white,
      primaryContainer: Colors.white,
      onPrimaryContainer: Colors.black,
      secondary: Colors.black,
      onSecondary: Colors.white,
      secondaryContainer: Colors.white,
      onSecondaryContainer: Colors.black,
      tertiary: Colors.black,
      onTertiary: Colors.white,
      surface: Colors.white,
      onSurface: Colors.black,
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: Colors.white,
      surfaceContainer: Colors.white,
      surfaceContainerHigh: Colors.white,
      surfaceContainerHighest: Colors.white,
      onSurfaceVariant: Colors.black,
      outline: Colors.black,
      outlineVariant: Colors.black,
      error: Colors.black,
      onError: Colors.white,
      errorContainer: Colors.white,
      onErrorContainer: Colors.black,
    );
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: Colors.white,
      canvasColor: Colors.white,
      splashFactory: NoSplash.splashFactory,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      hoverColor: Colors.transparent,
      focusColor: Colors.transparent,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: _NoPageTransitionBuilder(),
          TargetPlatform.iOS: _NoPageTransitionBuilder(),
          TargetPlatform.macOS: _NoPageTransitionBuilder(),
          TargetPlatform.windows: _NoPageTransitionBuilder(),
          TargetPlatform.linux: _NoPageTransitionBuilder(),
          TargetPlatform.fuchsia: _NoPageTransitionBuilder(),
        },
      ),
      // 统一标题栏：透明底、左对齐、52 高。各页不再各写一套 AppBar 装饰，
      // 视觉上从悬浮导航到页面标题是一条连续的玻璃带。
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        centerTitle: false,
        toolbarHeight: 52,
        titleTextStyle: TextStyle(
          fontSize: 16.5,
          fontWeight: FontWeight.w700,
          color: Colors.black,
          letterSpacing: 0.2,
        ),
        iconTheme: IconThemeData(size: 21, color: Colors.black),
        actionsIconTheme: IconThemeData(size: 20, color: Colors.black),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Colors.black, width: 0.6),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: Colors.black, width: 0.6),
        ),
        titleTextStyle: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: Colors.black,
        ),
        contentTextStyle: const TextStyle(
          fontSize: 14,
          color: Colors.black,
          height: 1.4,
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.white,
        modalBackgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(BrandRadii.sheet)),
        ),
        dragHandleColor: Colors.black,
        dragHandleSize: Size(36, 4),
      ),
      dividerTheme: const DividerThemeData(
        color: Colors.black,
        thickness: 0.6,
        space: 1,
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        dense: false,
        titleTextStyle: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: Colors.black,
        ),
        subtitleTextStyle: TextStyle(fontSize: 12.5, color: Colors.black),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(BrandRadii.control)),
        backgroundColor: Colors.black,
        contentTextStyle: const TextStyle(fontSize: 13, color: Colors.white),
      ),
    );
  }

  static ThemeData createTheme(
    Brightness brightness, {
    bool einkMode = false,
  }) {
    if (einkMode) return _createEinkTheme();
    final isDark = brightness == Brightness.dark;
    final primary = isDark ? accentDark : accent;
    final canvas = isDark ? Brand.darkCanvas : Brand.lightCanvas;
    final surface = isDark ? const Color(0xFF141827) : Colors.white;
    final surfaceContainerLow =
        isDark ? const Color(0xFF0F121D) : const Color(0xFFF1F2FA);
    final surfaceContainer =
        isDark ? const Color(0xFF171B2B) : const Color(0xFFECEEF8);
    final surfaceContainerHigh =
        isDark ? const Color(0xFF1D2234) : const Color(0xFFE4E7F4);
    final ink = isDark ? const Color(0xFFF2F3FB) : const Color(0xFF191B26);
    final muted = isDark ? const Color(0xFF9BA1B8) : const Color(0xFF6B7089);
    final line = isDark ? const Color(0xFF262B3D) : const Color(0xFFE4E7F2);

    final scheme = ColorScheme(
      brightness: brightness,
      primary: primary,
      onPrimary: Colors.white,
      primaryContainer:
          isDark ? const Color(0xFF2A2154) : const Color(0xFFEDE8FF),
      onPrimaryContainer:
          isDark ? const Color(0xFFE3DCFF) : const Color(0xFF2A1A6B),
      secondary: isDark ? const Color(0xFF67E8F9) : const Color(0xFF0EA5B7),
      onSecondary: isDark ? const Color(0xFF00343D) : Colors.white,
      secondaryContainer:
          isDark ? const Color(0xFF103B45) : const Color(0xFFD8F6FB),
      onSecondaryContainer:
          isDark ? const Color(0xFFB6F1FA) : const Color(0xFF05323A),
      tertiary: isDark ? const Color(0xFFF9A8D4) : const Color(0xFFDB2777),
      onTertiary: Colors.white,
      surface: surface,
      onSurface: ink,
      surfaceContainerLowest: isDark ? const Color(0xFF0F0F11) : Colors.white,
      surfaceContainerLow: surfaceContainerLow,
      surfaceContainer: surfaceContainer,
      surfaceContainerHigh: surfaceContainerHigh,
      surfaceContainerHighest:
          isDark ? const Color(0xFF34343A) : const Color(0xFFE4DFD6),
      onSurfaceVariant: muted,
      outline: isDark ? const Color(0xFF7A7670) : const Color(0xFF9E9A92),
      outlineVariant: line,
      error: isDark ? const Color(0xFFFFB4AB) : const Color(0xFFBA1A1A),
      onError: isDark ? const Color(0xFF690005) : Colors.white,
      errorContainer:
          isDark ? const Color(0xFF93000A) : const Color(0xFFFFDAD6),
      onErrorContainer:
          isDark ? const Color(0xFFFFDAD6) : const Color(0xFF410002),
    );

    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      scaffoldBackgroundColor: canvas,
      canvasColor: canvas,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        centerTitle: false,
        toolbarHeight: 52,
        titleTextStyle: TextStyle(
          fontSize: 16.5,
          fontWeight: FontWeight.w700,
          color: ink,
          letterSpacing: 0.2,
        ),
        iconTheme: IconThemeData(size: 21, color: ink),
        actionsIconTheme: IconThemeData(size: 20, color: ink),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BrandRadii.card),
          side: BorderSide(color: line, width: 0.6),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BrandRadii.panel + 2),
          side: BorderSide(color: line, width: 0.6),
        ),
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: ink,
        ),
        contentTextStyle: TextStyle(
          fontSize: 14,
          color: muted,
          height: 1.4,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        modalBackgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(BrandRadii.sheet)),
        ),
        dragHandleColor: line,
        dragHandleSize: const Size(36, 4),
      ),
      dividerTheme: DividerThemeData(
        color: line,
        thickness: 0.6,
        space: 1,
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        dense: false,
        titleTextStyle: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: ink,
        ),
        subtitleTextStyle: TextStyle(
          fontSize: 12.5,
          color: muted,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(BrandRadii.control)),
        backgroundColor:
            isDark ? const Color(0xFF2C2C30) : const Color(0xFF2C2825),
        contentTextStyle: const TextStyle(fontSize: 13, color: Colors.white),
      ),
    );
  }
}
