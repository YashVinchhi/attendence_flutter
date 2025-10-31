import 'package:flutter/foundation.dart';
import '../models/models.dart';
import '../services/database_helper.dart';

enum AttendanceProviderState { idle, loading, error }

class AttendanceProvider with ChangeNotifier {
  // Mutable list (was final but reassigned in fetch methods previously -> error)
  List<AttendanceRecord> _attendanceRecords = [];
  AttendanceProviderState _state = AttendanceProviderState.idle;
  String? _errorMessage;
  bool _disposed = false;

  List<AttendanceRecord> get attendanceRecords => List.unmodifiable(_attendanceRecords);
  AttendanceProviderState get state => _state;
  bool get isLoading => _state == AttendanceProviderState.loading;
  bool get hasError => _state == AttendanceProviderState.error;
  String? get errorMessage => _errorMessage;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _safeNotifyListeners() {
    if (!_disposed) notifyListeners();
  }

  void _setState(AttendanceProviderState newState, {String? error}) {
    _state = newState;
    _errorMessage = error;
    _safeNotifyListeners();
  }

  String _formatDate(DateTime d) => d.toIso8601String().substring(0, 10);

  bool _isValidDateRange(String fromDate, String toDate) {
    try {
      final from = DateTime.parse(fromDate);
      final to = DateTime.parse(toDate);
      final now = DateTime.now();
      if (from.isAfter(now) || to.isAfter(now)) return false; // future dates not allowed
      return !from.isAfter(to);
    } catch (_) {
      return false;
    }
  }

  Future<void> syncAttendanceFromFirestore() async {
    try {
      _setState(AttendanceProviderState.loading);
      await DatabaseHelper.instance.syncAttendanceFromFirestore();
      _setState(AttendanceProviderState.idle);
    } catch (e) {
      if (kDebugMode) print('Error syncing attendance from Firestore: $e');
      _setState(AttendanceProviderState.error, error: 'Failed to sync attendance from Firestore');
    }
  }

  Future<void> fetchAttendanceByDate(String date) async {
    if (_state == AttendanceProviderState.loading) return;
    try { DateTime.parse(date); } catch (_) { _setState(AttendanceProviderState.error, error: 'Invalid date format'); return; }

    _setState(AttendanceProviderState.loading);
    try {
      await syncAttendanceFromFirestore(); // Ensure Firestore data is synced
      _attendanceRecords = await DatabaseHelper.instance.getAttendanceByDate(date);
      _setState(AttendanceProviderState.idle);
    } catch (e) {
      if (kDebugMode) print('Error fetching attendance: $e');
      _setState(AttendanceProviderState.error, error: 'Failed to load attendance records');
    }
  }

  Future<void> fetchAttendanceByDateAndLecture(String date, String? lecture, {String? timeSlot}) async {
    if (_state == AttendanceProviderState.loading) return;
    try { DateTime.parse(date); } catch (_) { _setState(AttendanceProviderState.error, error: 'Invalid date format'); return; }

    _setState(AttendanceProviderState.loading);
    try {
      await syncAttendanceFromFirestore(); // Ensure Firestore data is synced
      _attendanceRecords = await DatabaseHelper.instance.getAttendanceByDateAndLecture(date, lecture, timeSlot: timeSlot);
      _setState(AttendanceProviderState.idle);
    } catch (e) {
      if (kDebugMode) print('Error fetching attendance: $e');
      _setState(AttendanceProviderState.error, error: 'Failed to load attendance records');
    }
  }

  Future<bool> markAttendance(int studentId, String date, bool isPresent, {String? notes, String? lecture, String? timeSlot}) async {
    try {
      final parsedDate = DateTime.parse(date);
      final formattedDate = _formatDate(parsedDate);
      if (parsedDate.isAfter(DateTime.now())) {
        _setState(AttendanceProviderState.error, error: 'Cannot mark future date');
        return false;
      }

      final existing = await DatabaseHelper.instance.getAttendanceRecordWithLecture(studentId, formattedDate, lecture, timeSlot: timeSlot);

      if (existing != null) {
        final updated = existing.copyWith(
          isPresent: isPresent,
          notes: notes ?? existing.notes,
          lecture: lecture ?? existing.lecture,
          timeSlot: timeSlot ?? existing.timeSlot,
          date: parsedDate,
        );
        await DatabaseHelper.instance.updateAttendance(updated);
        final idx = _attendanceRecords.indexWhere((r) => r.id == existing.id);
        if (idx != -1) _attendanceRecords[idx] = updated; else {
          // fallback if list not containing due to different fetch context
          _attendanceRecords.add(updated);
        }
      } else {
        final newRecord = AttendanceRecord(
          studentId: studentId,
          date: parsedDate,
          isPresent: isPresent,
          notes: notes,
          lecture: lecture,
          timeSlot: timeSlot,
        );
        final id = await DatabaseHelper.instance.insertAttendance(newRecord);
        _attendanceRecords.add(newRecord.copyWith(id: id));
      }

      _safeNotifyListeners();
      return true;
    } catch (e) {
      if (kDebugMode) print('Error marking attendance: $e');
      _setState(AttendanceProviderState.error, error: 'Failed to mark attendance');
      return false;
    }
  }

