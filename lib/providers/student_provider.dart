import 'package:flutter/material.dart';
import 'package:csv/csv.dart';
import 'package:sqflite/sqflite.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/models.dart';
import '../services/database_helper.dart';

enum StudentProviderState { idle, loading, error }

class StudentProvider with ChangeNotifier {
  List<Student> _students = [];
  StudentProviderState _state = StudentProviderState.idle;
  String? _errorMessage;
  bool _disposed = false;

  List<Student> get students => _students;
  StudentProviderState get state => _state;
  bool get isLoading => _state == StudentProviderState.loading;
  bool get hasError => _state == StudentProviderState.error;
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

  void _setState(StudentProviderState newState, {String? error}) {
    _state = newState;
    _errorMessage = error;
    _safeNotifyListeners();
  }

  Future<void> fetchStudents() async {
    if (_state == StudentProviderState.loading) return; // Prevent concurrent calls

    _setState(StudentProviderState.loading);

    try {
      // Load sample data if database is empty (for testing)
      await DatabaseHelper.instance.loadSampleData();

      final students = await DatabaseHelper.instance.getAllStudents();
      _students = students;
      _sortStudents();
      _setState(StudentProviderState.idle);
    } catch (e) {
      print('Error fetching students: $e');
      _setState(StudentProviderState.error, error: 'Failed to load students: ${e.toString()}');
    }
  }

  // Sort students so that CE students come first (by numeric roll) then IT students, then others by numeric roll.
  void _sortStudents() {
    int compareByRoll(Student a, Student b) {
      final ceitRegex = RegExp(r'(CE|IT)-[A-Z]:(\d+)');
      final ma = ceitRegex.firstMatch(a.rollNumber.toUpperCase());
      final mb = ceitRegex.firstMatch(b.rollNumber.toUpperCase());

      if (ma != null && mb != null) {
        final deptA = ma.group(1)!;
        final deptB = mb.group(1)!;
        if (deptA != deptB) return deptA == 'CE' ? -1 : 1;
        final numA = int.tryParse(ma.group(2)!) ?? 0;
        final numB = int.tryParse(mb.group(2)!) ?? 0;
        return numA.compareTo(numB);
      }

      // If only one matches the CE/IT pattern, prefer the matching one (so CE/IT stay together)
      if (ma != null && mb == null) return -1;
      if (ma == null && mb != null) return 1;

      // Fallback: compare by the first numeric sequence found in the roll string
      final numRegex = RegExp(r'(\d+)');
      final ra = numRegex.firstMatch(a.rollNumber);
      final rb = numRegex.firstMatch(b.rollNumber);
      if (ra != null && rb != null) {
        final na = int.tryParse(ra.group(1)!) ?? 0;
        final nb = int.tryParse(rb.group(1)!) ?? 0;
        return na.compareTo(nb);
      }

      // Last resort: alphabetical
      return a.rollNumber.compareTo(b.rollNumber);
    }

    _students.sort(compareByRoll);
  }

  Future<bool> addStudent(Student student) async {
    try {
      // Validate roll number uniqueness before attempting to insert
      if (await DatabaseHelper.instance.isRollNumberExists(student.rollNumber)) {
        _setState(StudentProviderState.error, error: 'Roll number ${student.rollNumber} already exists');
        return false;
      }

      final id = await DatabaseHelper.instance.insertStudent(student);
      final newStudent = Student(
        id: id,
        name: student.name,
        rollNumber: student.rollNumber,
        semester: student.semester,
        department: student.department,
        division: student.division,
        timeSlot: student.timeSlot,
        createdAt: student.createdAt,
      );
      _students.add(newStudent);
      _sortStudents(); // Keep sorted by roll number ordering
      _safeNotifyListeners();
      return true;
    } catch (e) {
      print('Error adding student: $e');
      String errorMsg = 'Failed to add student';
      if (e is ArgumentError) {
        errorMsg = e.message;
      }
      _setState(StudentProviderState.error, error: errorMsg);
      return false;
    }
  }

