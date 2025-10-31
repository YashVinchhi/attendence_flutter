import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:cross_file/cross_file.dart';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';
import '../providers/report_provider.dart';
import '../providers/student_provider.dart';
import '../providers/attendance_provider.dart';
import '../services/database_helper.dart';
import '../services/navigation_service.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  DateTime _fromDate = DateTime.now().subtract(const Duration(days: 30));
  DateTime _toDate = DateTime.now();
  DateTime _selectedReportDate = DateTime.now();
  int _selectedSemester = 3;
  String _selectedClassType = 'CE/IT';
  String _selectedDivision = 'B';
  // Trend chart specific filters
  String _trendDepartment = 'All';
  int _trendSemester = 0; // 0 means All Semesters
  List<Map<String, dynamic>> _trendData = [];

  // Return a short label for a trend entry: prefer the lecture number (e.g. '1', '2', ...).
  String _shortLectureLabel(Map<String, dynamic> entry) {
    final raw = (entry['label'] ?? '').toString();
    // Try to extract the first integer (lecture number) from labels like 'Lec 1 (8:00-8:50)'
    final m = RegExp(r'\d+').firstMatch(raw);
    if (m != null) return m.group(0)!;
    // Fallback: try to extract timeslot like '8:00-8:50' and return it (but user prefers numbers)
    final t = RegExp(r'\d{1,2}:\d{2}-\d{1,2}:\d{2}').firstMatch(raw);
    if (t != null) return t.group(0)!;
    return raw;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadReports();
    });
  }

  Future<void> _loadReports() async {
    final reportProvider = Provider.of<ReportProvider>(context, listen: false);
    final studentProvider = Provider.of<StudentProvider>(context, listen: false);

    if (studentProvider.students.isEmpty) {
      await studentProvider.fetchStudents();
    }

    await reportProvider.generateAttendanceReport(
      _fromDate.toIso8601String().substring(0, 10),
      _toDate.toIso8601String().substring(0, 10),
    );
  }

  Future<void> _shareFormattedAbsenteeReport() async {
    try {
      final attendanceProvider = Provider.of<AttendanceProvider>(context, listen: false);

      final reportDate = _selectedReportDate.toIso8601String().substring(0, 10);
      final formattedReport = await attendanceProvider.generateFormattedAbsenteeReport(
        reportDate,
        _selectedSemester,
        _selectedClassType,
        _selectedDivision,
      );

      // ignore: deprecated_member_use
      await Share.share(formattedReport, subject: 'Daily Absentee Report - $_selectedSemester$_selectedClassType-$_selectedDivision');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error sharing absentee report: $e')),
      );
    }
  }

  // New method to share different types of daily attendance reports
  Future<void> _shareFormattedAttendanceReport(String reportType) async {
    if (!mounted) return;

    final navigationService = Provider.of<NavigationService>(context, listen: false);

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
              Expanded(child: Text('Generating report...')),
            ],
          ),
        ),
      ),
    );

    try {
      final attendanceProvider = Provider.of<AttendanceProvider>(context, listen: false);

      final reportDate = _selectedReportDate.toIso8601String().substring(0, 10);
      final formattedReport = await attendanceProvider.generateFormattedAttendanceReport(
        reportDate,
        _selectedSemester,
        _selectedClassType,
        _selectedDivision,
        reportType: reportType,
      );

      String reportTitle = '';
      switch (reportType) {
        case 'present':
          reportTitle = 'Daily Present Students Report';
          break;
        case 'all':
          reportTitle = 'Complete Daily Attendance Report';
          break;
        default:
          reportTitle = 'Daily Absentee Report';
      }

      if (!mounted) return;

      // Close loading dialog
      await navigationService.popDialog(context, useRootNavigator: true);

      // Add delay before sharing
      await Future.delayed(const Duration(milliseconds: 200));

      if (!mounted) return;

      // ignore: deprecated_member_use
      await Share.share(formattedReport, subject: '$reportTitle - $_selectedSemester$_selectedClassType-$_selectedDivision');
    } catch (e) {
      if (mounted) {
        // Close loading dialog if still showing
        await navigationService.popDialog(context, useRootNavigator: true);

        await Future.delayed(const Duration(milliseconds: 200));

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error sharing $reportType report: $e')),
          );
        }
      }
    }
  }

  // Show dialog to choose report type
  Future<void> _showDailyReportOptions() async {
    final String? reportType = await showDialog<String>(
      context: context,
      useRootNavigator: true,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Choose Report Type'),
          content: const Text('What type of daily attendance report would you like to share?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop('absentees'),
              child: const Text('Absent Students Only'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop('present'),
              child: const Text('Present Students Only'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop('all'),
              child: const Text('Complete Report (All Students)'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );

    if (reportType != null && mounted) {
      // Add a small delay to ensure the dialog is fully closed
      await Future.delayed(const Duration(milliseconds: 200));
      if (mounted) {
        await _shareFormattedAttendanceReport(reportType);
      }
    }
  }

  Future<void> _shareReport() async {
    try {
      final reportProvider = Provider.of<ReportProvider>(context, listen: false);
      final studentProvider = Provider.of<StudentProvider>(context, listen: false);

      // Generate CSV content
      List<List<String>> csvData = [
        ['Student Name', 'Roll Number', 'Semester', 'Department', 'Division', 'Total Classes', 'Present', 'Absent', 'Attendance %']
      ];

      for (var student in studentProvider.students) {
        final attendanceData = reportProvider.getStudentAttendanceData(student.id);
        csvData.add([
          student.name,
          student.rollNumber,
          student.semester.toString(),
          student.department,
          student.division,
          attendanceData['total'].toString(),
          attendanceData['present'].toString(),
          attendanceData['absent'].toString(),
          '${attendanceData['percentage'].toStringAsFixed(1)}%',
        ]);
      }

      String csvString = const ListToCsvConverter().convert(csvData);

      // Create a temporary file
      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/attendance_report_${DateTime.now().millisecondsSinceEpoch}.csv');
      await file.writeAsString(csvString);

      // ignore: deprecated_member_use
      await Share.shareXFiles([XFile(file.path)], text: 'Attendance Report from ${_fromDate.toIso8601String().substring(0, 10)} to ${_toDate.toIso8601String().substring(0, 10)}', subject: 'Attendance Report');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error sharing report: $e')),
      );
    }
  }

  Future<void> _shareTextReport() async {
    try {
      final reportProvider = Provider.of<ReportProvider>(context, listen: false);
      final studentProvider = Provider.of<StudentProvider>(context, listen: false);

      StringBuffer reportText = StringBuffer();
      reportText.writeln('ATTENDANCE REPORT');
      reportText.writeln('Period: ${_fromDate.toIso8601String().substring(0, 10)} to ${_toDate.toIso8601String().substring(0, 10)}');
      reportText.writeln('Generated on: ${DateTime.now().toIso8601String().substring(0, 10)}');
      reportText.writeln('');
      reportText.writeln('Student Details:');
      reportText.writeln('-' * 50);

      for (var student in studentProvider.students) {
        final attendanceData = reportProvider.getStudentAttendanceData(student.id);
        reportText.writeln('Name: ${student.name}');
        reportText.writeln('Roll No: ${student.rollNumber}');
        reportText.writeln('Semester: ${student.semester}');
        reportText.writeln('Department: ${student.department}');
        reportText.writeln('Division: ${student.division}');
        reportText.writeln('Total Classes: ${attendanceData['total']}');
        reportText.writeln('Present: ${attendanceData['present']}');
        reportText.writeln('Absent: ${attendanceData['absent']}');
        reportText.writeln('Attendance: ${attendanceData['percentage'].toStringAsFixed(1)}%');
        reportText.writeln('-' * 30);
      }

      // ignore: deprecated_member_use
      await Share.share(reportText.toString(), subject: 'Attendance Report');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error sharing report: $e')),
      );
    }
  }

  Future<String?> _getSavedCcEmail() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final e = prefs.getString('last_import_cc_email');
      if (e != null && e.trim().isNotEmpty) return e.trim();
    } catch (_) {}
    return null;
  }

  Future<void> _emailFormattedAttendanceReport(String reportType) async {
    if (!mounted) return;
    try {
      final attendanceProvider = Provider.of<AttendanceProvider>(context, listen: false);
      final reportDate = _selectedReportDate.toIso8601String().substring(0, 10);
      final formattedReport = await attendanceProvider.generateFormattedAttendanceReport(
        reportDate,
        _selectedSemester,
        _selectedClassType,
        _selectedDivision,
        reportType: reportType,
      );

      String reportTitle = reportType == 'present' ? 'Daily Present Students Report' : reportType == 'all' ? 'Complete Daily Attendance Report' : 'Daily Absentee Report';

      final ccEmail = await _getSavedCcEmail();

      final subject = Uri.encodeComponent('$reportTitle - $_selectedSemester$_selectedClassType-$_selectedDivision');
      final body = Uri.encodeComponent(formattedReport);
      final queryParameters = <String, String>{'subject': subject, 'body': body};
      if (ccEmail != null && ccEmail.isNotEmpty) queryParameters['cc'] = ccEmail;

      final uri = Uri(scheme: 'mailto', path: '', queryParameters: queryParameters);
      if (!await launchUrl(uri)) {
        throw 'Could not open mail client';
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error preparing email: $e')));
    }
  }

  Future<void> _emailTextReport() async {
    try {
      final reportProvider = Provider.of<ReportProvider>(context, listen: false);
      final studentProvider = Provider.of<StudentProvider>(context, listen: false);

      StringBuffer reportText = StringBuffer();
      reportText.writeln('ATTENDANCE REPORT');
      reportText.writeln('Period: ${_fromDate.toIso8601String().substring(0, 10)} to ${_toDate.toIso8601String().substring(0, 10)}');
      reportText.writeln('Generated on: ${DateTime.now().toIso8601String().substring(0, 10)}');
      reportText.writeln('');
      reportText.writeln('Student Details:');
      reportText.writeln('-' * 50);

      for (var student in studentProvider.students) {
        final attendanceData = reportProvider.getStudentAttendanceData(student.id);
        reportText.writeln('Name: ${student.name}');
        reportText.writeln('Roll No: ${student.rollNumber}');
        reportText.writeln('Semester: ${student.semester}');
        reportText.writeln('Department: ${student.department}');
        reportText.writeln('Division: ${student.division}');
        reportText.writeln('Total Classes: ${attendanceData['total']}');
        reportText.writeln('Present: ${attendanceData['present']}');
        reportText.writeln('Absent: ${attendanceData['absent']}');
        reportText.writeln('Attendance: ${attendanceData['percentage'].toStringAsFixed(1)}%');
        reportText.writeln('-' * 30);
      }

      final ccEmail = await _getSavedCcEmail();
      final subject = Uri.encodeComponent('Attendance Report - ${_fromDate.toIso8601String().substring(0, 10)} to ${_toDate.toIso8601String().substring(0, 10)}');
      final body = Uri.encodeComponent(reportText.toString());
      final params = {'subject': subject, 'body': body};
      if (ccEmail != null) params['cc'] = ccEmail;
      final uri = Uri(scheme: 'mailto', path: '', queryParameters: params);
      if (!await launchUrl(uri)) throw 'Could not open mail client';
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error preparing email: $e')));
    }
  }

  Future<void> _emailCsvReport() async {
    try {
      // Generate CSV like _shareReport and then share the file. mailto cannot attach files reliably, so copy CC to clipboard and include in subject.
      final reportProvider = Provider.of<ReportProvider>(context, listen: false);
      final studentProvider = Provider.of<StudentProvider>(context, listen: false);

      List<List<String>> csvData = [
        ['Student Name', 'Roll Number', 'Semester', 'Department', 'Division', 'Total Classes', 'Present', 'Absent', 'Attendance %']
      ];

      for (var student in studentProvider.students) {
        final attendanceData = reportProvider.getStudentAttendanceData(student.id);
        csvData.add([
          student.name,
          student.rollNumber,
          student.semester.toString(),
          student.department,
          student.division,
          attendanceData['total'].toString(),
          attendanceData['present'].toString(),
          attendanceData['absent'].toString(),
          '${attendanceData['percentage'].toStringAsFixed(1)}%',
        ]);
      }

      String csvString = const ListToCsvConverter().convert(csvData);
      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/attendance_report_${DateTime.now().millisecondsSinceEpoch}.csv');
      await file.writeAsString(csvString);

      final ccEmail = await _getSavedCcEmail();
      if (ccEmail != null && ccEmail.isNotEmpty) {
        await Clipboard.setData(ClipboardData(text: ccEmail));
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('CC email copied to clipboard')));
      }

      final subject = 'Attendance Report from ${_fromDate.toIso8601String().substring(0, 10)} to ${_toDate.toIso8601String().substring(0, 10)}' + (ccEmail != null ? ' (cc: $ccEmail)' : '');
      // ignore: deprecated_member_use
      await Share.shareXFiles([XFile(file.path)], text: 'Attendance CSV attached', subject: subject);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error preparing CSV email: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final dbHelper = DatabaseHelper.instance;
    // Compute a safe chart height: prefer 258px but cap to a fraction of screen height to avoid overflow
    final chartHeight = min(258.0, MediaQuery.of(context).size.height * 0.32);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Attendance Reports'),
          leading: IconButton(
            icon: const Icon(Icons.home),
            onPressed: () => context.go('/home'),
            tooltip: 'Back to Home',
          ),
          bottom: const TabBar(tabs: [Tab(text: 'Daily'), Tab(text: 'Overall')]),
          actions: [
            IconButton(
              icon: const Icon(Icons.share),
              tooltip: 'Share Report',
              onPressed: () async {
                final choice = await showDialog<String>(
                  context: context,
                  builder: (ctx) => SimpleDialog(
                    title: const Text('Share Report'),
                    children: [
                      SimpleDialogOption(
                        onPressed: () => Navigator.pop(ctx, 'daily_options'),
                        child: Row(children: const [Icon(Icons.today), SizedBox(width: 8), Text('Daily Report Options')]),
                      ),
                      SimpleDialogOption(
                        onPressed: () => Navigator.pop(ctx, 'absentee'),
                        child: Row(children: const [Icon(Icons.report_problem), SizedBox(width: 8), Text('Daily Absentee Report')]),
                      ),
                      SimpleDialogOption(
                        onPressed: () => Navigator.pop(ctx, 'csv'),
                        child: Row(children: const [Icon(Icons.grid_on), SizedBox(width: 8), Text('CSV Report')]),
                      ),
                      SimpleDialogOption(
                        onPressed: () => Navigator.pop(ctx, 'text'),
                        child: Row(children: const [Icon(Icons.text_snippet), SizedBox(width: 8), Text('Plain Text Report')]),
                      ),
                      SimpleDialogOption(
                        onPressed: () => Navigator.pop(ctx, 'email'),
                        child: Row(children: const [Icon(Icons.email), SizedBox(width: 8), Text('Email Report (prefill CC)')]),
                      ),
                      SimpleDialogOption(
                        onPressed: () => Navigator.pop(ctx, null),
                        child: const Text('Cancel'),
                      ),
                    ],
                  ),
                );

                if (choice == 'email') {
                  // Show email format options
                  final emailChoice = await showDialog<String>(
                    context: context,
                    useRootNavigator: true,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Email Report As'),
                      content: const Text('Choose format to include in email body'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, 'formatted'), child: const Text('Formatted Daily')),
                        TextButton(onPressed: () => Navigator.pop(ctx, 'csv'), child: const Text('CSV (attachable via share)')),
                        TextButton(onPressed: () => Navigator.pop(ctx, 'text'), child: const Text('Plain Text')),
                        TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('Cancel')),
                      ],
                    ),
                  );

                  if (emailChoice == 'formatted') {
                    // Let user choose which daily formatted report type
                    final String? reportType = await showDialog<String>(
                      context: context,
                      useRootNavigator: true,
                      builder: (BuildContext dialogContext) {
                        return AlertDialog(
                          title: const Text('Choose Report Type'),
                          content: const Text('What type of daily attendance report would you like to email?'),
                          actions: [
                            TextButton(onPressed: () => Navigator.of(dialogContext).pop('absentees'), child: const Text('Absent Students Only')),
                            TextButton(onPressed: () => Navigator.of(dialogContext).pop('present'), child: const Text('Present Students Only')),
                            TextButton(onPressed: () => Navigator.of(dialogContext).pop('all'), child: const Text('Complete Report (All Students)')),
                            TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
                          ],
                        );
                      },
                    );
                    if (reportType != null) await _emailFormattedAttendanceReport(reportType);
                  } else if (emailChoice == 'text') {
                    await _emailTextReport();
                  } else if (emailChoice == 'csv') {
                    await _emailCsvReport();
                  }
                }
                else
                 if (choice == 'absentee') {
                   _shareFormattedAbsenteeReport();
                 } else if (choice == 'csv') {
                   _shareReport();
                 } else if (choice == 'text') {
                   _shareTextReport();
                 } else if (choice == 'daily_options') {
                   _showDailyReportOptions();
                 }
               },
             ),
           ],
         ),
        body: Consumer3<ReportProvider, StudentProvider, AttendanceProvider>(
          builder: (context, reportProvider, studentProvider, attendanceProvider, child) {
            return TabBarView(
              children: [
                // Daily tab
                ListView(
                  padding: const EdgeInsets.only(bottom: 80),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Daily Attendance Report Settings',
                                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Expanded(
                                    child: DropdownButtonFormField<int>(
                                      isExpanded: true,
                                      decoration: const InputDecoration(
                                        labelText: 'Semester',
                                        border: OutlineInputBorder(),
                                      ),
                                      initialValue: _selectedSemester,
                                      items: dbHelper.getSemesters().map((sem) => DropdownMenuItem(
                                        value: sem,
                                        child: Text('Sem $sem', overflow: TextOverflow.ellipsis),
                                      )).toList(),
                                      onChanged: (value) {
                                        if (value != null) {
                                          setState(() => _selectedSemester = value);
                                        }
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: DropdownButtonFormField<String>(
                                      isExpanded: true,
                                      decoration: const InputDecoration(
                                        labelText: 'Class Type',
                                        border: OutlineInputBorder(),
                                      ),
                                      initialValue: _selectedClassType,
                                      items: dbHelper.getCombinedDepartments().map((dept) => DropdownMenuItem(
                                        value: dept,
                                        child: Text(dept, overflow: TextOverflow.ellipsis),
                                      )).toList(),
                                      onChanged: (value) {
                                        if (value != null) {
                                          setState(() => _selectedClassType = value);
                                        }
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: DropdownButtonFormField<String>(
                                      isExpanded: true,
                                      decoration: const InputDecoration(
                                        labelText: 'Division',
                                        border: OutlineInputBorder(),
                                      ),
                                      initialValue: _selectedDivision,
                                      items: dbHelper.getDivisions().map((div) => DropdownMenuItem(
                                        value: div,
                                        child: Text('Div $div', overflow: TextOverflow.ellipsis),
                                      )).toList(),
                                      onChanged: (value) {
                                        if (value != null) {
                                          setState(() => _selectedDivision = value);
                                        }
                                      },
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              TextFormField(
                                decoration: const InputDecoration(
                                  labelText: 'Report Date',
                                  border: OutlineInputBorder(),
                                  suffixIcon: Icon(Icons.calendar_today),
                                ),
                                readOnly: true,
                                controller: TextEditingController(
                                  text: _selectedReportDate.toIso8601String().substring(0, 10),
                                ),
                                onTap: () async {
                                  final date = await showDatePicker(
                                    context: context,
                                    initialDate: _selectedReportDate,
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime.now(),
                                    useRootNavigator: true,
                                  );
                                  if (date != null) {
                                    setState(() => _selectedReportDate = date);
                                  }
                                },
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Expanded(
                                    child: ElevatedButton(
                                      onPressed: _showDailyReportOptions,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Theme.of(context).colorScheme.primary,
                                        foregroundColor: Theme.of(context).colorScheme.onPrimary,
                                        padding: const EdgeInsets.symmetric(vertical: 12),
                                        alignment: Alignment.center,
                                      ),
                                      child: const Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.share, size: 20),
                                          SizedBox(width: 8),
                                          Flexible(
                                            child: Text(
                                              'Generate Daily Report',
                                              textAlign: TextAlign.center,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: ElevatedButton(
                                      onPressed: _shareFormattedAbsenteeReport,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Theme.of(context).colorScheme.tertiaryContainer,
                                        foregroundColor: Theme.of(context).colorScheme.onTertiaryContainer,
                                        padding: const EdgeInsets.symmetric(vertical: 12),
                                        alignment: Alignment.center,
                                      ),
                                      child: const Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.warning, size: 20),
                                          SizedBox(width: 8),
                                          Flexible(
                                            child: Text(
                                              'Quick Absentee Report',
                                              textAlign: TextAlign.center,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              // Trend filters: Department and Semester (moved here to Daily tab)
                              Row(
                                children: [
                                  Expanded(
                                    child: DropdownButtonFormField<String>(
                                      isExpanded: true,
                                      decoration: const InputDecoration(
                                        labelText: 'Trend Department',
                                        border: OutlineInputBorder(),
                                      ),
                                      initialValue: _trendDepartment,
                                      items: ['All', ...dbHelper.getIndividualDepartments()].map((dept) => DropdownMenuItem(
                                        value: dept,
                                        child: Text(dept, overflow: TextOverflow.ellipsis),
                                      )).toList(),
                                      onChanged: (v) => setState(() => _trendDepartment = v ?? 'All'),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: DropdownButtonFormField<int>(
                                      isExpanded: true,
                                      decoration: const InputDecoration(
                                        labelText: 'Trend Semester',
                                        border: OutlineInputBorder(),
                                      ),
                                      initialValue: _trendSemester,
                                      items: [0, ...dbHelper.getSemesters()].map((sem) => DropdownMenuItem(
                                        value: sem,
                                        child: Text(sem == 0 ? 'All Semesters' : 'Sem $sem', overflow: TextOverflow.ellipsis),
                                      )).toList(),
                                      onChanged: (v) => setState(() => _trendSemester = v ?? 0),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: ElevatedButton(
                                      onPressed: () async {
                                        final rp = Provider.of<ReportProvider>(context, listen: false);
                                        final dateStr = _selectedReportDate.toIso8601String().substring(0, 10);
                                        final data = await rp.getDailyLectureAttendance(
                                          date: dateStr,
                                          semester: _trendSemester == 0 ? null : _trendSemester,
                                          department: _trendDepartment == 'All' ? null : _trendDepartment,
                                        );
                                        setState(() => _trendData = data);
                                      },
                                      child: const Text('Show Daily Attendance Trend'),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              // Trend chart area
                              if (_trendData.isNotEmpty) Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(12.0),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Daily Attendance Trend for ${_selectedReportDate.toIso8601String().substring(0,10)}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                      const SizedBox(height: 12),
                                      SizedBox(
                                        height: chartHeight,
                                        child: LayoutBuilder(
                                          builder: (context, constraints) {
                                            final maxBarHeight = constraints.maxHeight - 40; // leave space for labels
                                            return Row(
                                              crossAxisAlignment: CrossAxisAlignment.end,
                                              children: _trendData.map((entry) {
                                                final pct = (entry['percentage'] as num).toDouble().clamp(0.0, 100.0);
                                                final barHeight = (pct / 100.0) * maxBarHeight;
                                                return Expanded(
                                                  child: Padding(
                                                    padding: const EdgeInsets.symmetric(horizontal: 6.0),
                                                    child: Column(
                                                      mainAxisAlignment: MainAxisAlignment.end,
                                                      children: [
                                                        Container(
                                                          height: barHeight,
                                                          decoration: BoxDecoration(
                                                            color: Theme.of(context).colorScheme.primary,
                                                            borderRadius: BorderRadius.circular(6),
                                                          ),
                                                        ),
                                                        const SizedBox(height: 8),
                                                        SizedBox(
                                                          height: 36,
                                                          child: Text(
                                                            _shortLectureLabel(entry),
                                                            style: const TextStyle(fontSize: 10),
                                                            textAlign: TextAlign.center,
                                                            maxLines: 2,
                                                            overflow: TextOverflow.ellipsis,
                                                          ),
                                                        ),
                                                        const SizedBox(height: 4),
                                                        Text('${(pct).toStringAsFixed(1)}%', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                                      ],
                                                    ),
                                                  ),
                                                );
                                              }).toList(),
                                            );
                                          },
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Row(children: [Text('Total strength: ${_trendData.fold<int>(0, (p, e) => p + (e['strength'] as int))}'), const SizedBox(width: 12), Text('Date: ${_selectedReportDate.toIso8601String().substring(0,10)}')]),
                                    ],
                                  ),
                                ),
                              ) else Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text('No trend data. Select date/filters and press Show Daily Attendance Trend', style: TextStyle(color: Theme.of(context).colorScheme.outline))),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                // Overall tab
                ListView(
                  padding: const EdgeInsets.only(bottom: 80),
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Overall Attendance Reports',
                                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextFormField(
                                      decoration: const InputDecoration(
                                        labelText: 'From Date',
                                        border: OutlineInputBorder(),
                                        suffixIcon: Icon(Icons.calendar_today),
                                      ),
                                      readOnly: true,
                                      controller: TextEditingController(
                                        text: _fromDate.toIso8601String().substring(0, 10),
                                      ),
                                      onTap: () async {
                                        final date = await showDatePicker(
                                          context: context,
                                          initialDate: _fromDate,
                                          firstDate: DateTime(2020),
                                          lastDate: DateTime.now(),
                                          useRootNavigator: true,
                                        );
                                        if (date != null) {
                                          setState(() => _fromDate = date);
                                          _loadReports();
                                        }
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: TextFormField(
                                      decoration: const InputDecoration(
                                        labelText: 'To Date',
                                        border: OutlineInputBorder(),
                                        suffixIcon: Icon(Icons.calendar_today),
                                      ),
                                      readOnly: true,
                                      controller: TextEditingController(
                                        text: _toDate.toIso8601String().substring(0, 10),
                                      ),
                                      onTap: () async {
                                        final date = await showDatePicker(
                                          context: context,
                                          initialDate: _toDate,
                                          firstDate: _fromDate,
                                          lastDate: DateTime.now(),
                                          useRootNavigator: true,
                                        );
                                        if (date != null) {
                                          setState(() => _toDate = date);
                                          _loadReports();
                                        }
                                      },
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      onPressed: _shareReport,
                                      icon: const Icon(Icons.file_download),
                                      label: const Text('Share CSV Report'),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      onPressed: _shareTextReport,
                                      icon: const Icon(Icons.share),
                                      label: const Text('Share Text Report'),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                            ],
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Report Content (student list)
                    if (studentProvider.students.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24.0),
                        child: Center(
                          child: Text(
                            'No students found. Please add students first.',
                            style: TextStyle(fontSize: 16, color: Theme.of(context).colorScheme.onSurface),
                          ),
                        ),
                      )
                    else
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: studentProvider.students.length,
                        itemBuilder: (context, index) {
                          final student = studentProvider.students[index];
                          final attendanceData = reportProvider.getStudentAttendanceData(student.id);

                          return Card(
                            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              leading: CircleAvatar(
                                radius: 20,
                                backgroundColor: attendanceData['percentage'] >= 75
                                    ? Theme.of(context).colorScheme.primary
                                    : attendanceData['percentage'] >= 50
                                        ? Theme.of(context).colorScheme.tertiary
                                        : Theme.of(context).colorScheme.error,
                                child: Text(
                                  '${attendanceData['percentage'].toInt()}%',
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.onPrimary,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                              title: Text(
                                student.name,
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                                style: const TextStyle(fontSize: 14),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'Roll No: ${student.rollNumber}',
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  Text(
                                    'Sem ${student.semester} • ${student.department} • Div ${student.division}',
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  Text(
                                    'Present: ${attendanceData['present']}/${attendanceData['total']}',
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ],
                              ),
                              trailing: SizedBox(
                                width: 32,
                                height: 32,
                                child: IconButton(
                                  padding: EdgeInsets.zero,
                                  iconSize: 18,
                                  icon: const Icon(Icons.share),
                                  onPressed: () async {
                                    final text = '''
Student: ${student.name}
Roll No: ${student.rollNumber}
Semester: ${student.semester}
Department: ${student.department}
Division: ${student.division}
Total Classes: ${attendanceData['total']}
Present: ${attendanceData['present']}
Absent: ${attendanceData['absent']}
Attendance Percentage: ${attendanceData['percentage'].toStringAsFixed(1)}%
                                    ''';
                                    // ignore: deprecated_member_use
                                    await Share.share(text);
                                  },
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ],
            );
          },
        ),
        // No persistent FAB here; navigation provided in AppBar.
      ),
    );
  }
}
