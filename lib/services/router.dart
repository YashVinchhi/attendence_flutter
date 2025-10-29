import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../screens/home_screen.dart';
import '../screens/students_screen.dart';
import '../screens/attendance_screen.dart';
import '../screens/reports_screen.dart';
import '../screens/settings_screen.dart';
import '../widgets/scaffold_with_nav_bar.dart';
import 'navigation_service.dart';

// Root navigator key
final _rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');
// Shell navigator key
final _shellNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'shell');

// Factory function to create router instance
GoRouter createRouter({
  required NavigationService navigationService,
  Listenable? refreshListenable,
}) {
  // Attach the root navigator key to the navigation service
  navigationService.attachRootNavigatorKey(_rootNavigatorKey);

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    debugLogDiagnostics: true,
    initialLocation: '/home',
    refreshListenable: refreshListenable,
    routes: [
      ShellRoute(
        navigatorKey: _shellNavigatorKey,
        builder: (context, state, child) {
          return ScaffoldWithNavBar(body: child);
        },
        routes: [
          GoRoute(
            path: '/home',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: HomeScreen(),
            ),
          ),
          GoRoute(
            path: '/students',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: StudentsScreen(),
            ),
          ),
          GoRoute(
            path: '/attendance',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: AttendanceScreen(),
            ),
          ),
          // Deep link: attendance by date -> /attendance/YYYY-MM-DD
          GoRoute(
            path: '/attendance/:date',
            pageBuilder: (context, state) {
              final dateParam = state.pathParameters['date'];
              DateTime? parsed;
              if (dateParam != null) {
                try { parsed = DateTime.parse(dateParam); } catch (_) { parsed = null; }
              }
              return NoTransitionPage(
                child: AttendanceScreen(initialDate: parsed),
              );
            },
          ),
          GoRoute(
            path: '/reports',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: ReportsScreen(),
            ),
          ),
          GoRoute(
            path: '/settings',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: SettingsScreen(),
            ),
          ),
        ],
      ),
    ],
  );
}
