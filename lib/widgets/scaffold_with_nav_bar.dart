import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:provider/provider.dart';
import '../providers/user_provider.dart';

// Small private model for nav items
class _NavItem {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final String route;
  const _NavItem({required this.icon, required this.selectedIcon, required this.label, required this.route});
}

class ScaffoldWithNavBar extends StatelessWidget {
  const ScaffoldWithNavBar({
    required this.body,
    Key? key,
  }) : super(key: key);

  final Widget body;

  void _onItemTapped(BuildContext context, int index) {
    final userProv = Provider.of<UserProvider>(context, listen: false);
    final items = _buildNavRoutes(userProv);
    if (index < 0 || index >= items.length) return;
    context.go(items[index].route);
  }

  // Helper to compute nav items and their target routes based on permissions
  List<_NavItem> _buildNavRoutes(UserProvider userProv) {
    // Default Home always present
    final List<_NavItem> items = [
      const _NavItem(icon: Icons.home_outlined, selectedIcon: Icons.home, label: 'Home', route: '/home'),
    ];

    // Students (HOD/CC) or if user has view_students permission
    if (userProv.hasPermission('view_students') || userProv.isHod || userProv.isCc) {
      items.add(const _NavItem(icon: Icons.people_outline, selectedIcon: Icons.people, label: 'Students', route: '/students'));
    }

    // Attendance (CR/CC/HOD) - most users who can take/view attendance
    if (userProv.hasPermission('take_attendance') || userProv.isCr || userProv.isCc || userProv.isHod) {
      items.add(const _NavItem(icon: Icons.check_circle_outline, selectedIcon: Icons.check_circle, label: 'Attendance', route: '/attendance'));
    }

    // Reports
    if (userProv.hasPermission('view_reports') || userProv.isCr || userProv.isCc || userProv.isHod) {
      items.add(const _NavItem(icon: Icons.assessment_outlined, selectedIcon: Icons.assessment, label: 'Reports', route: '/reports'));
    }

    // Settings always present
    items.add(const _NavItem(icon: Icons.settings_outlined, selectedIcon: Icons.settings, label: 'Settings', route: '/settings'));

    return items;
  }

  @override
  Widget build(BuildContext context) {
    final path = GoRouterState.of(context).uri.path;
    // Compute current index by matching path to nav items; fallback to 0
    final userProv = Provider.of<UserProvider>(context);
    final navItems = _buildNavRoutes(userProv);
    int currentIndex = 0;
    for (int i = 0; i < navItems.length; i++) {
      if (path.startsWith(navItems[i].route)) {
        currentIndex = i;
        break;
      }
    }

    final isWide = MediaQuery.of(context).size.width >= 900;

    if (isWide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: currentIndex.clamp(0, navItems.length - 1),
              onDestinationSelected: (i) => _onItemTapped(context, i),
              labelType: NavigationRailLabelType.selected,
              useIndicator: true,
              destinations: navItems
                  .map((it) => NavigationRailDestination(icon: Icon(it.icon), selectedIcon: Icon(it.selectedIcon), label: Text(it.label)))
                  .toList(),
            ),
            const VerticalDivider(width: 1),
            Expanded(child: body),
          ],
        ),
      );
    }

    return Scaffold(
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex.clamp(0, navItems.length - 1),
        onDestinationSelected: (index) => _onItemTapped(context, index),
        destinations: navItems
            .map((it) => NavigationDestination(icon: Icon(it.icon), selectedIcon: Icon(it.selectedIcon), label: it.label))
            .toList(),
      ),
    );
  }
}
