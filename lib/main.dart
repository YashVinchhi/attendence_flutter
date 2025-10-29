import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'providers/student_provider.dart';
import 'providers/attendance_provider.dart';
import 'providers/report_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/settings_provider.dart';
import 'services/router.dart';
import 'services/navigation_service.dart';
import 'services/app_lifecycle_notifier.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  final navigationService = NavigationService();
  final appLifecycleNotifier = AppLifecycleNotifier();

  final routerConfig = createRouter(
    navigationService: navigationService,
    refreshListenable: appLifecycleNotifier,
  );

  runApp(MyApp(
    routerConfig: routerConfig,
    navigationService: navigationService,
    lifecycleNotifier: appLifecycleNotifier,
  ));
}

class MyApp extends StatelessWidget {
  final GoRouter routerConfig;
  final NavigationService navigationService;
  final AppLifecycleNotifier lifecycleNotifier;

  const MyApp({
    super.key,
    required this.routerConfig,
    required this.navigationService,
    required this.lifecycleNotifier,
  });

  // Updated modern palette tuned to the screenshots
  static const _primaryBlue = Color(0xFF3D86FF);
  static const _primaryBlueVariant = Color(0xFF2F6FDD);
  static const _mutedDark = Color(0xFF222232);
  static const _bgLight = Color(0xFFF7F8FA);
  static const _surfaceLight = Color(0xFFFFFFFF);
  static const _danger = Color(0xFFE74C3C);

  ColorScheme _lightScheme() {
    final base = ColorScheme.light(
      primary: _primaryBlue,
      onPrimary: Colors.white,
      secondary: _mutedDark,
      onSecondary: Colors.white,
      surface: _surfaceLight,
      background: _bgLight,
      error: _danger,
    );
    return base.copyWith(
      primaryContainer: _primaryBlueVariant,
      onPrimaryContainer: Colors.white,
      secondaryContainer: const Color(0xFFF1F3F8),
      onSecondaryContainer: _mutedDark,
      onSurface: const Color(0xFF0F1720),
      surfaceContainerHighest: const Color(0xFFF5F7FB),
      outline: const Color(0xFFE6E9F0),
      outlineVariant: const Color(0xFFF1F3F8),
      tertiary: _primaryBlue,
      onTertiary: Colors.white,
      tertiaryContainer: const Color(0xFFEFF5FF),
      onTertiaryContainer: _primaryBlueVariant,
      inverseSurface: const Color(0xFF0F1720),
      onInverseSurface: Colors.white,
      inversePrimary: _primaryBlueVariant,
      scrim: Colors.black54,
      shadow: Colors.black26,
    );
  }

  ColorScheme _darkScheme() {
    final base = ColorScheme.dark(
      primary: _primaryBlue,
      onPrimary: Colors.black,
      secondary: _mutedDark,
      onSecondary: Colors.white,
      surface: const Color(0xFF14141A),
      background: const Color(0xFF0B0B0F),
      error: _danger,
    );
    return base.copyWith(
      primaryContainer: _primaryBlueVariant,
      onPrimaryContainer: Colors.black,
      secondaryContainer: const Color(0xFF1C1C22),
      onSecondaryContainer: Colors.white,
      onSurface: Colors.white,
      surfaceContainerHighest: const Color(0xFF1C1C22),
      outline: const Color(0xFF2A2A30),
      outlineVariant: const Color(0xFF1C1C22),
      tertiary: _primaryBlue,
      onTertiary: Colors.black,
      tertiaryContainer: const Color(0xFF2B3F5F),
      onTertiaryContainer: Colors.white,
      inverseSurface: const Color(0xFFF2F2F2),
      onInverseSurface: const Color(0xFF1E1E1E),
      inversePrimary: _primaryBlueVariant,
      scrim: Colors.black54,
      shadow: Colors.black45,
    );
  }

  ThemeData _baseTheme(ColorScheme scheme) {
    final textTheme = GoogleFonts.poppinsTextTheme();

    // Typography roles tailored to the mockups
    final headlines = textTheme.copyWith(
      headlineSmall: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700, fontSize: 20),
      titleLarge: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700, fontSize: 22),
      titleMedium: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600, fontSize: 16),
      bodyMedium: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w400, fontSize: 14),
      labelLarge: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600, fontSize: 14),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      textTheme: headlines,
      fontFamily: GoogleFonts.poppins().fontFamily,
      scaffoldBackgroundColor: scheme.background,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: headlines.titleLarge?.copyWith(color: scheme.onSurface),
        iconTheme: IconThemeData(color: scheme.onSurface),
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          textStyle: headlines.labelLarge,
          elevation: 6,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.onSurface,
          side: BorderSide(color: scheme.outline),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 10,
        sizeConstraints: const BoxConstraints(minWidth: 56, minHeight: 56),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: scheme.surface,
        contentTextStyle: headlines.bodyMedium?.copyWith(color: scheme.onSurface),
        behavior: SnackBarBehavior.floating,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primary.withOpacity(0.12),
        elevation: 0,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          final color = selected ? scheme.primary : scheme.onSurface.withOpacity(0.6);
          return IconThemeData(color: color);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          final color = selected ? scheme.primary : scheme.onSurface.withOpacity(0.6);
          return headlines.labelLarge?.copyWith(color: color, fontSize: 12);
        }),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
          TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
        },
      ),
      visualDensity: VisualDensity.adaptivePlatformDensity,
    );
  }

  ThemeData _buildLightTheme() => _baseTheme(_lightScheme());
  ThemeData _buildDarkTheme() => _baseTheme(_darkScheme());

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider(create: (_) => StudentProvider()),
        ChangeNotifierProvider(create: (_) => AttendanceProvider()),
        ChangeNotifierProvider(create: (_) => ReportProvider()),
        Provider<NavigationService>.value(value: navigationService),
        ChangeNotifierProvider<AppLifecycleNotifier>.value(value: lifecycleNotifier),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, child) {
          final themeMode = themeProvider.themeMode;

          return MaterialApp.router(
            title: 'Attendance Management System',
            theme: _buildLightTheme(),
            darkTheme: _buildDarkTheme(),
            themeMode: themeMode,
            routerConfig: routerConfig,
            debugShowCheckedModeBanner: false,
            restorationScopeId: 'app',
          );
        },
      ),
    );
  }
}
