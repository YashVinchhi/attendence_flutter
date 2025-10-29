import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
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

      await Share.share(
        formattedReport,
        subject: 'Daily Absentee Report - $_selectedSemester$_selectedClassType-$_selectedDivision',
      );
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

      await Share.share(
        formattedReport,
        subject: '$reportTitle - $_selectedSemester$_selectedClassType-$_selectedDivision',
      );
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

      // Share the file
      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Attendance Report from ${_fromDate.toIso8601String().substring(0, 10)} to ${_toDate.toIso8601String().substring(0, 10)}',
        subject: 'Attendance Report',
      );
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

      await Share.share(
        reportText.toString(),
        subject: 'Attendance Report',
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error sharing report: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final dbHelper = DatabaseHelper.instance;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Attendance Reports'),
        leading: IconButton(
          icon: const Icon(Icons.home),
          onPressed: () => context.go('/home'),
          tooltip: 'Back to Home',
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.share),
            tooltip: 'Share Report',
            onSelected: (value) {
              if (value == 'absentee') {
                _shareFormattedAbsenteeReport();
              } else if (value == 'csv') {
                _shareReport();
              } else if (value == 'text') {
                _shareTextReport();
              } else if (value == 'daily_options') {
                _showDailyReportOptions();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'daily_options',
                child: ListTile(
                  leading: Icon(Icons.today),
                  title: Text('Daily Report Options'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'absentee',
                child: ListTile(
                  leading: Icon(Icons.report_problem),
                  title: Text('Daily Absentee Report'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'csv',
                child: ListTile(
                  leading: Icon(Icons.table_chart),
                  title: Text('Share as CSV'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'text',
                child: ListTile(
                  leading: Icon(Icons.text_fields),
                  title: Text('Share as Text'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: Consumer3<ReportProvider, StudentProvider, AttendanceProvider>(
        builder: (context, reportProvider, studentProvider, attendanceProvider, child) {
          return Column(
            children: [
              // Class Selection for Daily Reports
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
                                  backgroundColor: Colors.blue,
                                  foregroundColor: Colors.white,
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
                                        'Choose Daily Report Type',
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
                                  backgroundColor: Colors.orange,
                                  foregroundColor: Colors.white,
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
                      ],
                    ),
                  ),
                ),
              ),

              // Date Range Selection for Overall Reports
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
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Report Content
              Expanded(
                child: studentProvider.students.isEmpty
                    ? const Center(
                        child: Text(
                          'No students found. Please add students first.',
                          style: TextStyle(fontSize: 16),
                        ),
                      )
                    : ListView.builder(
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
                                    ? Colors.green
                                    : attendanceData['percentage'] >= 50
                                        ? Colors.orange
                                        : Colors.red,
                                child: Text(
                                  '${attendanceData['percentage'].toInt()}%',
                                  style: const TextStyle(
                                    color: Colors.white,
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
                                    await Share.share(text);
                                  },
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go('/home'),
        label: const Text('Back to Main Menu'),
        icon: const Icon(Icons.home),
      ),
    );
  }
}