  Future<bool> updateStudent(Student student) async {
    try {
      // Check if roll number exists for other students
      if (await DatabaseHelper.instance.isRollNumberExists(student.rollNumber, excludeId: student.id)) {
        _setState(StudentProviderState.error, error: 'Roll number ${student.rollNumber} is already taken by another student');
        return false;
      }

      await DatabaseHelper.instance.updateStudent(student);
      final index = _students.indexWhere((s) => s.id == student.id);
      if (index != -1) {
        _students[index] = student;
        _sortStudents(); // Keep sorted by roll number ordering
        _safeNotifyListeners();
      }
      return true;
    } catch (e) {
      print('Error updating student: $e');
      _setState(StudentProviderState.error, error: 'Failed to update student: ${e.toString()}');
      return false;
    }
  }

  Future<bool> deleteStudent(int id, {bool showConfirmation = true}) async {
    try {
      await DatabaseHelper.instance.deleteStudent(id);
      _students.removeWhere((student) => student.id == id);
      _safeNotifyListeners();
      return true;
    } catch (e) {
      print('Error deleting student: $e');
      _setState(StudentProviderState.error, error: 'Failed to delete student: ${e.toString()}');
      return false;
    }
  }

  // Get students by class (semester, department, division)
  List<Student> getStudentsByClass(int semester, String department, String division) {
    // Handle combined departments like CE/IT
    List<String> deptList = department.contains('/') ? department.split('/') : [department];

    List<Student> filteredStudents = _students.where((student) =>
      student.semester == semester &&
      student.division == division &&
      deptList.contains(student.department)
    ).toList();

    // Custom sorting for CE/IT: CE students first (by roll number), then IT students (by roll number)
    if (department == 'CE/IT') {
      filteredStudents.sort((a, b) {
        // Extract department and number from roll number (e.g., "CE-B:01" -> "CE", "01")
        RegExp rollRegex = RegExp(r'(CE|IT)-[A-Z]:(\d+)');

        Match? matchA = rollRegex.firstMatch(a.rollNumber);
        Match? matchB = rollRegex.firstMatch(b.rollNumber);

        if (matchA != null && matchB != null) {
          String deptA = matchA.group(1)!;
          String deptB = matchB.group(1)!;
          int numA = int.parse(matchA.group(2)!);
          int numB = int.parse(matchB.group(2)!);

          // CE comes before IT
          if (deptA != deptB) {
            return deptA == 'CE' ? -1 : 1;
          }

          // Within same department, sort by roll number
          return numA.compareTo(numB);
        }

        // Fallback to normal string comparison
        return a.rollNumber.compareTo(b.rollNumber);
      });
    } else {
      // For other departments, sort by roll number
      filteredStudents.sort((a, b) {
        RegExp rollRegex = RegExp(r'(\d+)');
        Match? matchA = rollRegex.firstMatch(a.rollNumber);
        Match? matchB = rollRegex.firstMatch(b.rollNumber);

        if (matchA != null && matchB != null) {
          int numA = int.parse(matchA.group(1)!);
          int numB = int.parse(matchB.group(1)!);
          return numA.compareTo(numB);
        }

        return a.rollNumber.compareTo(b.rollNumber);
      });
    }

    return filteredStudents;
  }

  // Get students by department only
  List<Student> getStudentsByDepartment(String department) {
    List<String> deptList = department.contains('/') ? department.split('/') : [department];

    return _students.where((student) =>
      deptList.contains(student.department)
    ).toList();
  }

  // Get unique class combinations
  List<Map<String, dynamic>> getClassCombinations() {
    Set<String> combinations = {};
    List<Map<String, dynamic>> result = [];

    for (var student in _students) {
      String key = '${student.semester}-${student.department}-${student.division}';
      if (!combinations.contains(key)) {
        combinations.add(key);
        result.add({
          'semester': student.semester,
          'department': student.department,
          'division': student.division,
        });
      }
    }

    result.sort((a, b) {
      int semesterComparison = a['semester'].compareTo(b['semester']);
      if (semesterComparison != 0) return semesterComparison;

      int deptComparison = a['department'].compareTo(b['department']);
      if (deptComparison != 0) return deptComparison;

      return a['division'].compareTo(b['division']);
    });

    return result;
  }

