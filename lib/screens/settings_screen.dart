import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import '../services/database_helper.dart';
import '../providers/theme_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/student_provider.dart';
import '../providers/attendance_provider.dart';
import '../services/navigation_service.dart';
import '../providers/auth_provider.dart';

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
    // If provider holds default placeholder, prefer 'SOE RKU' as requested.
    final providerName = settingsProvider.schoolName;
    _schoolNameController.text = (providerName.trim().isEmpty || providerName == 'Your School Name') ? 'SOE RKU' : providerName;
    _academicYearController.text = settingsProvider.academicYear;
  }

  @override
  void dispose() {
    _schoolNameController.dispose();
    _academicYearController.dispose();
    super.dispose();
  }

  Future<void> _clearAllData() async {
    final navigationService = Provider.of<NavigationService>(context, listen: false);

    final bool? confirmed = await navigationService.showDialogSafely<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear Local Data'),
        content: const Text(
          'This will permanently remove all students and attendance stored locally on this device only. It will NOT delete any data already synced to the cloud (Firestore). Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
            child: const Text('Clear Local Data'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    await Future.delayed(const Duration(milliseconds: 200));

    // Show loading dialog (do not await)
    navigationService.showDialogSafely(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (loadingContext) => PopScope(
        canPop: false,
        child: const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Expanded(child: Text('Clearing all data...')),
            ],
          ),
        ),
      ),
    );

    try {
      final studentProvider = Provider.of<StudentProvider>(context, listen: false);
      final attendanceProvider = Provider.of<AttendanceProvider>(context, listen: false);

      // Clear all data
      final success = await studentProvider.clearAllData();
      attendanceProvider.clearRecords();

      if (!mounted) return;

      await navigationService.popDialog(context, useRootNavigator: true);
      await Future.delayed(const Duration(milliseconds: 200));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? 'Local data cleared (cloud data retained).' : 'Failed to clear local data'),
            backgroundColor: success ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.error,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;

      await navigationService.popDialog(context, useRootNavigator: true);
      await Future.delayed(const Duration(milliseconds: 200));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  // New: Backup students and attendance to a CSV file and offer to share/save it
  Future<void> _backupData() async {
    final navigationService = Provider.of<NavigationService>(context, listen: false);
    try {
      // Show loading dialog
      navigationService.showDialogSafely(
        context: context,
        barrierDismissible: false,
        useRootNavigator: true,
        builder: (ctx) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Expanded(child: Text('Preparing backup...')),
            ],
          ),
        ),
      );

      final dbHelper = DatabaseHelper.instance;

      // Fetch students and attendance
      final students = await dbHelper.getAllStudents();

      // Build CSV sections: header row for students, then a separator, then attendance rows
      List<List<dynamic>> csvRows = [];

      // Students header
      csvRows.add(['STUDENTS']);
      csvRows.add(['id', 'name', 'roll_number', 'semester', 'department', 'division', 'time_slot', 'created_at']);
      for (final s in students) {
        csvRows.add([
          s.id ?? '',
          s.name,
          s.rollNumber,
          s.semester,
          s.department,
          s.division,
          s.timeSlot,
          s.createdAt.toIso8601String(),
        ]);
      }

      // Attendance header
      csvRows.add([]);
      csvRows.add(['ATTENDANCE']);
      csvRows.add(['id', 'student_id', 'date', 'is_present', 'lecture', 'notes', 'created_at', 'updated_at']);

      // For attendance, fetch all records in date order
      final tempDir = await getApplicationDocumentsDirectory();
      final dbPath = tempDir.path; // reuse to get directory

      // Query attendance table directly using helper method: getAttendanceByDateRange covering wide span
      // We will try to cover last 10 years to fetch everything
      final now = DateTime.now();
      final fromDate = DateTime(now.year - 10, now.month, now.day).toIso8601String().substring(0, 10);
      final toDate = now.toIso8601String().substring(0, 10);
      final attendanceRows = await dbHelper.getAttendanceByDateRange(fromDate, toDate);

      for (final a in attendanceRows) {
        csvRows.add([
          a.id ?? '',
          a.studentId,
          a.date.toIso8601String().substring(0, 10),
          a.isPresent ? 1 : 0,
          a.lecture ?? '',
          a.notes ?? '',
          a.createdAt?.toIso8601String() ?? '',
          a.updatedAt?.toIso8601String() ?? '',
        ]);
      }

      final csv = const ListToCsvConverter().convert(csvRows);

      final fileName = 'attendance_backup_${DateTime.now().toIso8601String().replaceAll(':', '-')}.csv';
      final file = File(joinPaths(dbPath, fileName));
      await file.writeAsString(csv);

      // Close loading dialog
      await navigationService.popDialog(context, useRootNavigator: true);

      // Offer to share the file using top-level Share API
      await Share.shareXFiles([XFile(file.path)], text: 'Attendance backup generated');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Backup created: ${file.path}')),
        );
      }
    } catch (e) {
      try {
        final navigationService = Provider.of<NavigationService>(context, listen: false);
        await navigationService.popDialog(context, useRootNavigator: true);
      } catch (_) {}
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Backup failed: $e'), backgroundColor: Theme.of(context).colorScheme.error),
        );
      }
    }
  }

  // New: Restore students from a CSV file (uses StudentProvider.bulkImportFromCsv)
  Future<void> _restoreData() async {
    final navigationService = Provider.of<NavigationService>(context, listen: false);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );

      if (result == null || result.files.isEmpty) return; // user cancelled

      final fileBytes = result.files.first.bytes;
      final filePath = result.files.first.path;

      String csvContent;
      if (fileBytes != null) {
        csvContent = String.fromCharCodes(fileBytes);
      } else if (filePath != null) {
        csvContent = await File(filePath).readAsString();
      } else {
        throw Exception("Selected file couldn't be read");
      }

      // Show loading dialog
      navigationService.showDialogSafely(
        context: context,
        barrierDismissible: false,
        useRootNavigator: true,
        builder: (ctx) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Expanded(child: Text('Importing data...')),
            ],
          ),
        ),
      );

      final studentProvider = Provider.of<StudentProvider>(context, listen: false);
      final resultMap = await studentProvider.bulkImportFromCsv(csvContent);

      await navigationService.popDialog(context, useRootNavigator: true);

      if (resultMap['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Import completed: ${resultMap['imported']}/${resultMap['total']}')),
        );
      } else {
        final errors = (resultMap['errors'] as List<dynamic>?)?.join('\n') ?? resultMap['message'] ?? 'Unknown error';
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Import Result'),
            content: SingleChildScrollView(child: Text(errors)),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('OK')),
            ],
          ),
        );
      }
    } catch (e) {
      try {
        await navigationService.popDialog(context, useRootNavigator: true);
      } catch (_) {}
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Restore failed: $e'), backgroundColor: Theme.of(context).colorScheme.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final onSurface = scheme.onSurface;

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
                      Text(
                        'App Settings',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(color: onSurface, fontWeight: FontWeight.bold),
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
                      Text(
                        'School Information',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(color: onSurface, fontWeight: FontWeight.bold),
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
                      Text(
                        'Attendance Settings',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(color: onSurface, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 16),
                      ListTile(
                        leading: const Icon(Icons.warning),
                        title: Text('Minimum Attendance Percentage', style: TextStyle(color: onSurface)),
                        subtitle: Text('Current: ${settingsProvider.minimumAttendancePercentage}%', style: TextStyle(color: onSurface.withAlpha((0.85 * 255).round()))),
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
                      Text(
                        'App Information',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(color: onSurface, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 16),
                      ListTile(
                        leading: const Icon(Icons.info),
                        title: Text('App Version', style: TextStyle(color: onSurface)),
                        subtitle: Text('1.0.0', style: TextStyle(color: onSurface.withAlpha((0.85 * 255).round()))),
                      ),
                      ListTile(
                        leading: const Icon(Icons.description),
                        title: Text('About', style: TextStyle(color: onSurface)),
                        subtitle: Text('Attendance Management System for Educational Institutions', style: TextStyle(color: onSurface.withAlpha((0.85 * 255).round()))),
                      ),
                      ListTile(
                        leading: const Icon(Icons.developer_mode),
                        title: Text('Developed by', style: TextStyle(color: onSurface)),
                        subtitle: Text('Yash Vinchhi', style: TextStyle(color: onSurface.withAlpha((0.85 * 255).round()))),
                        onTap: () {
                          showDialog(
                            context: context,
                            useRootNavigator: true,
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
                      Text(
                        'Data Management',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(color: onSurface, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 16),
                      ListTile(
                        leading: const Icon(Icons.backup),
                        title: Text('Backup Data', style: TextStyle(color: onSurface)),
                        subtitle: Text('Export all data as CSV', style: TextStyle(color: onSurface.withAlpha((0.85 * 255).round()))),
                        onTap: () {
                          _backupData();
                        },
                      ),
                      ListTile(
                        leading: const Icon(Icons.restore),
                        title: Text('Restore Data', style: TextStyle(color: onSurface)),
                        subtitle: Text('Import data from CSV', style: TextStyle(color: onSurface.withAlpha((0.85 * 255).round()))),
                        onTap: () {
                          _restoreData();
                        },
                      ),
                      ListTile(
                        leading: Icon(Icons.delete_forever, color: Theme.of(context).colorScheme.error),
                        title: Text('Clear All Data', style: TextStyle(color: onSurface)),
                        subtitle: Text('Delete all students and attendance records', style: TextStyle(color: onSurface.withAlpha((0.85 * 255).round()))),
                        onTap: () {
                          _clearAllData();
                        },
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Account actions
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Account', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: onSurface, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
                        onPressed: () async {
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Sign out'),
                              content: const Text('Are you sure you want to sign out?'),
                              actions: [
                                TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
                                ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error), child: const Text('Sign out')),
                              ],
                            ),
                          );
                          if (confirmed == true) {
                            try {
                              await AuthProvider.instance.signOut();
                              if (!mounted) return;
                              // Redirect to sign-in (router redirect will also handle this)
                              context.go('/signin');
                              if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Signed out')));
                            } catch (e) {
                              if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Sign out failed: $e')));
                            }
                          }
                        },
                        icon: const Icon(Icons.logout),
                        label: const Text('Sign out'),
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

// Helper to join paths without introducing new dependency
String joinPaths(String a, String b) {
  if (a.endsWith(Platform.pathSeparator)) return '$a$b';
  return '$a${Platform.pathSeparator}$b';
}
