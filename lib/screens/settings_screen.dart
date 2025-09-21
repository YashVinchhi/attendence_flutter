import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../providers/theme_provider.dart';
import '../providers/settings_provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TextEditingController _schoolNameController = TextEditingController();
  final TextEditingController _academicYearController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final settingsProvider = Provider.of<SettingsProvider>(context, listen: false);
    _schoolNameController.text = settingsProvider.schoolName;
    _academicYearController.text = settingsProvider.academicYear;
  }

  @override
  void dispose() {
    _schoolNameController.dispose();
    _academicYearController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        leading: IconButton(
          icon: const Icon(Icons.home),
          onPressed: () => context.go('/home'),
        ),
      ),
      body: Consumer2<ThemeProvider, SettingsProvider>(
        builder: (context, themeProvider, settingsProvider, child) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // App Settings
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'App Settings',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 16),
                      ListTile(
                        leading: const Icon(Icons.dark_mode),
                        title: const Text('Dark Mode'),
                        trailing: Switch(
                          value: themeProvider.themeMode == ThemeMode.dark,
                          onChanged: (value) {
                            themeProvider.setThemeMode(
                              value ? ThemeMode.dark : ThemeMode.light,
                            );
                          },
                        ),
                      ),
                      ListTile(
                        leading: const Icon(Icons.percent),
                        title: const Text('Show Percentage in Lists'),
                        subtitle: const Text('Display attendance percentage in student lists'),
                        trailing: Switch(
                          value: settingsProvider.showPercentageInList,
                          onChanged: (value) {
                            settingsProvider.togglePercentageDisplay();
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // School Information
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'School Information',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _schoolNameController,
                        decoration: const InputDecoration(
                          labelText: 'School Name',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.school),
                        ),
                        onChanged: (value) {
                          settingsProvider.updateSchoolName(value);
                        },
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _academicYearController,
                        decoration: const InputDecoration(
                          labelText: 'Academic Year',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.calendar_today),
                          hintText: 'e.g., 2023-24',
                        ),
                        onChanged: (value) {
                          settingsProvider.updateAcademicYear(value);
                        },
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Attendance Settings
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Attendance Settings',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 16),
                      ListTile(
                        leading: const Icon(Icons.warning),
                        title: const Text('Minimum Attendance Percentage'),
                        subtitle: Text('Current: ${settingsProvider.minimumAttendancePercentage}%'),
                        trailing: SizedBox(
                          width: 100,
                          child: Slider(
                            value: settingsProvider.minimumAttendancePercentage.toDouble(),
                            min: 0,
                            max: 100,
                            divisions: 20,
                            label: '${settingsProvider.minimumAttendancePercentage}%',
                            onChanged: (value) {
                              settingsProvider.updateMinimumAttendance(value.round());
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // App Information
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'App Information',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 16),
                      const ListTile(
                        leading: Icon(Icons.info),
                        title: Text('App Version'),
                        subtitle: Text('1.0.0'),
                      ),
                      const ListTile(
                        leading: Icon(Icons.description),
                        title: Text('About'),
                        subtitle: Text('Attendance Management System for Educational Institutions'),
                      ),
                      ListTile(
                        leading: const Icon(Icons.developer_mode),
                        title: const Text('Developed by'),
                        subtitle: const Text('Flutter Team'),
                        onTap: () {
                          showDialog(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('About Developer'),
                              content: const Text(
                                'This app was developed using Flutter framework to help educational institutions manage student attendance efficiently.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(context).pop(),
                                  child: const Text('OK'),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Data Management
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Data Management',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 16),
                      ListTile(
                        leading: const Icon(Icons.backup),
                        title: const Text('Backup Data'),
                        subtitle: const Text('Export all data as CSV'),
                        onTap: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Backup feature coming soon!'),
                            ),
                          );
                        },
                      ),
                      ListTile(
                        leading: const Icon(Icons.restore),
                        title: const Text('Restore Data'),
                        subtitle: const Text('Import data from CSV'),
                        onTap: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Restore feature coming soon!'),
                            ),
                          );
                        },
                      ),
                      ListTile(
                        leading: const Icon(Icons.delete_forever, color: Colors.red),
                        title: const Text('Clear All Data'),
                        subtitle: const Text('Delete all students and attendance records'),
                        onTap: () {
                          showDialog(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Clear All Data'),
                              content: const Text(
                                'Are you sure you want to delete all data? This action cannot be undone.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(context).pop(),
                                  child: const Text('Cancel'),
                                ),
                                TextButton(
                                  onPressed: () {
                                    Navigator.of(context).pop();
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Clear data feature coming soon!'),
                                      ),
                                    );
                                  },
                                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                                  child: const Text('Clear'),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 32),
            ],
          );
        },
      ),
    );
  }
}