  Future<List<Student>> searchStudents(String query) async {
    if (query.isEmpty) return _students;

    final lowercaseQuery = query.toLowerCase();
    return _students.where((student) =>
        student.name.toLowerCase().contains(lowercaseQuery) ||
        student.rollNumber.toLowerCase().contains(lowercaseQuery)).toList();
  }

  void clearError() {
    if (_state == StudentProviderState.error) {
      _setState(StudentProviderState.idle);
    }
  }

  // Bulk operations with atomic transactions
  Future<bool> bulkDeleteStudents(List<int> studentIds) async {
    if (studentIds.isEmpty) return true;

    try {
      final db = await DatabaseHelper.instance.database;
      await db.transaction((txn) async {
        for (final id in studentIds) {
          await txn.delete('students', where: 'id = ?', whereArgs: [id]);
        }
      });

      _students.removeWhere((student) => studentIds.contains(student.id));
      _safeNotifyListeners();
      return true;
    } catch (e) {
      print('Error in bulk delete: $e');
      _setState(StudentProviderState.error, error: 'Failed to delete students: ${e.toString()}');
      return false;
    }
  }

  // Helper: check if a CSV row is effectively empty (all cells null/empty)
  bool _isRowEmpty(List<dynamic> row) {
    return row.isEmpty || row.every((c) => (c == null) || c.toString().trim().isEmpty);
  }

  // Helper: try to parse department/division from roll e.g., CE-B:01 -> CE, B
  Map<String, String>? _extractDeptDivFromRoll(String roll) {
    final re = RegExp(r'^([A-Za-z]+)-([A-Za-z]+):([0-9]+)$');
    final m = re.firstMatch(roll.trim());
    if (m != null) {
      return {
        'department': m.group(1)!.toUpperCase(),
        'division': m.group(2)!.toUpperCase(),
      };
    }
    return null;
  }

