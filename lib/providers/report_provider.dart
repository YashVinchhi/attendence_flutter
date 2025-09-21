import 'package:flutter/material.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/models.dart';
import '../services/database_helper.dart';

enum ReportProviderState { idle, loading, error, generating }

class ReportProvider with ChangeNotifier {
  final Map<int, Map<String, dynamic>> _studentAttendanceData = {};
  ReportProviderState _state = ReportProviderState.idle;
  String? _errorMessage;
  String _fromDate = '';
  String _toDate = '';
  bool _disposed = false;

  Map<int, Map<String, dynamic>> get studentAttendanceData => _studentAttendanceData;
  ReportProviderState get state => _state;
  bool get isLoading => _state == ReportProviderState.loading;
  bool get isGenerating => _state == ReportProviderState.generating;
  bool get hasError => _state == ReportProviderState.error;
  String? get errorMessage => _errorMessage;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _safeNotifyListeners() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  void _setState(ReportProviderState newState, {String? error}) {
    _state = newState;
    _errorMessage = error;
    _safeNotifyListeners();
  }

  // Validate date ranges
  bool _isValidDateRange(String? fromDate, String? toDate) {
    if (fromDate == null || toDate == null) return false;

    try {
      final from = DateTime.parse(fromDate);
      final to = DateTime.parse(toDate);
      final now = DateTime.now();

      // Don't allow future dates
      if (from.isAfter(now) || to.isAfter(now)) return false;

      // From date should not be after to date
      return !from.isAfter(to);
    } catch (e) {
      return false;
    }
  }

  Future<void> generateAttendanceReport(String fromDate, String toDate) async {
    if (_state == ReportProviderState.loading) return;

    // Validate date range
    if (!_isValidDateRange(fromDate, toDate)) {
      _setState(ReportProviderState.error, error: 'Invalid date range or future dates not allowed');
      return;
    }

    _setState(ReportProviderState.loading);
    _fromDate = fromDate;
    _toDate = toDate;

    try {
      final students = await DatabaseHelper.instance.getAllStudents();
      _studentAttendanceData.clear();

      for (var student in students) {
        final stats = await DatabaseHelper.instance.getStudentAttendanceStats(
          student.id!,
          fromDate,
          toDate,
        );
        _studentAttendanceData[student.id!] = stats;
      }

      _setState(ReportProviderState.idle);
    } catch (e) {
      print('Error generating attendance report: $e');
      _setState(ReportProviderState.error, error: 'Failed to generate report: ${e.toString()}');
    }
  }

  Map<String, dynamic> getStudentAttendanceData(int? studentId) {
    if (studentId == null) {
      return {
        'total': 0,
        'present': 0,
        'absent': 0,
        'percentage': 0.0,
      };
    }

    return _studentAttendanceData[studentId] ?? {
      'total': 0,
      'present': 0,
      'absent': 0,
      'percentage': 0.0,
    };
  }

  Future<Map<String, dynamic>> getOverallStats() async {
    try {
      if (_fromDate.isEmpty || _toDate.isEmpty) {
        return {
          'totalStudents': 0,
          'averageAttendance': 0.0,
          'totalClasses': 0,
        };
      }

      final students = await DatabaseHelper.instance.getAllStudents();
      if (students.isEmpty) {
        return {
          'totalStudents': 0,
          'averageAttendance': 0.0,
          'totalClasses': 0,
        };
      }

      double totalPercentage = 0;
      int totalClasses = 0;

      for (var student in students) {
        final data = getStudentAttendanceData(student.id);
        totalPercentage += data['percentage'];
        totalClasses += data['total'] as int;
      }

      return {
        'totalStudents': students.length,
        'averageAttendance': students.isNotEmpty ? totalPercentage / students.length : 0.0,
        'totalClasses': totalClasses,
      };
    } catch (e) {
      print('Error getting overall stats: $e');
      return {
        'totalStudents': 0,
        'averageAttendance': 0.0,
        'totalClasses': 0,
      };
    }
  }

  // Enhanced CSV export with proper error handling
  Future<bool> exportToCSV({
    int? semester,
    String? department,
    String? division,
  }) async {
    if (_fromDate.isEmpty || _toDate.isEmpty) {
      _setState(ReportProviderState.error, error: 'No report data available. Generate a report first.');
      return false;
    }

    _setState(ReportProviderState.generating);

    try {
      // Get filtered students
      List<Student> students;
      if (semester != null && department != null && division != null) {
        students = await DatabaseHelper.instance.getStudentsByClass(semester, department, division);
      } else {
        students = await DatabaseHelper.instance.getAllStudents();
      }

      if (students.isEmpty) {
        _setState(ReportProviderState.error, error: 'No students found for the selected criteria');
        return false;
      }

      // Generate CSV content
      StringBuffer csvContent = StringBuffer();

      // CSV Header
      csvContent.writeln('Name,Roll Number,Semester,Department,Division,Total Classes,Present,Absent,Attendance %');

      // CSV Data
      for (var student in students) {
        final stats = getStudentAttendanceData(student.id);
        csvContent.writeln(
          '"${student.name}","${student.rollNumber}",${student.semester},"${student.department}","${student.division}",${stats['total']},${stats['present']},${stats['absent']},${stats['percentage'].toStringAsFixed(2)}'
        );
      }

      // Add summary at the end
      final overallStats = await getOverallStats();
      csvContent.writeln('');
      csvContent.writeln('SUMMARY');
      csvContent.writeln('Total Students,${overallStats['totalStudents']}');
      csvContent.writeln('Average Attendance,${overallStats['averageAttendance'].toStringAsFixed(2)}%');
      csvContent.writeln('Report Period,"$_fromDate to $_toDate"');
      csvContent.writeln('Generated On,"${DateTime.now().toIso8601String().substring(0, 10)}"');

      // Save file
      final fileName = 'attendance_report_${_fromDate}_to_$_toDate.csv';
      final success = await _saveAndShareFile(csvContent.toString(), fileName);

      if (success) {
        _setState(ReportProviderState.idle);
        return true;
      } else {
        return false;
      }
    } catch (e) {
      print('Error exporting CSV: $e');
      _setState(ReportProviderState.error, error: 'Failed to export CSV: ${e.toString()}');
      return false;
    }
  }

