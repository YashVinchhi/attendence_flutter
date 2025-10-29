import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/student_provider.dart';
import '../providers/attendance_provider.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Home'),
        centerTitle: true,
        elevation: 0,
      ),
      body: Consumer2<StudentProvider, AttendanceProvider>(
        builder: (context, studentProvider, attendanceProvider, child) {
          return Padding(
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
                          Text('Welcome back,', style: TextStyle(color: Theme.of(context).colorScheme.onBackground.withOpacity(0.7))),
                          const SizedBox(height: 4),
                          Text('Yash Vinchhi', style: Theme.of(context).textTheme.titleLarge),
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
                    Expanded(child: _buildSummaryBox(context, 'Present', '95%', Colors.green.shade100, Colors.green)),
                    const SizedBox(width: 12),
                    Expanded(child: _buildSummaryBox(context, 'Absent', '3', Colors.red.shade100, Colors.red)),
                    const SizedBox(width: 12),
                    Expanded(child: _buildSummaryBox(context, 'Late', '2', Colors.amber.shade100, Colors.amber)),
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
                    _buildQuickAction(context, 'Take Attendance', Icons.checklist, () => context.go('/attendance'), color: Theme.of(context).colorScheme.primary),
                    _buildQuickAction(context, 'View Reports', Icons.bar_chart, () => context.go('/reports')),
                    _buildQuickAction(context, 'Manage Students', Icons.people, () => context.go('/students')),
                    _buildQuickAction(context, 'Settings', Icons.settings, () => context.go('/settings')),
                  ],
                ),

                const SizedBox(height: 16),
                Text('Recent Activity', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView(
                    children: [
                      _buildActivityItem(Icons.check_circle, 'Attendance for \'Class A\' submitted', '5 mins ago', Colors.green),
                      _buildActivityItem(Icons.bar_chart, 'New weekly report generated', '1 hour ago', Colors.blue),
                      _buildActivityItem(Icons.swap_horiz, "Jane Doe's leave request approved", 'Yesterday', Colors.orange),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
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
          backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.15),
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
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0,2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: TextStyle(color: accent.withOpacity(0.9), fontWeight: FontWeight.w600)),
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
                  color: (color ?? scheme.primary).withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color ?? scheme.primary, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActivityItem(IconData icon, String title, String time, Color color) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: CircleAvatar(backgroundColor: color.withOpacity(0.12), child: Icon(icon, color: color)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(time),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}