  // Bulk import from CSV with batching
  Future<Map<String, dynamic>> bulkImportFromCsv(String csvData) async {
    _setState(StudentProviderState.loading);
    const int batchSize = 50; // Process 50 students at a time

    try {
      final List<List<dynamic>> rawTable = const CsvToListConverter().convert(csvData);

      if (rawTable.isEmpty) {
        _setState(StudentProviderState.error, error: 'CSV file is empty');
        return {'success': false, 'message': 'CSV file is empty'};
      }

      // Remove empty rows
      final nonEmptyRows = rawTable.where((r) => !_isRowEmpty(r)).toList();
      if (nonEmptyRows.isEmpty) {
        _setState(StudentProviderState.error, error: 'CSV contains no data rows');
        return {'success': false, 'message': 'CSV contains no data rows'};
      }

      // Skip header row if it exists
      final bool hasHeader = _isHeaderRow(nonEmptyRows.first);
      final dataRows = hasHeader ? nonEmptyRows.skip(1).toList() : nonEmptyRows;

      if (dataRows.isEmpty) {
        _setState(StudentProviderState.error, error: 'No data rows found in CSV');
        return {'success': false, 'message': 'No data rows found in CSV'};
      }

      List<Student> studentsToAdd = [];
      List<String> errors = [];
      Set<String> existingRollNumbers = {};

      // Pre-fetch existing roll numbers in one go
      final existingStudents = await DatabaseHelper.instance.getAllStudents();
      existingRollNumbers.addAll(existingStudents.map((s) => s.rollNumber.toUpperCase()));

      // Process rows in batches
      for (int i = 0; i < dataRows.length; i += batchSize) {
        final endIndex = (i + batchSize < dataRows.length) ? i + batchSize : dataRows.length;
        final batch = dataRows.sublist(i, endIndex);

        await _processCsvBatch(batch, i, studentsToAdd, errors, existingRollNumbers);

        // Update loading state with progress
        _setState(StudentProviderState.loading);
        _safeNotifyListeners();
      }

      if (studentsToAdd.isEmpty) {
        _setState(StudentProviderState.error, error: 'No valid students to import');
        return {
          'success': false,
          'message': 'No valid students to import',
          'errors': errors,
          'imported': 0,
          'total': dataRows.length,
        };
      }

      // Bulk insert using batched transactions
      final db = await DatabaseHelper.instance.database;

      int totalInserted = 0;
      final List<Student> allAdded = [];

      // Insert in batches
      for (int i = 0; i < studentsToAdd.length; i += batchSize) {
        final endIndex = (i + batchSize < studentsToAdd.length) ? i + batchSize : studentsToAdd.length;
        final batch = studentsToAdd.sublist(i, endIndex);

        // Track only this batch's added students to avoid duplicates in provider list
        final List<Student> batchAdded = [];

        await db.transaction((txn) async {
          for (final student in batch) {
            try {
              final id = await txn.insert('students', student.toMap());
              final s = student.copyWith(id: id);
              batchAdded.add(s);
              allAdded.add(s);
            } on DatabaseException catch (dbEx) {
              final msg = dbEx.toString();
              if (msg.toLowerCase().contains('unique') || msg.toLowerCase().contains('constraint')) {
                errors.add('Failed to insert ${student.name} (${student.rollNumber}): duplicate roll number (unique constraint)');
              } else {
                errors.add('Failed to insert ${student.name} (${student.rollNumber}): ${dbEx.toString()}');
              }
            } catch (e) {
              errors.add('Failed to insert ${student.name} (${student.rollNumber}): ${e.toString()}');
            }
          }
        });

        totalInserted += batchAdded.length;

        // Update UI after each batch: add only newly added
        _students.addAll(batchAdded);
        _sortStudents();
        _safeNotifyListeners();

        // Attempt to sync this batch to Firestore (best-effort). Use roll number as document id
        // for idempotency. Any Firestore errors are recorded but do not abort the local import.
        try {
          final firestore = FirebaseFirestore.instance;
          final fbBatch = firestore.batch();
          for (final s in batchAdded) {
            final docId = s.rollNumber.replaceAll(RegExp(r'[^A-Za-z0-9_\-]'), '_').toUpperCase();
            final docRef = firestore.collection('students').doc(docId);
            fbBatch.set(docRef, {
              'name': s.name,
              'rollNumber': s.rollNumber,
              'semester': s.semester,
              'department': s.department,
              'division': s.division,
              'timeSlot': s.timeSlot,
              'localId': s.id,
              'createdAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
          }
          await fbBatch.commit();
        } catch (fbErr) {
          errors.add('Firestore sync failed for batch starting at ${i}: ${fbErr.toString()}');
        }
      }

      _setState(StudentProviderState.idle);
      return {
        'success': true,
        'message': 'Import completed',
        'imported': totalInserted,
        'total': dataRows.length,
        'errors': errors,
      };
    } catch (e) {
      _setState(StudentProviderState.error, error: 'Import failed: ${e.toString()}');
      return {
        'success': false,
        'message': 'Import failed: ${e.toString()}',
        'imported': 0,
        'total': 0,
        'errors': [e.toString()],
      };
    }
  }

  Future<void> _processCsvBatch(
    List<List<dynamic>> batch,
    int startIndex,
    List<Student> studentsToAdd,
    List<String> errors,
    Set<String> existingRollNumbers,
  ) async {
    for (int i = 0; i < batch.length; i++) {
      final row = batch[i];
      final rowNumber = startIndex + i + 1;

      try {
        // Skip empty rows defensively
        if (_isRowEmpty(row)) {
          continue;
        }

        // Try to support multiple formats
        // Format A (5+ columns): Name, Roll, Semester, Department, Division
        if (row.length >= 5) {
          final name = row[0]?.toString().trim() ?? '';
          final rollNumber = row[1]?.toString().trim() ?? '';
          final semesterStr = row[2]?.toString().trim() ?? '';
          final department = row[3]?.toString().trim() ?? '';
          final division = row[4]?.toString().trim() ?? '';

          if (name.isEmpty || rollNumber.isEmpty || department.isEmpty || division.isEmpty) {
            errors.add('Row $rowNumber: Empty required fields');
            continue;
          }

          final semester = int.tryParse(semesterStr);
          if (semester == null || semester < 1 || semester > 8) {
            errors.add('Row $rowNumber: Invalid semester "$semesterStr" (must be 1-8)');
            continue;
          }

          final normalizedRollNumber = rollNumber.toUpperCase();
          if (existingRollNumbers.contains(normalizedRollNumber)) {
            errors.add('Row $rowNumber: Roll number "$rollNumber" already exists');
            continue;
          }
          existingRollNumbers.add(normalizedRollNumber);

          final student = Student(
            name: name,
            rollNumber: rollNumber,
            semester: semester,
            department: department,
            division: division,
            timeSlot: '8:00-8:50', // Default time slot for CSV imports
          );

          studentsToAdd.add(student);
          continue;
        }

        // Format B (2+ columns): Roll, Name OR Name, Roll
        if (row.length >= 2) {
          String c0 = row[0]?.toString().trim() ?? '';
          String c1 = row[1]?.toString().trim() ?? '';

          String roll = '';
          String name = '';

          final rollFromC0 = _extractDeptDivFromRoll(c0) != null || ValidationHelper.isValidRollNumber(c0);
          final rollFromC1 = _extractDeptDivFromRoll(c1) != null || ValidationHelper.isValidRollNumber(c1);

          if (rollFromC0 && !rollFromC1) {
            roll = c0; name = c1;
          } else if (!rollFromC0 && rollFromC1) {
            roll = c1; name = c0;
          } else if (rollFromC0 && rollFromC1) {
            // Ambiguous, prefer CE/IT pattern in c0
            roll = _extractDeptDivFromRoll(c0) != null ? c0 : c1;
            name = roll == c0 ? c1 : c0;
          } else {
            errors.add('Row $rowNumber: Could not determine roll and name from columns');
            continue;
          }

          if (name.isEmpty || roll.isEmpty) {
            errors.add('Row $rowNumber: Empty required fields');
            continue;
          }

          final inferred = _extractDeptDivFromRoll(roll);
          if (inferred == null) {
            errors.add('Row $rowNumber: Roll "$roll" not in expected pattern like CE-B:01');
            continue;
          }

          final normalizedRollNumber = roll.toUpperCase();
          if (existingRollNumbers.contains(normalizedRollNumber)) {
            errors.add('Row $rowNumber: Roll number "$roll" already exists');
            continue;
          }
          existingRollNumbers.add(normalizedRollNumber);

          final student = Student(
            name: name,
            rollNumber: roll,
            semester: 3, // Default when not provided
            department: inferred['department']!,
            division: inferred['division']!,
            timeSlot: '8:00-8:50',
          );

          studentsToAdd.add(student);
          continue;
        }

        // If we get here, the row is not in a supported format
        errors.add('Row $rowNumber: Unsupported row format');
      } catch (e) {
        errors.add('Row $rowNumber: ${e.toString()}');
      }
    }
  }

  bool _isHeaderRow(List<dynamic> row) {
    if (row.isEmpty) return false;
    final firstCell = row[0]?.toString().toLowerCase() ?? '';
    if (firstCell.contains('name') || firstCell == 'name') return true;
    if (firstCell.contains('student')) return true;
    if (firstCell.contains('roll')) return true;
    // Also consider a header like: Roll, Name
    if (row.length >= 2) {
      final c1 = row[1]?.toString().toLowerCase() ?? '';
      if ((firstCell.contains('roll') && c1.contains('name')) || (firstCell.contains('name') && c1.contains('roll'))) {
        return true;
      }
    }
    return false;
  }

  // Clear all data (students and attendance)
  Future<bool> clearAllData() async {
    _setState(StudentProviderState.loading);

    try {
      await DatabaseHelper.instance.clearAllData();
      _students.clear();
      _setState(StudentProviderState.idle);
      return true;
    } catch (e) {
      print('Error clearing all data: $e');
      _setState(StudentProviderState.error, error: 'Failed to clear data: ${e.toString()}');
      return false;
    }
  }
}
