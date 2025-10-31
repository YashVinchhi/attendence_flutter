import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:provider/provider.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../providers/user_provider.dart';
import '../providers/auth_provider.dart';
import '../services/auth_service.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

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
    final canInvite = isAdmin || isCC || role == 'HOD';
    final canManageStudents = isAdmin || isCC;
    final hasClasses = userProvider.allowedClasses.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Home'),
        centerTitle: true,
        elevation: 0,
        actions: [
          if (kDebugMode) ...[
            IconButton(
              tooltip: 'Debug Sign-in',
              icon: const Icon(Icons.login_outlined),
              onPressed: () => context.go('/debug-signin'),
            ),
            IconButton(
              tooltip: 'Pending Profiles',
              icon: const Icon(Icons.sync_problem),
              onPressed: () => _showPendingProfilesDialog(context),
            ),
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
              Row(
                children: [
                  _buildLogoAvatar(context),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Welcome back,', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7))),
                        const SizedBox(height: 4),
                        Text(displayName, style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 2),
                        if (role != null) Text('Role: $role', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 12)),
                        if (!hasClasses && !isAdmin) Text('No classes assigned', style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12)),
                      ],
                    ),
                  ),
                  IconButton(onPressed: () {}, icon: Icon(Icons.notifications_outlined)),
                ],
              ),
              const SizedBox(height: 20),

              // Summary boxes
              Row(
                children: [
                  Expanded(child: _buildSummaryBox(context, 'Present', '95%', Theme.of(context).colorScheme.primary.withAlpha(0x15), Theme.of(context).colorScheme.primary)),
                  const SizedBox(width: 12),
                  Expanded(child: _buildSummaryBox(context, 'Absent', '3', Theme.of(context).colorScheme.error.withAlpha(0x12), Theme.of(context).colorScheme.error)),
                  const SizedBox(width: 12),
                  Expanded(child: _buildSummaryBox(context, 'Late', '2', Theme.of(context).colorScheme.tertiary.withAlpha(0x12), Theme.of(context).colorScheme.tertiary)),
                ],
              ),

              const SizedBox(height: 20),
              Text('Quick Actions', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),

              // Quick action grid
              GridView.count(
                shrinkWrap: true,
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.6,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildQuickAction(
                    context,
                    'Take Attendance',
                    Icons.checklist,
                    hasClasses || isAdmin ? () => context.go('/attendance') : () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('You have no classes assigned'))),
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  _buildQuickAction(context, 'View Reports', Icons.bar_chart, () => context.go('/reports')),
                  if (canManageStudents) _buildQuickAction(context, 'Manage Students', Icons.people, () => context.go('/students')),
                  if (canInvite) _buildQuickAction(context, 'Create Invite', Icons.person_add, () => context.go('/create-invite')),
                  if (role == 'HOD') _buildQuickAction(context, 'Manage CCs', Icons.manage_accounts, () => context.go('/manage-ccs')),
                  if (role == 'HOD' || role == 'CC') _buildQuickAction(context, 'Manage CRs', Icons.how_to_reg, () => context.go('/manage-crs')),
                  _buildQuickAction(context, 'Settings', Icons.settings, () => context.go('/settings')),
                ],
              ),

              const SizedBox(height: 16),
              // Recent Activity removed as requested
            ],
          ),
        ),
      ),
    );
  }

  // Attempts to load `assets/fox.png` from the asset bundle. If the asset
  // is missing or fails to load, falls back to the default avatar icon.
  Widget _buildLogoAvatar(BuildContext context) {
    return FutureBuilder<ByteData>(
      future: rootBundle.load('assets/fox.png'),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done && snapshot.hasData) {
          final bytes = snapshot.data!.buffer.asUint8List();
          return CircleAvatar(
            radius: 28,
            backgroundImage: MemoryImage(bytes),
            backgroundColor: Colors.transparent,
          );
        }

        // Fallback avatar while loading or if asset not found
        return CircleAvatar(
          radius: 28,
          backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
          child: Icon(Icons.person, color: Theme.of(context).colorScheme.primary),
        );
      },
    );
  }

  Widget _buildSummaryBox(BuildContext context, String label, String value, Color bg, Color accent) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Theme.of(context).colorScheme.shadow.withAlpha(0x20), blurRadius: 8, offset: const Offset(0,2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: TextStyle(color: accent.withValues(alpha: 0.9), fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: accent)),
        ],
      ),
    );
  }

  Widget _buildQuickAction(BuildContext context, String title, IconData icon, VoidCallback onTap, {Color? color}) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 4,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(14),
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

  Future<void> _showPendingProfilesDialog(BuildContext context) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where((k) => k.startsWith('pending_profile_')).toList();
      if (keys.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No pending profiles')));
        return;
      }

      await showDialog<void>(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            title: const Text('Pending Profiles'),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: keys.length,
                itemBuilder: (c, i) {
                  final k = keys[i];
                  final uid = k.replaceFirst('pending_profile_', '');
                  final raw = prefs.getString(k) ?? '';
                  String pretty;
                  try {
                    final obj = jsonDecode(raw);
                    pretty = const JsonEncoder.withIndent('  ').convert(obj);
                  } catch (_) {
                    pretty = raw;
                  }
                  return Card(
                    child: ListTile(
                      title: Text(uid),
                      subtitle: Text(pretty, maxLines: 6, overflow: TextOverflow.ellipsis),
                      isThreeLine: true,
                      trailing: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Retry',
                            icon: const Icon(Icons.refresh),
                            onPressed: () async {
                              Navigator.of(ctx).pop();
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Retrying pending profiles...')));
                              await AuthService.instance.retryPendingProfiles();
                            },
                          ),
                          IconButton(
                            tooltip: 'Delete',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () async {
                              await prefs.remove(k);
                              Navigator.of(ctx).pop();
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Removed pending profile')));
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Close'))],
          );
        },
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error reading pending profiles: $e')));
    }
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
      await showDialog<void>(context: context, builder: (ctx) => AlertDialog(title: const Text('Firestore profile'), content: SingleChildScrollView(child: Text(data.toString())), actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Close'))]));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error reading profile: $e')));
    }
  }
}
