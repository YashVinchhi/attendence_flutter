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

      // Try sensible directory choices with fallbacks
      try {
        if (Platform.isAndroid) {
          directory = await getExternalStorageDirectory();
        } else if (Platform.isIOS) {
          directory = await getApplicationDocumentsDirectory();
        } else {
          // On desktop or other platforms prefer downloads, else documents
          directory = await getDownloadsDirectory();
          if (directory == null) directory = await getApplicationDocumentsDirectory();
        }
      } catch (e) {
        // Accessing platform dirs can fail; fallback to application documents
        try {
          directory = await getApplicationDocumentsDirectory();
        } catch (_) {
          directory = null;
        }
      }

      if (directory == null) {
        _setState(ReportProviderState.error, error: 'Could not access storage directory');
        return false;
      }

      final file = File('${directory.path}/$fileName');

      try {
        await file.writeAsString(content);
      } catch (e) {
        // If writing to external storage fails (permissions), try application documents
        try {
          final altDir = await getApplicationDocumentsDirectory();
          final altFile = File('${altDir.path}/$fileName');
          await altFile.writeAsString(content);
          // Replace file reference with altFile for sharing below
          // ignore: prefer_final_locals
          directory = altDir;
        } catch (writeErr) {
          _setState(ReportProviderState.error, error: 'Failed to save file: ${writeErr.toString()}');
          return false;
        }
      }

      // Attempt to share the file. If file sharing fails, fallback to sharing raw text.
      try {
        // ignore: deprecated_member_use
        await Share.shareXFiles(
          [XFile(file.path)],
          text: 'Attendance Report - $_fromDate to $_toDate',
          subject: 'Attendance Report',
        );
      } catch (shareErr) {
        // Fallback: share as plain text (CSV content) if file share isn't supported
        try {
          // ignore: deprecated_member_use
          await Share.share(content, subject: 'Attendance Report - $_fromDate to $_toDate');
        } catch (textShareErr) {
          _setState(ReportProviderState.error, error: 'Failed to share file: ${textShareErr.toString()}');
          return false;
        }
      }

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
      final totalAttendanceCount = totalPresent + totalAbsent;
      final avgAttendance = (students.isNotEmpty && totalAttendanceCount > 0)
          ? (totalPresent / totalAttendanceCount * 100)
          : 0.0;
      report.writeln('Average Attendance: ${avgAttendance.toStringAsFixed(1)}%');

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
        final total = (row['total_records'] is int) ? row['total_records'] as int : int.tryParse('${row['total_records']}') ?? 0;
        final present = (row['present_count'] is int) ? row['present_count'] as int : int.tryParse('${row['present_count']}') ?? 0;
        // absent count not used here
        return {
          'date': row['date'],
          'total': total,
          'present': present,
          'percentage': total > 0 ? (present / total * 100) : 0.0,
        };
      }).toList();
    } catch (e) {
      print('Error getting attendance trend: $e');
      return [];
    }
  }

  /// Compute per-lecture overall attendance percentage for a given single date.
  /// [date] should be in 'YYYY-MM-DD' format.
  /// [semester] can be null or 0 to represent all semesters.
  /// [department] can be null or 'All' to represent all departments.
  Future<List<Map<String, dynamic>>> getDailyLectureAttendance({
    required String date,
    int? semester,
    String? department,
  }) async {
    try {
      // Lectures and their time slots (match UI ordering)
      final slots = [
        {'label': 'Lec 1 (8:00-8:50)', 'lecture': 1, 'timeslot': '8:00-8:50'},
        {'label': 'Lec 2 (8:50-9:45)', 'lecture': 2, 'timeslot': '8:50-9:45'},
        {'label': 'Lec 3 (10:00-10:50)', 'lecture': 3, 'timeslot': '10:00-10:50'},
        {'label': 'Lec 4 (10:50-11:40)', 'lecture': 4, 'timeslot': '10:50-11:40'},
        {'label': 'Lec 5 (12:30-1:20)', 'lecture': 5, 'timeslot': '12:30-1:20'},
        {'label': 'Lec 6 (1:20-2:10)', 'lecture': 6, 'timeslot': '1:20-2:10'},
      ];

      // Determine which classes to include based on filters
      List<Map<String, dynamic>> classCombs = await DatabaseHelper.instance.getClassCombinations();
      // Filter classes according to semester and department
      if (semester != null && semester > 0) {
        classCombs = classCombs.where((c) => (c['semester'] as int) == semester).toList();
      }
      if (department != null && department.isNotEmpty && department.toLowerCase() != 'all') {
        // department can be 'CE/IT', 'CE', 'IT'
        classCombs = classCombs.where((c) {
          final dept = (c['department'] as String);
          if (department == 'CE/IT') return dept == 'CE' || dept == 'IT';
          return dept == department;
        }).toList();
      }

      // If no matching classes found, return zeros per slot
      if (classCombs.isEmpty) {
        return slots.map((s) => {'label': s['label'], 'percentage': 0.0, 'present': 0, 'strength': 0}).toList();
      }

      // For each class combination, get strength (number of students)
      int totalStrength = 0;
      final classKeys = <String>[]; // e.g., '3|CE|A'
      for (final c in classCombs) {
        final sem = c['semester'] as int;
        final dept = c['department'] as String;
        final div = c['division'] as String;
        final students = await DatabaseHelper.instance.getStudentsByClass(sem, dept, div);
        final strength = students.length;
        totalStrength += strength;
        classKeys.add('$sem|$dept|$div|$strength');
      }

      // If total strength is zero, return zeros
      if (totalStrength == 0) {
        return slots.map((s) => {'label': s['label'], 'percentage': 0.0, 'present': 0, 'strength': 0}).toList();
      }

      // For each lecture slot, count present students across all classes
      final List<Map<String, dynamic>> results = [];
      for (final slot in slots) {
        int presentSum = 0;
        int strengthSum = 0;
        // For each class, fetch attendance records for the given date, lecture string
        for (final ck in classKeys) {
          final parts = ck.split('|');
          final sem = int.parse(parts[0]);
          final dept = parts[1];
          final div = parts[2];
          final strength = int.parse(parts[3]);
          strengthSum += strength;

          // Use DatabaseHelper method to get attendance by date/lecture filtering by class
          // Re-fetch students for this class to get their IDs
          final classStudents = await DatabaseHelper.instance.getStudentsByClass(sem, dept, div);
          if (classStudents.isEmpty) continue;
          final ids = classStudents.map((s) => s.id!).toList();
          final presentCount = await DatabaseHelper.instance.countPresentByStudentIdsAndDateAndLecture(ids, date, '${slot['lecture']}');
          presentSum += presentCount;
        }

        final percentage = strengthSum > 0 ? (presentSum / strengthSum * 100) : 0.0;
        results.add({'label': slot['label'], 'percentage': percentage, 'present': presentSum, 'strength': strengthSum});
      }

      return results;
    } catch (e) {
      print('Error computing daily lecture attendance: $e');
      return [];
    }
  }
}

