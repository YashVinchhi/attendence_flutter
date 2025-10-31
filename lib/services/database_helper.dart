import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/models.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('attendance.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    // Open database first
    final db = await openDatabase(
      path,
      version: 4, // Incremented version to trigger migration for lecture field
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
    );

    // Ensure required columns/indexes exist for older DBs that may already be at
    // the current version number but were created without the newer columns.
    try {
      await _ensureColumnsExist(db);
    } catch (e) {
      // Non-fatal: log and continue. Worst-case behavior will surface as DB errors.
      print('Warning: _ensureColumnsExist failed: $e');
    }

    return db;
  }

  // Ensure missing columns (non-destructive) are added when needed even if DB
  // version matches. This covers the case where a DB was created without the
  // newer columns but its version already equals the runtime version.
  Future<void> _ensureColumnsExist(Database db) async {
    // Cache table schemas to avoid repeated PRAGMA calls
    final Map<String, List<String>> tableSchemas = {};

    Future<bool> _columnExists(String table, String column) async {
      if (!tableSchemas.containsKey(table)) {
        try {
          final info = await db.rawQuery('PRAGMA table_info("$table")');
          tableSchemas[table] = info.map((row) => row['name']?.toString() ?? '').toList();
        } catch (_) {
          tableSchemas[table] = [];
        }
      }
      return tableSchemas[table]?.contains(column) ?? false;
    }

    // Centralized index creation
    Future<void> _createIndex(String indexName, String table, String columns) async {
      try {
        await db.execute('CREATE INDEX IF NOT EXISTS $indexName ON $table($columns)');
      } catch (e) {
        print('Could not create index $indexName: $e');
      }
    }

    // Ensure columns exist
    try {
      if (!await _columnExists('students', 'time_slot')) {
        await db.execute('ALTER TABLE students ADD COLUMN time_slot TEXT NOT NULL DEFAULT "8:00-8:50"');
      }
      if (!await _columnExists('students', 'enrollment_number')) {
        await db.execute('ALTER TABLE students ADD COLUMN enrollment_number TEXT NOT NULL DEFAULT ""');
      }
      if (!await _columnExists('attendance', 'time_slot')) {
        await db.execute('ALTER TABLE attendance ADD COLUMN time_slot TEXT DEFAULT ""');
      }
    } catch (e) {
      print('Could not ensure columns: $e');
    }

    // Ensure indexes exist
    await _createIndex('idx_students_roll_number', 'students', 'roll_number');
    await _createIndex('idx_students_enrollment_number', 'students', 'enrollment_number');
    await _createIndex('idx_attendance_student_date', 'attendance', 'student_id, date');
    await _createIndex('idx_attendance_lecture', 'attendance', 'lecture');
  }

  Future _createDB(Database db, int version) async {
    const idType = 'INTEGER PRIMARY KEY AUTOINCREMENT';
    const textType = 'TEXT NOT NULL';
    const integerType = 'INTEGER NOT NULL';

    await db.execute('''
      CREATE TABLE students (
        id $idType,
        name $textType,
        roll_number $textType UNIQUE,
        enrollment_number TEXT,
        semester $integerType,
        department $textType,
        division $textType,
        time_slot $textType,
        created_at $textType
      )
    ''');

    await db.execute('''
      CREATE TABLE attendance (
        id $idType,
        student_id $integerType,
        date $textType,
        is_present $integerType,
        notes TEXT,
        lecture TEXT,
        time_slot TEXT,
        created_at TEXT,
        updated_at TEXT,
        FOREIGN KEY (student_id) REFERENCES students (id) ON DELETE CASCADE
      )
    ''');

    // Create indexes for better performance
    await db.execute('CREATE INDEX idx_students_roll_number ON students(roll_number)');
    await db.execute('CREATE INDEX idx_attendance_student_date ON attendance(student_id, date)');
    await db.execute('CREATE INDEX idx_attendance_lecture ON attendance(lecture)');
  }

  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Perform incremental, non-destructive migrations where possible.
    // We guard each migration step with try/catch so upgrades never fail catastrophically.
    try {
      // Ensure attendance and students tables exist (create if missing)
      await db.execute('''
        CREATE TABLE IF NOT EXISTS students (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          roll_number TEXT NOT NULL UNIQUE,
          semester INTEGER NOT NULL,
          department TEXT NOT NULL,
          division TEXT NOT NULL,
          time_slot TEXT NOT NULL DEFAULT "8:00-8:50",
          created_at TEXT
        )
      ''');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS attendance (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          student_id INTEGER NOT NULL,
          date TEXT,
          is_present INTEGER,
          notes TEXT,
          lecture TEXT,
          time_slot TEXT,
          created_at TEXT,
          updated_at TEXT,
          FOREIGN KEY (student_id) REFERENCES students (id) ON DELETE CASCADE
        )
      ''');

      // Add indexes if missing (CREATE INDEX IF NOT EXISTS is supported)
      await db.execute('CREATE INDEX IF NOT EXISTS idx_students_roll_number ON students(roll_number)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_attendance_student_date ON attendance(student_id, date)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_attendance_lecture ON attendance(lecture)');
    } catch (e) {
      // If any of the safe-create steps fail, continue — avoid aborting upgrade.
      print('Non-destructive migration create/index step failed: $e');
    }

    // Add column migrations for older databases. We check using PRAGMA table_info.
    Future<bool> _columnExists(Database db, String table, String column) async {
      try {
        final info = await db.rawQuery('PRAGMA table_info(\'$table\')');
        for (final row in info) {
          final name = row['name']?.toString();
          if (name == column) return true;
        }
      } catch (_) {}
      return false;
    }

    try {
      if (oldVersion < 3) {
        // Ensure attendance has lecture, created_at, updated_at
        if (!await _columnExists(db, 'attendance', 'lecture')) {
          try {
            await db.execute('ALTER TABLE attendance ADD COLUMN lecture TEXT');
          } catch (e) {
            print('Could not add attendance.lecture column: $e');
          }
        }
        if (!await _columnExists(db, 'attendance', 'time_slot')) {
          try {
            await db.execute('ALTER TABLE attendance ADD COLUMN time_slot TEXT DEFAULT ""');
          } catch (e) {
            print('Could not add attendance.time_slot column: $e');
          }
        }
      }

      if (oldVersion < 4) {
        // Ensure students table has time_slot
        if (!await _columnExists(db, 'students', 'time_slot')) {
          try {
            await db.execute('ALTER TABLE students ADD COLUMN time_slot TEXT NOT NULL DEFAULT "8:00-8:50"');
          } catch (e) {
            print('Could not add students.time_slot column: $e');
          }
        }
      }
      // Ensure enrollment_number exists for older DBs too
      if (!await _columnExists(db, 'students', 'enrollment_number')) {
        try {
          await db.execute('ALTER TABLE students ADD COLUMN enrollment_number TEXT NOT NULL DEFAULT ""');
        } catch (e) {
          print('Could not add students.enrollment_number column during upgrade: $e');
        }
      }
      // Ensure index on enrollment_number
      try {
        await db.execute('CREATE INDEX IF NOT EXISTS idx_students_enrollment_number ON students(enrollment_number)');
      } catch (e) {
        print('Could not create idx_students_enrollment_number: $e');
      }
    } catch (e) {
      print('Migration check failed: $e');
    }
  }

  // Load sample data for testing
  Future<void> loadSampleData() async {
    try {
      final db = await database;
      final existingStudents = await db.query('students', limit: 1);
      if (existingStudents.isNotEmpty) {
        print('Sample data already loaded, skipping...');
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      final hasUserClearedData = prefs.getBool('user_cleared_data') ?? false;
      if (hasUserClearedData) {
        print('User has cleared data, not loading sample data automatically');
        return;
      }

      print('Loading sample data from configuration file...');
      final sampleData = await rootBundle.loadString('assets/sample_data/students.json');
      final List<dynamic> students = json.decode(sampleData);

      for (final student in students) {
        await db.insert('students', {
          'name': student['name'],
          'roll_number': student['rollNumber'],
          'semester': student['semester'],
          'department': student['department'],
          'division': student['division'],
          'time_slot': student['timeSlot'] ?? "8:00-8:50",
          'created_at': DateTime.now().toIso8601String(),
        });
      }

      print('Sample data loaded successfully.');
    } catch (e) {
      print('Failed to load sample data: $e');
    }
  }

  // Student operations
  Future<int> insertStudent(Student student) async {
    final db = await instance.database;
    return await db.insert('students', student.toMap());
  }

  Future<List<Student>> getAllStudents() async {
    final db = await instance.database;
    final result = await db.query('students', orderBy: 'name');
    return result.map((map) => Student.fromMap(map)).toList();
  }

  Future<List<Student>> getStudentsByClass(int semester, String department, String division) async {
    final db = await instance.database;
    final result = await db.query(
      'students',
      where: 'semester = ? AND department = ? AND division = ?',
      whereArgs: [semester, department, division],
      orderBy: 'name',
    );
    return result.map((map) => Student.fromMap(map)).toList();
  }

  // Get students by combined class (handles CE/IT together)
  Future<List<Student>> getStudentsByCombinedClass(int semester, String department, String division) async {
    final db = await instance.database;

    String whereClause;
    List<dynamic> whereArgs;

    if (department == 'CE/IT') {
      // For CE/IT, get both CE and IT students
      whereClause = 'semester = ? AND (department = ? OR department = ?) AND division = ?';
      whereArgs = [semester, 'CE', 'IT', division];
    } else {
      // For other departments, use normal query
      whereClause = 'semester = ? AND department = ? AND division = ?';
      whereArgs = [semester, department, division];
    }

    final result = await db.query(
      'students',
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: 'name',
    );
    return result.map((map) => Student.fromMap(map)).toList();
  }

  // Get students by combined class with proper roll number ordering
  Future<List<Student>> getStudentsByCombinedClassOrdered(int semester, String department, String division) async {
    final db = await instance.database;

    String whereClause;
    List<dynamic> whereArgs;

    if (department == 'CE/IT') {
      // For CE/IT, get both CE and IT students
      whereClause = 'semester = ? AND (department = ? OR department = ?) AND division = ?';
      whereArgs = [semester, 'CE', 'IT', division];
    } else {
      // For other departments, use normal query
      whereClause = 'semester = ? AND department = ? AND division = ?';
      whereArgs = [semester, department, division];
    }

    final result = await db.query(
      'students',
      where: whereClause,
      whereArgs: whereArgs,
    );

    List<Student> students = result.map((map) => Student.fromMap(map)).toList();

    // Custom sorting for CE/IT: CE students first (by roll number), then IT students (by roll number)
    if (department == 'CE/IT') {
      students.sort((a, b) {
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
      students.sort((a, b) {
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

    return students;
  }
  Future<int> updateStudent(Student student) async {
    final db = await instance.database;
    return await db.update(
      'students',
      student.toMap(),
      where: 'id = ?',
      whereArgs: [student.id],
    );
  }

  // Utility: Clear all data from tables for a clean reset
  Future<void> clearAllData() async {
    final db = await instance.database;
    await db.transaction((txn) async {
      await txn.delete('attendance');
      await txn.delete('students');
    });
    // Mark that the user cleared data so loadSampleData won't auto-reload samples
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('user_cleared_data', true);
    } catch (_) {}
  }

  Future<int> deleteStudent(int id) async {
    final db = await instance.database;
    return await db.delete(
      'students',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // Attendance operations
  Future<int> insertAttendance(AttendanceRecord attendance) async {
    final db = await instance.database;
    return await db.insert('attendance', attendance.toMap());
  }

  Future<List<AttendanceRecord>> getAttendanceByDate(String date) async {
    final db = await instance.database;
    final result = await db.query(
      'attendance',
      where: 'date = ?',
      whereArgs: [date],
    );
    return result.map((map) => AttendanceRecord.fromMap(map)).toList();
  }

  // Get attendance by date and lecture
  Future<List<AttendanceRecord>> getAttendanceByDateAndLecture(String date, String? lecture, {String? timeSlot}) async {
    final db = await instance.database;
    String whereClause = 'date = ?';
    List<dynamic> whereArgs = [date];

    if (lecture != null && lecture.isNotEmpty) {
      whereClause += ' AND lecture = ?';
      whereArgs.add(lecture);
    }
    if (timeSlot != null && timeSlot.isNotEmpty) {
      whereClause += ' AND time_slot = ?';
      whereArgs.add(timeSlot);
    }

    final result = await db.query(
      'attendance',
      where: whereClause,
      whereArgs: whereArgs,
    );
    return result.map((map) => AttendanceRecord.fromMap(map)).toList();
  }

  // Get attendance record with lecture filter
  Future<AttendanceRecord?> getAttendanceRecordWithLecture(int studentId, String date, String? lecture, {String? timeSlot}) async {
    final db = await instance.database;
    String whereClause = 'student_id = ? AND date = ?';
    List<dynamic> whereArgs = [studentId, date];

    if (lecture != null && lecture.isNotEmpty) {
      whereClause += ' AND lecture = ?';
      whereArgs.add(lecture);
    }

    if (timeSlot != null && timeSlot.isNotEmpty) {
      whereClause += ' AND time_slot = ?';
      whereArgs.add(timeSlot);
    }

    final result = await db.query(
      'attendance',
      where: whereClause,
      whereArgs: whereArgs,
    );

    if (result.isNotEmpty) {
      return AttendanceRecord.fromMap(result.first);
    }
    return null;
  }

  Future<List<AttendanceRecord>> getAttendanceByStudent(int studentId) async {
    final db = await instance.database;
    final result = await db.query(
      'attendance',
      where: 'student_id = ?',
      whereArgs: [studentId],
      orderBy: 'date DESC',
    );
    return result.map((map) => AttendanceRecord.fromMap(map)).toList();
  }

  Future<List<AttendanceRecord>> getAttendanceByDateRange(String fromDate, String toDate) async {
    final db = await instance.database;
    final result = await db.query(
      'attendance',
      where: 'date >= ? AND date <= ?',
      whereArgs: [fromDate, toDate],
      orderBy: 'date DESC',
    );
    return result.map((map) => AttendanceRecord.fromMap(map)).toList();
  }

  Future<AttendanceRecord?> getAttendanceRecord(int studentId, String date) async {
    final db = await instance.database;
    final result = await db.query(
      'attendance',
      where: 'student_id = ? AND date = ?',
      whereArgs: [studentId, date],
    );

    if (result.isNotEmpty) {
      return AttendanceRecord.fromMap(result.first);
    }
    return null;
  }

  Future<int> updateAttendance(AttendanceRecord attendance) async {
    final db = await instance.database;
    final now = DateTime.now().toIso8601String();

    final updatedMap = attendance.toMap();
    updatedMap['updated_at'] = now;

    return await db.update(
      'attendance',
      updatedMap,
      where: 'id = ?',
      whereArgs: [attendance.id],
    );
  }

  // Check if roll number exists
  Future<bool> isRollNumberExists(String rollNumber, {int? excludeId}) async {
    final db = await instance.database;
    String whereClause = 'roll_number = ?';
    List<dynamic> whereArgs = [rollNumber.trim().toUpperCase()];

    if (excludeId != null) {
      whereClause += ' AND id != ?';
      whereArgs.add(excludeId);
    }

    final result = await db.query(
      'students',
      where: whereClause,
      whereArgs: whereArgs,
    );

    return result.isNotEmpty;
  }

  // Utility methods for dropdowns
  List<int> getSemesters() {
    return [1, 2, 3, 4, 5, 6, 7, 8];
  }

  List<String> getDepartments() {
    return ['CE/IT', 'EC', 'ME', 'CS'];
  }

  List<String> getIndividualDepartments() {
    return ['CE', 'IT', 'EC', 'ME', 'CS'];
  }

  List<String> getCombinedDepartments() {
    return ['CE/IT', 'EC', 'ME', 'CS'];
  }

  List<String> getDivisions() {
    return ['A', 'B', 'C', 'D'];
  }

  // Return unique class combinations present in students table as a list of maps { 'semester': int, 'department': String, 'division': String }
  Future<List<Map<String, dynamic>>> getClassCombinations() async {
    final db = await database;
    try {
      // Query both 'classes' and 'divisions' collections to ensure compatibility
      final result = await db.rawQuery(
        'SELECT DISTINCT semester, department, division FROM students ORDER BY semester, department, division'
      );

      if (result.isEmpty) {
        print('No class combinations found in the database.');
        return [];
      }

      print('Class combinations query result: $result');

      return result.map((r) => {
        'semester': (r['semester'] is int) ? r['semester'] as int : int.tryParse('${r['semester']}') ?? 0,
        'department': r['department']?.toString() ?? '',
        'division': r['division']?.toString() ?? '',
        'class': r['division']?.toString() ?? '', // Alias 'division' as 'class' for compatibility
      }).toList();
    } catch (e) {
      print('Error fetching class combinations: $e');
      return [];
    }
  }

  // Upsert a batch of students into local DB.
  // For each student: if enrollment_number (non-empty) matches an existing row, update it.
  // Otherwise, match by roll_number. Returns the list of students with assigned local IDs.
  Future<List<Student>> upsertStudents(List<Student> students) async {
    if (students.isEmpty) return [];
    final db = await database;
    final List<Student> result = [];

    await db.transaction((txn) async {
      for (final s in students) {
        try {
          final enroll = s.enrollmentNumber.trim().toUpperCase();
          final roll = s.rollNumber.trim().toUpperCase();

          // Try to find existing by enrollment_number first (when present and non-empty)
          List<Map<String, Object?>> existing = [];
          if (enroll.isNotEmpty) {
            existing = await txn.query('students', where: 'enrollment_number = ?', whereArgs: [enroll], limit: 1);
          }

          // If not found by enrollment, try by roll_number
          if (existing.isEmpty) {
            existing = await txn.query('students', where: 'roll_number = ?', whereArgs: [roll], limit: 1);
          }

          if (existing.isNotEmpty) {
            // Update existing
            final row = existing.first;
            final int id = row['id'] as int;
            final map = s.toMap();
            map.remove('id');
            await txn.update('students', map, where: 'id = ?', whereArgs: [id]);
            result.add(s.copyWith(id: id));
          } else {
            // Insert new
            final map = s.toMap();
            map.remove('id');
            final int id = await txn.insert('students', map);
            result.add(s.copyWith(id: id));
          }
        } catch (e) {
          print('upsertStudents: failed for ${s.rollNumber} / ${s.enrollmentNumber}: $e');
        }
      }
    });

    return result;
  }

  // ---------------------------------------------------------------------------
  // Reporting / statistics helpers
  // ---------------------------------------------------------------------------

  /// Return aggregate attendance stats for a single student within a date range.
  /// Result map contains: { 'total': int, 'present': int, 'absent': int, 'percentage': double }
  Future<Map<String, dynamic>> getStudentAttendanceStats(int studentId, String fromDate, String toDate) async {
    final db = await database;

    try {
      final result = await db.rawQuery('''
        SELECT
          COUNT(*) as total,
          SUM(CASE WHEN is_present = 1 THEN 1 ELSE 0 END) as present
        FROM attendance
        WHERE student_id = ? AND date >= ? AND date <= ?
      ''', [studentId, fromDate, toDate]);

      if (result.isEmpty) {
        return { 'total': 0, 'present': 0, 'absent': 0, 'percentage': 0.0 };
      }

      final row = result.first;
      final total = (row['total'] is int) ? row['total'] as int : int.tryParse('${row['total']}') ?? 0;
      final present = (row['present'] is int) ? row['present'] as int : int.tryParse('${row['present']}') ?? 0;
      final absent = total - present;
      final percentage = total > 0 ? (present / total * 100) : 0.0;

      return { 'total': total, 'present': present, 'absent': absent, 'percentage': percentage };
    } catch (e) {
      print('getStudentAttendanceStats error: $e');
      return { 'total': 0, 'present': 0, 'absent': 0, 'percentage': 0.0 };
    }
  }

  /// Count present students from a list of student IDs for a given date and lecture.
  /// Returns 0 if ids list is empty. Lecture can be null or empty to ignore lecture filter.
  Future<int> countPresentByStudentIdsAndDateAndLecture(List<int> ids, String date, String? lecture) async {
    if (ids.isEmpty) return 0;
    final db = await database;

    try {
      final placeholders = List.filled(ids.length, '?').join(',');
      final args = <dynamic>[];
      args.addAll(ids);
      args.add(date);

      String lectureCondition = '';
      if (lecture != null && lecture.isNotEmpty) {
        lectureCondition = ' AND lecture = ?';
        args.add(lecture);
      }

      final sql = 'SELECT COUNT(*) as cnt FROM attendance WHERE student_id IN ($placeholders) AND date = ? AND is_present = 1$lectureCondition';
      final result = await db.rawQuery(sql, args);
      if (result.isEmpty) return 0;
      final val = result.first['cnt'];
      return (val is int) ? val : int.tryParse('$val') ?? 0;
    } catch (e) {
      print('countPresentByStudentIdsAndDateAndLecture error: $e');
      return 0;
    }
  }

  // Fetch users by role from the database
  Future<List<Map<String, dynamic>>> getUsersByRole(String role) async {
    final db = await database;
    final result = await db.query(
      'users',
      where: 'role = ?',
      whereArgs: [role],
    );
    return result;
  }

  Future<void> updateUserClasses(String email, List<String> newClasses) async {
    final db = await instance.database;

    // Convert the list of classes to a JSON string for storage
    final classesJson = newClasses.join(',');

    // Update the user's classes in the database
    await db.update(
      'users',
      {'classes': classesJson},
      where: 'email = ?',
      whereArgs: [email],
    );
  }

  Future<void> ensureUsersTableHasClassesColumn() async {
    final db = await instance.database;

    // Check if the 'classes' column exists in the 'users' table
    final columnExists = await db.rawQuery(
      "PRAGMA table_info('users')",
    ).then((columns) => columns.any((column) => column['name'] == 'classes'));

    if (!columnExists) {
      // Add the 'classes' column if it doesn't exist
      await db.execute("ALTER TABLE users ADD COLUMN classes TEXT");
    }
  }

  Future<void> syncAttendanceFromFirestore() async {
    final db = await instance.database;
    final firestore = FirebaseFirestore.instance;

    try {
      final snapshot = await firestore.collection('attendance').get();
      final batch = db.batch();

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final attendance = AttendanceRecord(
          id: data['id'],
          studentId: data['student_id'],
          date: DateTime.parse(data['date']),
          isPresent: data['is_present'],
          notes: data['notes'],
          lecture: data['lecture'],
          timeSlot: data['time_slot'],
        );

        batch.insert('attendance', attendance.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
      }

      await batch.commit();
    } catch (e) {
      if (kDebugMode) print('Error syncing attendance from Firestore: $e');
    }
  }
}
