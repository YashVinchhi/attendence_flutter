import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../screens/home_screen.dart';
import '../screens/students_screen.dart';
import '../screens/attendance_screen.dart';
import '../screens/reports_screen.dart';
import '../screens/settings_screen.dart';
import '../widgets/scaffold_with_nav_bar.dart';
import 'navigation_service.dart';
import '../screens/accept_invite_screen.dart';
import '../screens/create_invite_screen.dart';
import '../screens/debug_sign_in.dart';
import '../screens/sign_in_screen.dart';
import '../providers/auth_provider.dart';
import '../screens/manage_ccs_screen.dart';
import '../screens/manage_crs_screen.dart';

// CompositeListenable: lightweight Listenable that proxies multiple sources
// This replaces the incorrect use of `Listenable.merge(...)` and lets us pass
// a single Listenable to GoRouter that fires when any source changes.
class CompositeListenable extends ChangeNotifier {
  CompositeListenable(List<Listenable> sources) {
    _sources = List.unmodifiable(sources);
    for (final s in _sources) {
      s.addListener(_onSourceChange);
    }
  }

  late final List<Listenable> _sources;

  void _onSourceChange() => notifyListeners();

  @override
  void dispose() {
    for (final s in _sources) {
      try {
        s.removeListener(_onSourceChange);
      } catch (_) {}
    }
    super.dispose();
  }
}

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

  final authListenable = AuthProvider.instance;

  // Combine listenables safely: if a refreshListenable is provided, create
  // a CompositeListenable that listens to both authListenable and the provided one.
  final Listenable combinedRefresh = (refreshListenable != null)
      ? CompositeListenable([refreshListenable, authListenable])
      : authListenable;

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    debugLogDiagnostics: true,
    initialLocation: '/signin',
    refreshListenable: combinedRefresh,
    redirect: (context, state) {
      final loggedIn = AuthProvider.instance.isLoggedIn;
      // Use uri.path to check the path portion of the current location (compatible with this go_router version)
      final currentPath = state.uri.path;
      final loggingIn = currentPath == '/signin' || currentPath == '/debug-signin' || currentPath == '/accept-invite';
      if (!loggedIn && !loggingIn) return '/signin';
      if (loggedIn && loggingIn) return '/home';
      return null;
    },
    routes: [
      GoRoute(
        path: '/signin',
        pageBuilder: (context, state) => MaterialPage(child: const SignInScreen()),
      ),
      // Standalone route for invite acceptance (optional token via query param)
      GoRoute(
        path: '/accept-invite',
        pageBuilder: (context, state) {
          // Use state.uri.queryParameters to be compatible with go_router versions
          final token = state.uri.queryParameters['token'];
          return MaterialPage(child: AcceptInviteScreen(token: token));
        },
      ),

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
          GoRoute(
            path: '/create-invite',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: CreateInviteScreen(),
            ),
          ),
          GoRoute(
            path: '/manage-ccs',
            pageBuilder: (context, state) => const NoTransitionPage(child: ManageCcsScreen()),
          ),
          GoRoute(
            path: '/manage-crs',
            pageBuilder: (context, state) => const NoTransitionPage(child: ManageCrsScreen()),
          ),
          GoRoute(
            path: '/debug-signin',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: DebugSignInScreen(),
            ),
          ),
        ],
      ),
    ],
  );
}
