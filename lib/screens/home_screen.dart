import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../providers/user_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/attendance_provider.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  // Parse class display strings like '3CE-B' or '3CE/IT-B' into tuple
  Map<String, String>? _parseClassDisplay(String s) {
    final re = RegExp(r'^(\d{1,2})([A-Za-z\/]+)-([A-Za-z]+)\$');
    final m = re.firstMatch(s.trim());
    if (m == null) return null;
    return {'semester': m.group(1)!, 'department': m.group(2)!, 'division': m.group(3)!};
  }

  Future<Map<String,int>> _computeTodaySummary(BuildContext context) async {
    try {
      final userProv = Provider.of<UserProvider>(context, listen: false);
      final attendanceProv = Provider.of<AttendanceProvider>(context, listen: false);
      final classes = userProv.allowedClasses; // display strings like '3CE-B'
      final date = DateTime.now().toIso8601String().substring(0,10);

      int present = 0, absent = 0, late = 0;

      if (classes.isEmpty) {
        // If no classes assigned, return zeros
        return {'present': 0, 'absent': 0, 'late': 0};
      }

      for (final cd in classes) {
        final parsed = _parseClassDisplay(cd);
        if (parsed == null) continue;
        final sem = int.tryParse(parsed['semester']!);
        final dept = parsed['department']!;
        final div = parsed['division']!;
        if (sem == null) continue;
        try {
          final stats = await attendanceProv.getAttendanceStatistics(date, sem, dept, div);
          present += (stats['present'] as int?) ?? 0;
          absent += (stats['absent'] as int?) ?? 0;
          // no explicit late tracking currently; leave as 0
        } catch (_) {
          // ignore failures per-class and continue
        }
      }

      return {'present': present, 'absent': absent, 'late': late};
    } catch (e) {
      return {'present': 0, 'absent': 0, 'late': 0};
    }
  }

  @override
  Widget build(BuildContext context) {
    // Read providers via context.watch so UI updates when user/provider state changes
    // Providers accessed only where needed; avoid unused local variables
    // (read via context.watch where used)
    final userProvider = context.watch<UserProvider>();
    final authEmail = AuthProvider.instance.email;

    final role = userProvider.user?.role.name;
    final displayName = userProvider.user?.name ?? authEmail ?? 'User';
    final isAdmin = userProvider.isAdmin;
    final isCC = role == 'CC';
    final hasClasses = userProvider.allowedClasses.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Home'),
        centerTitle: true,
        elevation: 0,
        actions: [
          if (kDebugMode) ...[
            IconButton(
              tooltip: 'Check Profile',
              icon: const Icon(Icons.person_search),
              onPressed: () => _checkMyProfile(context),
            ),
          ],
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Redesigned the section displaying the user's name, image, and role
              Row(
                children: [
                  CircleAvatar(
                    radius: 36,
                    backgroundColor: Theme.of(context).colorScheme.primary.withAlpha(50),
                    child: CircleAvatar(
                      radius: 32,
                      backgroundImage: AssetImage('assets/fox.png'), // Replace with actual user image if available
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayName,
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        if (role != null)
                          Text(
                            'Role: $role',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Today's summary
              Text('Today\'s Summary', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              FutureBuilder<Map<String,int>>(
                future: _computeTodaySummary(context),
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    // lightweight loading placeholders
                    return Row(
                      children: [
                        Expanded(child: _buildSummaryBox(context, 'Present', '—', Theme.of(context).colorScheme.primary.withAlpha(0x15), Theme.of(context).colorScheme.primary)),
                        const SizedBox(width: 12),
                        Expanded(child: _buildSummaryBox(context, 'Absent', '—', Theme.of(context).colorScheme.error.withAlpha(0x12), Theme.of(context).colorScheme.error)),
                        const SizedBox(width: 12),
                        Expanded(child: _buildSummaryBox(context, 'Late', '—', Theme.of(context).colorScheme.tertiary.withAlpha(0x12), Theme.of(context).colorScheme.tertiary)),
                      ],
                    );
                  }
                  final data = snap.data ?? {'present':0,'absent':0,'late':0};
                  return Row(
                    children: [
                      Expanded(child: _buildSummaryBox(context, 'Present', '${data['present']}', Theme.of(context).colorScheme.primary.withAlpha(0x15), Theme.of(context).colorScheme.primary)),
                      const SizedBox(width: 12),
                      Expanded(child: _buildSummaryBox(context, 'Absent', '${data['absent']}', Theme.of(context).colorScheme.error.withAlpha(0x12), Theme.of(context).colorScheme.error)),
                      const SizedBox(width: 12),
                      Expanded(child: _buildSummaryBox(context, 'Late', '${data['late']}', Theme.of(context).colorScheme.tertiary.withAlpha(0x12), Theme.of(context).colorScheme.tertiary)),
                    ],
                  );
                },
              ),

              const SizedBox(height: 20),
              Text('Quick Actions', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),

              // Quick action grid (responsive wrap to avoid uneven spacing when number of actions is odd)
              LayoutBuilder(
                builder: (context, constraints) {
                  final tileWidth = (constraints.maxWidth - 12) / 2;
                  final List<Widget> actions = [];

                  void addAction(Widget w) => actions.add(SizedBox(width: tileWidth, child: w));

                  addAction(_buildQuickAction(
                    context,
                    'Take Attendance',
                    Icons.checklist,
                    hasClasses || isAdmin ? () => context.go('/attendance') : () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('You have no classes assigned'))),
                    color: Theme.of(context).colorScheme.primary,
                  ));
                  addAction(_buildQuickAction(context, 'View Reports', Icons.bar_chart, () => context.go('/reports')));
                  if (isAdmin || isCC) addAction(_buildQuickAction(context, 'Manage Students', Icons.people, () => context.go('/students')));
                  if (role == 'HOD') addAction(_buildQuickAction(context, 'Manage CCs', Icons.manage_accounts, () => context.go('/manage-ccs')));
                  if (role == 'HOD' || role == 'CC') addAction(_buildQuickAction(context, 'Manage CRs', Icons.how_to_reg, () => context.go('/manage-crs')));
                  addAction(_buildQuickAction(context, 'Settings', Icons.settings, () => context.go('/settings')));

                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: actions,
                  );
                },
              ),

              const SizedBox(height: 16),
              // Recent Activity removed as requested
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryBox(BuildContext context, String label, String value, Color bg, Color accent) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Theme.of(context).colorScheme.shadow.withAlpha(0x14), blurRadius: 6, offset: const Offset(0,1))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: TextStyle(color: accent.withValues(alpha: 0.9), fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: accent)),
        ],
      ),
    );
  }

  Widget _buildQuickAction(BuildContext context, String title, IconData icon, VoidCallback onTap, {Color? color}) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: (color ?? scheme.primary).withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color ?? scheme.primary, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(title, style: TextStyle(fontWeight: FontWeight.w600, color: scheme.onSurface)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _checkMyProfile(BuildContext context) async {
    final uid = AuthProvider.instance.uid;
    if (uid == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Not signed in')));
      return;
    }
    try {
      final snap = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (!snap.exists) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile not found in Firestore')));
        return;
      }
      final data = snap.data();
      // Enhanced Firestore profile viewing dialog
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.person, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              const Text('Firestore Profile'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: data != null
                  ? data.entries.map<Widget>((entry) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${entry.key}: ',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.secondary,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            '${entry.value}',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  )).toList()
                  : [
                    Text(
                      'No data available',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error reading profile: $e')));
    }
  }
}