  Future<bool> _bulkMarkAttendance(List<int> studentIds, String date, bool isPresent, {String? lecture, String? timeSlot}) async {
    try {
      final results = await Future.wait(studentIds.map((id) => markAttendance(id, date, isPresent, lecture: lecture, timeSlot: timeSlot)));
      // If any individual mark failed (returned false), treat bulk as failed
      if (results.any((r) => r == false)) {
        _setState(AttendanceProviderState.error, error: 'One or more attendance updates failed');
        return false;
      }
      return true;
    } catch (e) {
      if (kDebugMode) print('Bulk mark error: $e');
      _setState(AttendanceProviderState.error, error: 'Bulk operation failed');
      return false;
    }
  }

  Future<bool> markAllPresent(List<int> studentIds, String date, {String? lecture, String? timeSlot}) => _bulkMarkAttendance(studentIds, date, true, lecture: lecture, timeSlot: timeSlot);
  Future<bool> markAllAbsent(List<int> studentIds, String date, {String? lecture, String? timeSlot}) => _bulkMarkAttendance(studentIds, date, false, lecture: lecture, timeSlot: timeSlot);

  bool isStudentPresent(int studentId, String date, {String? lecture, String? timeSlot}) {
    try {
      final record = _attendanceRecords.firstWhere(
        (r) => r.studentId == studentId
            && _formatDate(r.date) == date
            && (lecture == null || (r.lecture ?? '') == lecture)
            && (timeSlot == null || (r.timeSlot ?? '') == timeSlot),
      );
      return record.isPresent;
    } catch (_) {
      // No record found => treat as absent by default
      return false;
    }
  }

  // Helper: whether we have any attendance record for student+date+lecture
  bool hasAttendanceRecord(int studentId, String date, {String? lecture, String? timeSlot}) {
    return _attendanceRecords.any((r) => r.studentId == studentId
        && _formatDate(r.date) == date
        && (lecture == null || (r.lecture ?? '') == lecture)
        && (timeSlot == null || (r.timeSlot ?? '') == timeSlot));
  }