  Future<bool> _saveAndShareFile(String content, String fileName) async {
    try {
      Directory? directory;

      if (Platform.isAndroid) {
        directory = await getExternalStorageDirectory();
      } else if (Platform.isIOS) {
        directory = await getApplicationDocumentsDirectory();
      } else {
        directory = await getDownloadsDirectory();
      }

      if (directory == null) {
        _setState(ReportProviderState.error, error: 'Could not access storage directory');
        return false;
      }

      final file = File('${directory.path}/$fileName');
      await file.writeAsString(content);

      // Share the file
      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Attendance Report - $_fromDate to $_toDate',
        subject: 'Attendance Report',
      );

      return true;
    } catch (e) {
      print('Error saving/sharing file: $e');
      _setState(ReportProviderState.error, error: 'Failed to save or share file: ${e.toString()}');
      return false;
    }
  }

  // Generate detailed class-wise report
  Future<String> generateClassWiseReport(int semester, String department, String division) async {
    try {
      if (!_isValidDateRange(_fromDate, _toDate)) {
        throw ArgumentError('Invalid date range for report generation');
      }

      final students = await DatabaseHelper.instance.getStudentsByClass(semester, department, division);

      if (students.isEmpty) {
        return 'No students found for $semester$department-$division';
      }

      StringBuffer report = StringBuffer();
      report.writeln('ATTENDANCE REPORT - CLASS WISE');
      report.writeln('=' * 50);
      report.writeln('Class: $semester$department-$division');
      report.writeln('Period: $_fromDate to $_toDate');
      report.writeln('Generated on: ${DateTime.now().toIso8601String().substring(0, 10)}');
      report.writeln('');

      // Individual student data
      report.writeln('INDIVIDUAL ATTENDANCE:');
      report.writeln('-' * 50);

      int totalPresent = 0, totalAbsent = 0, totalClasses = 0;

      for (var student in students) {
        final stats = getStudentAttendanceData(student.id);
        final present = stats['present'] as int;
        final absent = stats['absent'] as int;
        final total = stats['total'] as int;
        final percentage = stats['percentage'] as double;

        report.writeln('${student.name} (${student.rollNumber})');
        report.writeln('  Present: $present, Absent: $absent, Total: $total');
        report.writeln('  Attendance: ${percentage.toStringAsFixed(1)}%');
        report.writeln('');

        totalPresent += present;
        totalAbsent += absent;
        totalClasses += total;
      }

      // Class summary
      report.writeln('CLASS SUMMARY:');
      report.writeln('-' * 50);
      report.writeln('Total Students: ${students.length}');
      report.writeln('Total Classes Conducted: ${totalClasses ~/ students.length}');
      report.writeln('Average Attendance: ${students.isNotEmpty ? (totalPresent / (totalPresent + totalAbsent) * 100).toStringAsFixed(1) : 0}%');

      return report.toString();
    } catch (e) {
      throw Exception('Error generating class-wise report: $e');
    }
  }

  void clearError() {
    if (_state == ReportProviderState.error) {
      _setState(ReportProviderState.idle);
    }
  }

  // Get attendance trend data for charts
  Future<List<Map<String, dynamic>>> getAttendanceTrend() async {
    try {
      if (_fromDate.isEmpty || _toDate.isEmpty) return [];

      final db = await DatabaseHelper.instance.database;
      final result = await db.rawQuery('''
        SELECT 
          date,
          COUNT(*) as total_records,
          SUM(CASE WHEN is_present = 1 THEN 1 ELSE 0 END) as present_count,
          SUM(CASE WHEN is_present = 0 THEN 1 ELSE 0 END) as absent_count
        FROM attendance 
        WHERE date >= ? AND date <= ?
        GROUP BY date
        ORDER BY date
      ''', [_fromDate, _toDate]);

      return result.map((row) {
        final total = row['total_records'] as int;
        final present = row['present_count'] as int;
        return {
          'date': row['date'],
          'total': total,
          'present': present,
          'absent': row['absent_count'],
          'percentage': total > 0 ? (present / total * 100) : 0.0,
        };
      }).toList();
    } catch (e) {
      print('Error getting attendance trend: $e');
      return [];
    }
  }
}
