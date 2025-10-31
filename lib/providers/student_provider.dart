import 'package:flutter/material.dart';
import 'package:csv/csv.dart';
import 'package:sqflite/sqflite.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';
import '../services/database_helper.dart';
import '../providers/user_provider.dart';

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
      // If the current app user is a CC or CR with allowed classes, prefer fetching
      // students from Firestore for those classes so a new device sees only permitted data.
      final currentUser = UserProvider.instance.user;
      if (currentUser != null && (currentUser.role == UserRole.CC || currentUser.role == UserRole.CR)) {
        print('DEBUG: Current user allowedClasses: \\${currentUser.allowedClasses}');
        final allowed = currentUser.allowedClasses;
        if (allowed.isNotEmpty) {
          try {
            final fromFs = await _fetchStudentsFromFirestoreForAllowedClasses(allowed);
            _students = fromFs;
            _sortStudents();
            _setState(StudentProviderState.idle);
            return;
          } catch (e) {
            // If Firestore fetch fails, fall back to local DB below and log the error
            print('Firestore fetch for allowed classes failed: $e');
          }
        }
      }

      // Temporarily bypass allowedClasses filtering
      _students = await DatabaseHelper.instance.getAllStudents();
      _sortStudents();
      _setState(StudentProviderState.idle);
      return;

      // Default/local behavior: load sample data if database is empty (for testing)
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

  // Helper: query Firestore for students belonging to the list of allowed classes
  Future<List<Student>> _fetchStudentsFromFirestoreForAllowedClasses(List<ClassInfo> allowed) async {
    final firestore = FirebaseFirestore.instance;
    final Map<String, Student> byRoll = {};

    for (final c in allowed) {
      // Query by semester + department + division so Firestore can validate the query
      // against security rules. If your student docs use 'branch' instead of 'department',
      // fall back to querying by 'branch'.
      Query query = firestore.collection('students')
          .where('semester', isEqualTo: c.semester)
          .where('department', isEqualTo: c.department)
          .where('division', isEqualTo: c.division);

      QuerySnapshot snap = await query.get();
      if (snap.docs.isEmpty) {
        // Try fallback: some student docs may use 'branch' instead of 'department'
        final fallbackQuery = firestore.collection('students')
            .where('semester', isEqualTo: c.semester)
            .where('branch', isEqualTo: c.department)
            .where('division', isEqualTo: c.division);
        final fallbackSnap = await fallbackQuery.get();
        if (fallbackSnap.docs.isNotEmpty) {
          snap = fallbackSnap;
        } else {
          print('No student docs in Firestore for sem=${c.semester} dept=${c.department} div=${c.division} (allowed class ${c.displayName})');
        }
      }
      for (final doc in snap.docs) {
        final dRaw = doc.data();
        final d = (dRaw is Map<String, dynamic>) ? dRaw : null;
        if (d == null) continue; // defensive: skip documents with no data or unexpected shape
        try {
          final name = (d['name'] ?? '').toString();
          final roll = (d['rollNumber'] ?? d['roll_number'] ?? '').toString();
          final semDyn = d['semester'];
          // Accept alternate field name 'branch' if 'department' missing
          final deptFromDoc = (d['department'] ?? d['branch'] ?? '').toString();
          final div = (d['division'] ?? c.division).toString();
          final sem = (semDyn is int) ? semDyn : int.tryParse('$semDyn') ?? c.semester;
          final timeSlot = (d['timeSlot'] ?? d['time_slot'] ?? '').toString();
          final enrollment = (d['enrollmentNumber'] ?? d['enrollment_number'] ?? '').toString();

          // Department matching: be case-insensitive and handle combined allowed departments like 'CE/IT'
          final docDeptNorm = deptFromDoc.trim().toUpperCase();
          final allowedDeptNorm = c.department.trim().toUpperCase();
          bool deptMatches = false;
          if (docDeptNorm.isEmpty) {
            // If document has no department, skip (can't verify)
            deptMatches = false;
          } else if (allowedDeptNorm.contains('/')) {
            final parts = allowedDeptNorm.split('/').map((p) => p.trim()).toList();
            deptMatches = parts.any((p) => p == docDeptNorm);
          } else {
            deptMatches = docDeptNorm == allowedDeptNorm;
          }

          if (!deptMatches) {
            // Not the target department; skip this doc
            continue;
          }

          final student = Student(
            id: null,
            name: name,
            rollNumber: roll,
            semester: sem,
            department: deptFromDoc,
            division: div,
            timeSlot: timeSlot,
            enrollmentNumber: enrollment,
          );

          // Use normalized roll as dedupe key
          final key = student.rollNumber.trim().toUpperCase();
          byRoll[key] = student;
        } catch (e) {
          // Ignore malformed entries for robustness
          print('Skipping malformed student doc ${doc.id}: $e');
        }
      }
    }

    final list = byRoll.values.toList();
    // Sort using existing provider logic
    list.sort((a, b) {
      // Use same comparison used in _sortStudents: compareByRoll closure
      final ceitRegex = RegExp(r'(CE|IT)-[A-Z]:(\d+)');
      int compareByRoll(Student x, Student y) {
        final ma = ceitRegex.firstMatch(x.rollNumber.toUpperCase());
        final mb = ceitRegex.firstMatch(y.rollNumber.toUpperCase());
        if (ma != null && mb != null) {
          final deptA = ma.group(1)!;
          final deptB = mb.group(1)!;
          if (deptA != deptB) return deptA == 'CE' ? -1 : 1;
          final numA = int.tryParse(ma.group(2)!) ?? 0;
          final numB = int.tryParse(mb.group(2)!) ?? 0;
          return numA.compareTo(numB);
        }
        if (ma != null && mb == null) return -1;
        if (ma == null && mb != null) return 1;
        final numRegex = RegExp(r'(\d+)');
        final ra = numRegex.firstMatch(x.rollNumber);
        final rb = numRegex.firstMatch(y.rollNumber);
        if (ra != null && rb != null) {
          final na = int.tryParse(ra.group(1)!) ?? 0;
          final nb = int.tryParse(rb.group(1)!) ?? 0;
          return na.compareTo(nb);
        }
        return x.rollNumber.compareTo(y.rollNumber);
      }
      return compareByRoll(a, b);
    });

    // Persist fetched students into local DB for offline use (upsert by enrollment or roll)
    try {
      final persisted = await DatabaseHelper.instance.upsertStudents(list);
      // Keep provider list in sync with persisted records (DB-assigned ids)
      return persisted;
    } catch (e) {
      print('Failed to persist fetched students locally: $e');
      // Fall back to returning in-memory list
      return list;
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
      // Authorization: if current user is a CC, validate allowedClasses includes this student's class
      final current = UserProvider.instance.user;
      if (current != null && (current.role == UserRole.CC || current.role == UserRole.CR)) {
        final allowed = current.allowedClasses;
        final target = ClassInfo(semester: student.semester, department: student.department, division: student.division);
        final permitted = allowed.any((c) => c == target);
        if (!permitted) {
          _setState(StudentProviderState.error, error: 'Not authorized to add students for ${student.department}-${student.division}');
          return false;
        }
      }
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
        enrollmentNumber: student.enrollmentNumber, // Added enrollmentNumber
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
      // Authorization: CC can only update students in their allowed classes
      final current = UserProvider.instance.user;
      if (current != null && (current.role == UserRole.CC || current.role == UserRole.CR)) {
        final allowed = current.allowedClasses;
        final target = ClassInfo(semester: student.semester, department: student.department, division: student.division);
        final permitted = allowed.any((c) => c == target);
        if (!permitted) {
          _setState(StudentProviderState.error, error: 'Not authorized to update students for ${student.department}-${student.division}');
          return false;
        }
      }
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
      // Ensure authorization: if CC, check the student belongs to their allowed classes
      final current = UserProvider.instance.user;
      if (current != null && (current.role == UserRole.CC || current.role == UserRole.CR)) {
        final students = _students.where((s) => s.id == id).toList();
        if (students.isEmpty) {
          _setState(StudentProviderState.error, error: 'Student not found');
          return false;
        }
        final s = students.first;
        final allowed = current.allowedClasses;
        final target = ClassInfo(semester: s.semester, department: s.department, division: s.division);
        if (!allowed.any((c) => c == target)) {
          _setState(StudentProviderState.error, error: 'Not authorized to delete student for ${s.department}-${s.division}');
          return false;
        }
      }
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
      // Authorization: CC may only delete students in their allowed classes; filter unauthorized IDs out
      final current = UserProvider.instance.user;
      if (current != null && (current.role == UserRole.CC || current.role == UserRole.CR)) {
        final allowed = current.allowedClasses;
        // Build set of permitted student ids
        final permittedIds = _students.where((s) => studentIds.contains(s.id) && allowed.any((c) => c == ClassInfo(semester: s.semester, department: s.department, division: s.division))).map((s) => s.id).toSet();
        if (permittedIds.isEmpty) {
          _setState(StudentProviderState.error, error: 'Not authorized to delete selected students');
          return false;
        }
        // Replace studentIds with only permitted ones
        studentIds = studentIds.where((id) => permittedIds.contains(id)).toList();
        if (studentIds.isEmpty) return true;
      }
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

      // Parse optional leading metadata rows (e.g., CC name / CC's mail)
      String? ccName;
      String? ccEmail;
      // Collect rows that are actual data (we'll remove metadata lines)
      final List<List<dynamic>> dataCandidates = List.from(nonEmptyRows);
      for (int i = 0; i < nonEmptyRows.length; i++) {
        final row = nonEmptyRows[i].map((c) => c?.toString().trim() ?? '').toList();
        // Look for patterns like: "", "", "CC", "Nikunj Vadher", ...
        final lower = row.map((c) => c.toLowerCase()).toList();
        if (row.where((c) => c.isNotEmpty).isEmpty) {
          // skip fully empty (shouldn't be present due to earlier filter)
          dataCandidates.remove(row);
          continue;
        }
        if (lower.contains('cc')) {
          // try to find name near the 'CC' token
          final idx = lower.indexOf('cc');
          if (idx + 1 < row.length && row[idx + 1].isNotEmpty) ccName = row[idx + 1];
          dataCandidates.remove(nonEmptyRows[i]);
          continue;
        }
        if (lower.contains("cc's mail") || lower.contains('cc mail') || lower.any((c) => c.contains("@"))) {
          // pick first cell containing an @ as email if present
          for (final cell in row) {
            if (cell.contains('@')) {
              ccEmail = cell;
              break;
            }
          }
          dataCandidates.remove(nonEmptyRows[i]);
          continue;
        }
        // If the row looks like a header (contains 'sem' or 'roll' keywords), stop scanning metadata
        if (_isHeaderRow(row)) break;
        // If we reach a row that looks like data (has numeric semester and division), stop
        if (row.isNotEmpty && row[0].isNotEmpty && int.tryParse(row[0]) != null) break;
      }

      // Skip header row if it exists
      // Find header row index in dataCandidates
      int headerIndex = -1;
      for (int i = 0; i < dataCandidates.length; i++) {
        if (_isHeaderRow(dataCandidates[i])) { headerIndex = i; break; }
      }
      final bool hasHeader = headerIndex != -1;
      final headerRow = hasHeader ? dataCandidates[headerIndex].map((c) => c?.toString().trim() ?? '').toList() : null;
      // Build header map: column name -> index
      Map<String, int>? headerMap;
      if (hasHeader && headerRow != null) {
        headerMap = {};
        for (int i = 0; i < headerRow.length; i++) {
          final raw = headerRow[i].toLowerCase();
          final key = raw.replaceAll(RegExp(r'[ _]'), ''); // normalize

          // Enrollment / enrollment_number / enrollment no
          if (key.contains('enroll') || key.contains('enrollment')) {
            headerMap['enrollment_number'] = i;
          }

          // Full name / fullname / name
          if (key.contains('fullname') || (key.contains('full') && key.contains('name')) || key == 'name') {
            headerMap['full_name'] = i;
            headerMap['name'] = i;
          }

          // Roll number variations
          if (key.contains('roll')) {
            headerMap['roll_number'] = i;
            headerMap['roll'] = i;
          }

          // Semester (allow sem or semester)
          if (key.contains('sem')) {
            headerMap['sem'] = i;
            headerMap['semester'] = i;
          }

          // Division
          if (key.contains('div')) {
            headerMap['division'] = i;
          }

          // Branch / department / dept
          if (key.contains('branch') || key.contains('dept') || key.contains('department')) {
            headerMap['branch'] = i;
            headerMap['department'] = i;
          }

          // Explicitly ignore any timeslot/createdAt-like columns for CSV import
          if (key.contains('time') || key.contains('slot') || key.contains('created') || key.contains('timestamp')) {
            // don't map these; they are intentionally ignored
          }
        }
      }

      final List<List<dynamic>> dataRows = [];
      if (hasHeader) {
        // take rows after headerRow in dataCandidates
        for (int i = headerIndex + 1; i < dataCandidates.length; i++) dataRows.add(dataCandidates[i]);
      } else {
        dataRows.addAll(dataCandidates);
      }

      if (dataRows.isEmpty) {
        _setState(StudentProviderState.error, error: 'No data rows found in CSV');
        return {'success': false, 'message': 'No data rows found in CSV'};
      }

      List<Student> studentsToAdd = [];
      List<String> errors = [];

      // Use composite key dept|div|rollId for uniqueness to avoid collisions when roll numbers repeat across branches/divisions
      final Set<String> existingKeys = {};

      // Note: parsing is delegated to _processCsvBatch which understands headerMap and CEIT-A template.
      // existingKeys will be populated by the batch processor to ensure idempotent uniqueness checks.

      // Process rows in batches
      for (int i = 0; i < dataRows.length; i += batchSize) {
        final endIndex = (i + batchSize < dataRows.length) ? i + batchSize : dataRows.length;
        final batch = dataRows.sublist(i, endIndex);

        await _processCsvBatch(batch, i, studentsToAdd, errors, existingKeys, headerMap: headerMap);

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
          'cc_name': ccName,
          'cc_email': ccEmail,
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
              // Check DB for existing enrollment_number (if present)
              if (student.enrollmentNumber.isNotEmpty) {
                final existingEnroll = await txn.query(
                  'students',
                  where: 'enrollment_number = ?',
                  whereArgs: [student.enrollmentNumber.trim().toUpperCase()],
                  limit: 1,
                );
                if (existingEnroll.isNotEmpty) {
                  errors.add('Skipped ${student.name}: enrollment ${student.enrollmentNumber} already exists in DB');
                  continue; // skip inserting this student
                }
              }

              // Check DB for existing roll number (global unique constraint)
              final existingRoll = await txn.query(
                'students',
                where: 'roll_number = ?',
                whereArgs: [student.rollNumber.trim().toUpperCase()],
                limit: 1,
              );
              if (existingRoll.isNotEmpty) {
                errors.add('Skipped ${student.name}: roll ${student.rollNumber} already exists in DB');
                continue; // skip inserting this student
              }

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
            final Map<String, dynamic> payload = {
              'name': s.name,
              'rollNumber': s.rollNumber,
              'semester': s.semester,
              'department': s.department,
              'division': s.division,
              'localId': s.id,
              'createdAt': FieldValue.serverTimestamp(),
            };
            // Only include timeSlot if non-empty (we don't accept timeSlot from CSV)
            if (s.timeSlot.isNotEmpty) payload['timeSlot'] = s.timeSlot;
            fbBatch.set(docRef, payload, SetOptions(merge: true));
          }
          await fbBatch.commit();
        } catch (fbErr) {
          errors.add('Firestore sync failed for batch starting at ${i}: ${fbErr.toString()}');
        }
      }

      _setState(StudentProviderState.idle);
      // Persist CC metadata for later use (e.g., reports/email)
      try {
        if (ccEmail != null || ccName != null) {
          final prefs = await SharedPreferences.getInstance();
          if (ccEmail != null) await prefs.setString('last_import_cc_email', ccEmail);
          if (ccName != null) await prefs.setString('last_import_cc_name', ccName);
        }
      } catch (_) {
        // ignore prefs write failures
      }

      return {
        'success': true,
        'message': 'Import completed',
        'imported': totalInserted,
        'total': dataRows.length,
        'errors': errors,
        'cc_name': ccName,
        'cc_email': ccEmail,
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
    Set<String> existingKeys,
    { Map<String,int>? headerMap }
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
         // If headerMap is provided parse columns according to header names
         if (headerMap != null && headerMap.isNotEmpty) {
           // Allow separator rows like: Sem,Division,,,
           final semCell = row.length > (headerMap['semester'] ?? -1) ? row[headerMap['semester']!]?.toString().trim() ?? '' : '';
           final divCell = row.length > (headerMap['division'] ?? -1) ? row[headerMap['division']!]?.toString().trim() ?? '' : '';
           final deptCell = row.length > (headerMap['department'] ?? -1) ? row[headerMap['department']!]?.toString().trim() ?? '' : '';
           // prefer explicit roll_number header but fall back to generic 'roll'
           final rollCell = row.length > (headerMap['roll_number'] ?? headerMap['roll'] ?? -1)
               ? row[(headerMap['roll_number'] ?? headerMap['roll'])!]?.toString().trim() ?? '' : '';
           // prefer full_name then name
           final nameCell = row.length > (headerMap['full_name'] ?? headerMap['name'] ?? -1)
               ? row[(headerMap['full_name'] ?? headerMap['name'])!]?.toString().trim() ?? '' : '';
           // optional enrollment number
           final enrollCell = headerMap.containsKey('enrollment_number') && row.length > headerMap['enrollment_number']!
               ? row[headerMap['enrollment_number']!]?.toString().trim() ?? '' : '';

           // Treat rows where only semester+division present as separators -> skip silently
           if (semCell.isNotEmpty && divCell.isNotEmpty && rollCell.isEmpty && nameCell.isEmpty) {
             continue; // separator between sections
           }

           if (semCell.isEmpty || divCell.isEmpty || rollCell.isEmpty || nameCell.isEmpty || deptCell.isEmpty) {
             errors.add('Row $rowNumber: Empty required fields');
             continue;
           }

           final semester = int.tryParse(semCell);
           if (semester == null || semester < 1 || semester > 8) {
             errors.add('Row $rowNumber: Invalid semester "$semCell" (must be 1-8)');
             continue;
           }

           // Normalize roll number: if rollCell lacks department/division info but branch/div are present,
           // build a canonical roll like 'CE-B:01' to avoid DB-unique conflicts where roll_number alone is used.
           final deptNorm = deptCell.trim().toUpperCase();
           final divNorm = divCell.trim().toUpperCase();
           String rollNormalized = rollCell.trim();
           if (_extractDeptDivFromRoll(rollNormalized) == null) {
             // If roll is purely numeric, normalize to padded numeric (at least 2 digits)
             final m = RegExp(r'^0*(\d+)$').firstMatch(rollNormalized);
             if (m != null) {
               final numStr = m.group(1)!;
               final padded = numStr.length == 1 ? numStr.padLeft(2, '0') : numStr;
               rollNormalized = '${deptNorm}-${divNorm}:$padded';
             } else if (rollNormalized.isNotEmpty) {
               // Generic fallback: attach dept/div prefix to keep roll strings namespaced
               rollNormalized = '${deptNorm}-${divNorm}:${rollNormalized.toUpperCase()}';
             }
           }

           // Build uniqueness key: prefer enrollment number if present, otherwise composite key
           final key = enrollCell.isNotEmpty ? 'E|${enrollCell.toUpperCase()}' : 'C|${_compositeKey(deptNorm, divNorm, rollNormalized)}';
           if (existingKeys.contains(key)) {
             errors.add('Row $rowNumber: Duplicate student (${enrollCell.isNotEmpty ? 'Enrollment $enrollCell' : 'Roll $rollNormalized in $deptNorm-$divNorm'})');
             continue;
           }
           existingKeys.add(key);

           final student = Student(
             name: nameCell,
             rollNumber: rollNormalized,
             semester: semester,
             department: deptNorm,
             division: divNorm,
             timeSlot: '',
             enrollmentNumber: enrollCell, // Use provided enrollment number or empty
           );
           studentsToAdd.add(student);
           continue;
         }

         // Format B (2+ columns): Roll, Name OR Name, Roll
         if (row.length >= 2) {
           // First check for CEIT-A style template (Enrollment_Number,Full_Name,Roll_Number,Branch,Sem,Division,Role)
           // Some files may not have header; detect by column count >=6 and content patterns.
           if (row.length >= 6) {
             final enrollmentCell = row[0]?.toString().trim() ?? '';
             final fullName = row[1]?.toString().trim() ?? '';
             final rollCell = row[2]?.toString().trim() ?? '';
             final branchCell = row[3]?.toString().trim() ?? '';
             final semCell = row[4]?.toString().trim() ?? '';
             final divCell = row[5]?.toString().trim() ?? '';

             // Basic sanity checks: name, roll, branch, sem, division must be present
             final sem = int.tryParse(semCell);
             if (fullName.isNotEmpty && rollCell.isNotEmpty && branchCell.isNotEmpty && sem != null && divCell.isNotEmpty) {
               // Use composite key to detect duplicates
               // Normalize roll number similar to header parsing when rollCell is numeric-only
               final branchNorm = branchCell.trim().toUpperCase();
               final divNorm = divCell.trim().toUpperCase();
               String rollNormalized = rollCell.trim();
               if (_extractDeptDivFromRoll(rollNormalized) == null) {
                 final m = RegExp(r'^0*(\d+)$').firstMatch(rollNormalized);
                 if (m != null) {
                   final numStr = m.group(1)!;
                   final padded = numStr.length == 1 ? numStr.padLeft(2, '0') : numStr;
                   rollNormalized = '${branchNorm}-${divNorm}:$padded';
                 } else if (rollNormalized.isNotEmpty) {
                   rollNormalized = '${branchNorm}-${divNorm}:${rollNormalized.toUpperCase()}';
                 }
               }

               final key = enrollmentCell.isNotEmpty ? 'E|${enrollmentCell.toUpperCase()}' : 'C|${_compositeKey(branchNorm, divNorm, rollNormalized)}';
               if (existingKeys.contains(key)) {
                 errors.add('Row $rowNumber: Duplicate student (${enrollmentCell.isNotEmpty ? 'Enrollment $enrollmentCell' : 'Roll $rollNormalized in $branchNorm-$divNorm'})');
                 continue;
               }
               existingKeys.add(key);

               final student = Student(
                 name: fullName,
                 rollNumber: rollNormalized,
                 semester: sem,
                 department: branchNorm,
                 division: divNorm,
                 timeSlot: '',
                 enrollmentNumber: enrollmentCell,
               );
               studentsToAdd.add(student);
               continue;
             }
             // else fall through to other parsing strategies
           }

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

           final inferredDept = inferred['department']!;
           final inferredDiv = inferred['division']!;
           // Determine numeric/normalized part of roll
           final key = _compositeKey(inferredDept, inferredDiv, roll);
           if (existingKeys.contains(key)) {
             errors.add('Row $rowNumber: Roll number "$roll" for $inferredDept-$inferredDiv already exists');
             continue;
           }
           existingKeys.add(key);

           final student = Student(
             name: name,
             rollNumber: roll,
             semester: 3, // Default when not provided
             department: inferred['department']!,
             division: inferred['division']!,
             timeSlot: '',
             enrollmentNumber: '', // Placeholder for enrollmentNumber
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
    // Lowercase cells for keyword detection
    final cells = row.map((c) => c?.toString().toLowerCase() ?? '').toList();

    // Keywords that indicate a header row
    final keywords = ['sem', 'semester', 'division', 'div', 'branch', 'dept', 'department', 'roll', 'name', 'full name', 'student'];

    int matches = 0;
    for (final k in keywords) {
      if (cells.any((c) => c.contains(k))) matches++;
    }

    // If two or more header-like keywords are present, treat this as a header row.
    if (matches >= 2) return true;

    // Fallback: check common two-column header patterns like 'roll,name' or 'name,roll'
    if (cells.length >= 2) {
      final c0 = cells[0];
      final c1 = cells[1];
      if ((c0.contains('roll') && c1.contains('name')) || (c0.contains('name') && c1.contains('roll'))) return true;
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

  // Build a composite uniqueness key from department, division and roll identifier.
  // The roll identifier is normalized to its numeric part if available (e.g., CE-B:01 -> 01) else uppercased roll string.
  String _compositeKey(String department, String division, String roll) {
    final dept = department.trim().toUpperCase();
    final div = division.trim().toUpperCase();

    // Extract numeric part after colon if present (CE-B:01 -> 01) or first numeric sequence
    String rollId;
    final colonMatch = RegExp(r':(\d+)').firstMatch(roll);
    if (colonMatch != null) {
      // Normalize numeric part by removing leading zeros
      final num = colonMatch.group(1)!;
      rollId = (int.tryParse(num) ?? 0).toString();
    } else {
      final numMatch = RegExp(r'(\d+)').firstMatch(roll);
      if (numMatch != null) {
        final num = numMatch.group(1)!;
        rollId = (int.tryParse(num) ?? 0).toString();
      } else {
        // Fallback to uppercased roll string
        rollId = roll.trim().toUpperCase();
      }
    }

    return '$dept|$div|$rollId';
  }

  // Helper: robustly match a Firestore student doc to an allowed ClassInfo.
  // Tolerates swapped fields, semester-prefixed department strings, and single-letter department/division mixups.
  bool _matchesAllowedClass(ClassInfo allowed, String department, String division, int semester) {
    final deptAllowed = allowed.department.trim().toUpperCase();
    final divAllowed = allowed.division.trim().toUpperCase();

    // Special case: allow semester-prefixed department strings (for legacy data)
    String deptDoc = department;
    if (department.length > 1 && department[1] == '-') {
      deptDoc = department.substring(2); // skip semester prefix
    }

    // Normalized comparisons
    final deptDocNorm = deptDoc.trim().toUpperCase();
    final divDocNorm = division.trim().toUpperCase();

    // Debug: print expected vs actual for mismatches
    if (deptDocNorm != deptAllowed || divDocNorm != divAllowed) {
      print('ClassInfo mismatch: allowed="$deptAllowed-$divAllowed" doc="$deptDocNorm-$divDocNorm"');
    }

    // Match either directly or swapped (for cases like CE-B vs B-CE)
    return (deptDocNorm == deptAllowed && divDocNorm == divAllowed) ||
           (deptDocNorm == divAllowed && divDocNorm == deptAllowed);
  }
}