  Future<String> generateFormattedAbsenteeReport(String date, int semester, String department, String division) async {
    try {
      await fetchAttendanceByDate(date); // refresh
      final allStudents = await DatabaseHelper.instance.getStudentsByCombinedClassOrdered(semester, department, division);
      // Prepare header pieces in requested format
      final classDisplay = '${semester}${department}-${division}';
      late final String headerLine;
      try {
        final dt = DateTime.parse(date);
        const days = ['MONDAY','TUESDAY','WEDNESDAY','THURSDAY','FRIDAY','SATURDAY','SUNDAY'];
        final dd = dt.day.toString().padLeft(2, '0');
        final mm = dt.month.toString().padLeft(2, '0');
        final yyyy = dt.year.toString();
        final dow = days[dt.weekday - 1];
        headerLine = '$classDisplay,$dd/$mm/$yyyy, $dow';
      } catch (_) {
        // Fallback to raw date if parsing fails
        headerLine = '$classDisplay,$date';
      }

      if (allStudents.isEmpty) {
        return headerLine + '\nNo students found.';
      }

      final studentMap = {for (var s in allStudents) s.id!: s};
      final idSet = studentMap.keys.toSet();

      // Collect absent attendance rows for that class/date
      final absentRecords = _attendanceRecords.where((r) => _formatDate(r.date) == date && !r.isPresent && idSet.contains(r.studentId)).toList();

      final sb = StringBuffer();
      sb.writeln(headerLine);
      sb.writeln('');

      if (absentRecords.isEmpty) {
        sb.writeln('All students present');
        return sb.toString();
      }

      // Group absent records by lecture string (normalize empty -> 'General')
      final Map<String, List<AttendanceRecord>> byLecture = {};
      for (var rec in absentRecords) {
        final key = (rec.lecture == null || rec.lecture!.trim().isEmpty) ? 'General' : rec.lecture!.trim();
        byLecture.putIfAbsent(key, () => []).add(rec);
      }

      // Helper: parse subject & lecture number
      String _subjectOf(String lectureKey) {
        if (lectureKey.contains(' - Lecture ')) {
          return lectureKey.split(' - Lecture ').first.trim();
        }
        if (lectureKey == 'General') return 'GENERAL';
        return lectureKey.trim();
      }

      int _lectureNumberOf(String lectureKey) {
        if (lectureKey.contains(' - Lecture ')) {
          final n = int.tryParse(lectureKey.split(' - Lecture ').last.trim());
          return n ?? -1;
        }
        return -1;
      }

      String _timingForLecture(int n) {
        switch (n) {
          case 1: return '8:00-8:50';
          case 2: return '8:50-9:45';
          case 3: return '10:00-10:50';
          case 4: return '10:50-11:40';
          case 5: return '12:30-1:20';
          case 6: return '1:20-2:10';
          default: return '';
        }
      }

      String _facultyFor(String subject) {
        final up = subject.toUpperCase();
        if (up.startsWith('DCN')) return "PARITA MA'AM";
        if (up.startsWith('DS')) return "JANKI MA'AM";
        if (up.startsWith('MATH')) return "PURVANGI MA'AM / MMP SIR";
        if (up.startsWith('ADBMS')) return 'NIKUNJ SIR';
        if (up.startsWith('OOP')) return "NEHA MA'AM / TWINKLE MA'AM";
        return '';
      }

      // Sort lecture keys by inferred lecture number then by subject
      final lectureKeys = byLecture.keys.toList();
      lectureKeys.sort((a, b) {
        final na = _lectureNumberOf(a);
        final nb = _lectureNumberOf(b);
        if (na != -1 && nb != -1 && na != nb) return na.compareTo(nb);
        if (na != -1 && nb == -1) return -1;
        if (na == -1 && nb != -1) return 1;
        return a.compareTo(b);
      });

      int headerIndex = 1;
      for (final lectureKey in lectureKeys) {
        final subject = _subjectOf(lectureKey);
        final lectureNum = _lectureNumberOf(lectureKey);
        final timing = _timingForLecture(lectureNum);
        final faculty = _facultyFor(subject);

        // Requested: remove '(Lecture X)' label and keep index + subject + timing + faculty
        sb.writeln('[${headerIndex}] $subject${timing.isNotEmpty ? ' $timing' : ''}${faculty.isNotEmpty ? ' [$faculty]' : ''}');

        // Build department-only grouping (e.g., CE:, IT:)
        final Map<String, List<Student>> byDept = {};
        final records = byLecture[lectureKey]!;
        // Avoid duplicate same student for same lecture
        final seen = <int>{};
        for (var rec in records) {
          if (seen.contains(rec.studentId)) continue;
          seen.add(rec.studentId);
          final st = studentMap[rec.studentId];
          if (st == null) continue;
          final key = st.department; // department only
          byDept.putIfAbsent(key, () => []).add(st);
        }

        final deptKeys = byDept.keys.toList()..sort();
        for (final dk in deptKeys) {
          sb.writeln(dk + ':');
          final list = byDept[dk]!;
          // Sort by numeric part of roll number if present
          list.sort((a, b) {
            final rx = RegExp(r'(\d+)');
            final ma = rx.firstMatch(a.rollNumber);
            final mb = rx.firstMatch(b.rollNumber);
            if (ma != null && mb != null) {
              return int.parse(ma.group(1)!).compareTo(int.parse(mb.group(1)!));
            }
            return a.rollNumber.compareTo(b.rollNumber);
          });
          for (final st in list) {
            // Prefer digits after ':' like CE-B:01, else any first digits
            final afterColon = RegExp(r':(\d+)').firstMatch(st.rollNumber);
            String rollDigits = afterColon?.group(1) ?? (RegExp(r'(\d+)').firstMatch(st.rollNumber)?.group(1) ?? st.rollNumber);
            // Remove leading zeros if numeric
            final rollNum = int.tryParse(rollDigits);
            final displayRoll = rollNum != null ? rollNum.toString() : rollDigits;
            sb.writeln('$displayRoll: ${st.name}');
          }
          sb.writeln('');
        }
        headerIndex++;
      }

      return sb.toString().trimRight();
    } catch (e) {
      return 'Error generating absentee report: $e';
    }
  }

  Future<String> generateFormattedAttendanceReport(String date, int semester, String department, String division, {String reportType = 'absentees'}) async {
    if (reportType == 'absentees') {
      return generateFormattedAbsenteeReport(date, semester, department, division);
    }
    try {
      await fetchAttendanceByDate(date);
      final students = await DatabaseHelper.instance.getStudentsByCombinedClassOrdered(semester, department, division);
      final idSet = students.map((s) => s.id!).toSet();

      // Removed unused presentRecords and studentMap to avoid warnings
      final absentRecords = _attendanceRecords.where((r) => _formatDate(r.date) == date && !r.isPresent && idSet.contains(r.studentId)).toList();

      final sb = StringBuffer();
      if (reportType == 'present') {
        sb.writeln('DAILY PRESENT STUDENTS REPORT');
      } else {
        sb.writeln('COMPLETE DAILY ATTENDANCE REPORT');
      }
      sb.writeln('Date: $date');
      sb.writeln('Class: ${semester}${department}-${division}');
      sb.writeln('Total Students: ${students.length}');
      sb.writeln('Present: ${students.length - absentRecords.length}');
      sb.writeln('Absent: ${absentRecords.length}');
      sb.writeln('');

      if (reportType == 'present') {
        sb.writeln('PRESENT STUDENTS:');
        sb.writeln('-' * 40);
        // A student is present if no absent record for them (or explicitly marked present)
        final absentIdSet = absentRecords.map((r) => r.studentId).toSet();
        int idx = 1;
        for (var s in students) {
          if (!absentIdSet.contains(s.id)) {
            sb.writeln('${idx.toString().padLeft(2,'0')}. ${s.name} (${s.rollNumber})');
            idx++;
          }
        }
      } else { // all
        sb.writeln('ALL STUDENTS STATUS:');
        sb.writeln('-' * 40);
        int idx = 1;
        final absentIdSet = absentRecords.map((r) => r.studentId).toSet();
        final absentMap = {for (var r in absentRecords) r.studentId: r};
        for (var s in students) {
          final absentRec = absentMap[s.id];
          final present = !absentIdSet.contains(s.id);
          final status = present ? '✅ Present' : '❌ Absent';
          sb.writeln('${idx.toString().padLeft(2,'0')}. ${s.name} (${s.rollNumber}) - $status');
          if (!present && absentRec != null) {
            if (absentRec.lecture != null && absentRec.lecture!.isNotEmpty) sb.writeln('    Subject: ${absentRec.lecture}');
            if (absentRec.notes != null && absentRec.notes!.trim().isNotEmpty) sb.writeln('    Note: ${absentRec.notes!.trim()}');
          }
          idx++;
        }
      }
      sb.writeln('');
      sb.writeln('Generated on: ${DateTime.now().toString().substring(0,16)}');
      return sb.toString();
    } catch (e) {
      return 'Error generating attendance report: $e';
    }
  }

  void clearRecords() {
    _attendanceRecords.clear();
    _setState(AttendanceProviderState.idle);
  }

  Future<Map<String, dynamic>> getAttendanceStats(String fromDate, String toDate) async {
    if (!_isValidDateRange(fromDate, toDate)) {
      throw ArgumentError('Invalid date range');
    }
    try {
      final records = await DatabaseHelper.instance.getAttendanceByDateRange(fromDate, toDate);
      final total = records.length;
      final present = records.where((r) => r.isPresent).length;
      final absent = total - present;
      final percentage = total > 0 ? (present / total) * 100 : 0.0;
      return {
        'total': total,
        'present': present,
        'absent': absent,
        'percentage': percentage,
      };
    } catch (e) {
      throw Exception('Failed to get attendance statistics: $e');
    }
  }

  // Per-day statistics for a specific class (optional utility)
  Future<Map<String, dynamic>> getAttendanceStatistics(String date, int semester, String department, String division) async {
    try {
      await fetchAttendanceByDate(date);
      final students = await DatabaseHelper.instance.getStudentsByCombinedClassOrdered(semester, department, division);
      final idSet = students.map((s) => s.id!).toSet();
      final presentRecords = _attendanceRecords.where((r) => _formatDate(r.date) == date && r.isPresent && idSet.contains(r.studentId)).length;
      final absentRecords = _attendanceRecords.where((r) => _formatDate(r.date) == date && !r.isPresent && idSet.contains(r.studentId)).length;
      final total = presentRecords + absentRecords; // only counted if attendance taken
      final percentage = total > 0 ? (presentRecords / total) * 100 : 0.0;
      return {
        'date': date,
        'semester': semester,
        'department': department,
        'division': division,
        'total': total,
        'present': presentRecords,
        'absent': absentRecords,
        'percentage': percentage,
      };
    } catch (e) {
      throw Exception('Failed to get attendance statistics: $e');
    }
  }
}
