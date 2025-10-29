import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

    return await openDatabase(
      path,
      version: 4, // Incremented version to trigger migration for lecture field
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
    );
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
    if (oldVersion < 2) {
      // Migration from version 1 to 2
      // Drop existing tables and recreate with proper schema
      await db.execute('DROP TABLE IF EXISTS attendance');
      await db.execute('DROP TABLE IF EXISTS students');

      // Recreate tables with correct schema
      await _createDB(db, newVersion);
    } else if (oldVersion < 3) {
      // Migration from version 2 to 3
      // Add lecture field to attendance table
      await db.execute('ALTER TABLE attendance ADD COLUMN lecture TEXT');
      await db.execute('ALTER TABLE attendance ADD COLUMN created_at TEXT');
      await db.execute('ALTER TABLE attendance ADD COLUMN updated_at TEXT');
      await db.execute('CREATE INDEX idx_attendance_lecture ON attendance(lecture)');
    } else if (oldVersion < 4) {
      // Add time_slot column if it doesn't exist
      await db.execute('ALTER TABLE students ADD COLUMN time_slot TEXT NOT NULL DEFAULT "8:00-8:50"');
    }
  }

  // Load sample data for testing
  Future<void> loadSampleData() async {
    try {
      final db = await database;

      // Check if we already have students
      final existingStudents = await db.query('students', limit: 1);
      if (existingStudents.isNotEmpty) {
        print('Sample data already loaded, skipping...');
        return;
      }

      // Check if user has previously cleared data - if so, don't auto-load sample data
      final prefs = await SharedPreferences.getInstance();
      final hasUserClearedData = prefs.getBool('user_cleared_data') ?? false;

      if (hasUserClearedData) {
        print('User has cleared data, not loading sample data automatically');
        return;
      }

      print('Loading sample data from CEIT-B.csv...');

      // Sample data for CEIT-B (3rd semester, Division B)
      final sampleStudents = [
        // CE Students
        {'name': 'KANJARIYA VAISHALIBEN BHIKHABHAI', 'rollNumber': 'CE-B:01', 'semester': 3, 'department': 'CE', 'division': 'B'},
        {'name': 'ASODARIYA HETAL MUKESHBHAI', 'rollNumber': 'CE-B:02', 'semester': 3, 'department': 'CE', 'division': 'B'},
        {'name': 'BARASIYA MEET JAYANTIBHAI', 'rollNumber': 'CE-B:03', 'semester': 3, 'department': 'CE', 'division': 'B'},
        {'name': 'BHESANIYA HENSI RAMESHBHAI', 'rollNumber': 'CE-B:04', 'semester': 3, 'department': 'CE', 'division': 'B'},
        {'name': 'DHADUK DHYEY BHAVINBHAI', 'rollNumber': 'CE-B:05', 'semester': 3, 'department': 'CE', 'division': 'B'},
        {'name': 'DUDHATRA ISHA PANKAJBHAI', 'rollNumber': 'CE-B:06', 'semester': 3, 'department': 'CE', 'division': 'B'},
        {'name': 'HIRANI AASHKA', 'rollNumber': 'CE-B:07', 'semester': 3, 'department': 'CE', 'division': 'B'},
        {'name': 'KADIVAR MUSKANBANU MUSTUFA', 'rollNumber': 'CE-B:08', 'semester': 3, 'department': 'CE', 'division': 'B'},
        {'name': 'KANSAGARA MANAV AJAYBHAI', 'rollNumber': 'CE-B:09', 'semester': 3, 'department': 'CE', 'division': 'B'},
        {'name': 'KARANGIYA BHAVIN VIJAYBHAI', 'rollNumber': 'CE-B:10', 'semester': 3, 'department': 'CE', 'division': 'B'},
        {'name': 'KOTHIVAR ARJUN NATVARBHAI', 'rollNumber': 'CE-B:11', 'semester': 3, 'department': 'CE', 'division': 'B'},
        {'name': 'LIMBASIYA DEV RAJESHBHAI', 'rollNumber': 'CE-B:12', 'semester': 3, 'department': 'CE', 'division': 'B'},
        {'name': 'MANEK DARSH NILESHBHAI', 'rollNumber': 'CE-B:13', 'semester': 3, 'department': 'CE', 'division': 'B'},
        {'name': 'NAKUM DIVYA SHAILESHBHAI', 'rollNumber': 'CE-B:14', 'semester': 3, 'department': 'CE', 'division': 'B'},
        {'name': 'NANERA UDAY MUKESHBHAI', 'rollNumber': 'CE-B:15', 'semester': 3, 'department': 'CE', 'division': 'B'},
        {'name': 'NIMAVAT DISHA HITESHBHAI', 'rollNumber': 'CE-B:16', 'semester': 3, 'department': 'CE', 'division': 'B'},
        {'name': 'PADHIYAR JAYRAJSINH SURUBHA', 'rollNumber': 'CE-B:17', 'semester': 3, 'department': 'CE', 'division': 'B'},
        {'name': 'PANARA TARUN MAHENDRABHAI', 'rollNumber': 'CE-B:18', 'semester': 3, 'department': 'CE', 'division': 'B'},
        {'name': 'PATAL DIPAK GANGABHAI', 'rollNumber': 'CE-B:19', 'semester': 3, 'department': 'CE', 'division': 'B'},
        {'name': 'POKAL KRISH', 'rollNumber': 'CE-B:20', 'semester': 3, 'department': 'CE', 'division': 'B'},
        {'name': 'RAMANI MANSI DAMJIBHAI', 'rollNumber': 'CE-B:21', 'semester': 3, 'department': 'CE', 'division': 'B'},
        {'name': 'SADADIYA PRIYANSHU DILIPBHAI', 'rollNumber': 'CE-B:22', 'semester': 3, 'department': 'CE', 'division': 'B'},
        {'name': 'SANGANI DHRUVKUMAR KANTILAL', 'rollNumber': 'CE-B:23', 'semester': 3, 'department': 'CE', 'division': 'B'},
        {'name': 'SANYAJA TIRTH KALPESHBHAI', 'rollNumber': 'CE-B:24', 'semester': 3, 'department': 'CE', 'division': 'B'},
        {'name': 'SARENA VISHALKUAMAR PRAKASHBHAI', 'rollNumber': 'CE-B:25', 'semester': 3, 'department': 'CE', 'division': 'B'},
        {'name': 'SAVALIYA BINAL BHARATBHAI', 'rollNumber': 'CE-B:26', 'semester': 3, 'department': 'CE', 'division': 'B'},
        {'name': 'SOLANKI KINJALBEN SANJAYBHAI', 'rollNumber': 'CE-B:27', 'semester': 3, 'department': 'CE', 'division': 'B'},
        {'name': 'SUTARIYA TEJASKUMAR NARESHBHAI', 'rollNumber': 'CE-B:28', 'semester': 3, 'department': 'CE', 'division': 'B'},
        {'name': 'TAGADIYA KRISH DAMJIBHAI', 'rollNumber': 'CE-B:29', 'semester': 3, 'department': 'CE', 'division': 'B'},
        {'name': 'TRAPASIYA JENSHI RASIKBHAI', 'rollNumber': 'CE-B:30', 'semester': 3, 'department': 'CE', 'division': 'B'},
        {'name': 'VAGHELA SHAKTISINH KIRITSINH', 'rollNumber': 'CE-B:31', 'semester': 3, 'department': 'CE', 'division': 'B'},
        {'name': 'VARMORA DHARM PRAKASHBHAI', 'rollNumber': 'CE-B:32', 'semester': 3, 'department': 'CE', 'division': 'B'},
        {'name': 'VEKARIYA VATSAL RAKESHBHAI', 'rollNumber': 'CE-B:33', 'semester': 3, 'department': 'CE', 'division': 'B'},
        {'name': 'VINCHHI YASH HEMENDRABHAI', 'rollNumber': 'CE-B:34', 'semester': 3, 'department': 'CE', 'division': 'B'},
        {'name': 'VIRADIYA DHRUTI PRAVINBHAI', 'rollNumber': 'CE-B:35', 'semester': 3, 'department': 'CE', 'division': 'B'},
        {'name': 'MEET DESAI', 'rollNumber': 'CE-B:36', 'semester': 3, 'department': 'CE', 'division': 'B'},
        {'name': 'JANI VISHESH RAKESHKUMAR', 'rollNumber': 'CE-B:37', 'semester': 3, 'department': 'CE', 'division': 'B'},
        {'name': 'SHEIKH RAJIBUL ABBASUDDIN', 'rollNumber': 'CE-B:38', 'semester': 3, 'department': 'CE', 'division': 'B'},
        {'name': 'SOLANKI RAHIL AMITBHAI', 'rollNumber': 'CE-B:39', 'semester': 3, 'department': 'CE', 'division': 'B'},
        {'name': 'PRAJAPATI VIRAL VINODBHAI', 'rollNumber': 'CE-B:40', 'semester': 3, 'department': 'CE', 'division': 'B'},
        {'name': 'DOBARIYA DHRUMIT BHIKHALAL', 'rollNumber': 'CE-B:41', 'semester': 3, 'department': 'CE', 'division': 'B'},
        {'name': 'DOBARIYA HETVI RAJESHBHAI', 'rollNumber': 'CE-B:42', 'semester': 3, 'department': 'CE', 'division': 'B'},
        {'name': 'METALIYA KANHAI DIPAKBHAI', 'rollNumber': 'CE-B:43', 'semester': 3, 'department': 'CE', 'division': 'B'},
        {'name': 'GORASIYA DEEPKUMAR JAYESHBHAI', 'rollNumber': 'CE-B:44', 'semester': 3, 'department': 'CE', 'division': 'B'},
        {'name': 'DHRUVIL KHUNT', 'rollNumber': 'CE-B:45', 'semester': 3, 'department': 'CE', 'division': 'B'},
        {'name': 'CHIRAG KISHAN FOFANDI', 'rollNumber': 'CE-B:46', 'semester': 3, 'department': 'CE', 'division': 'B'},
        {'name': 'DHANKECHA MANTHAN VIPULBHAI', 'rollNumber': 'CE-B:47', 'semester': 3, 'department': 'CE', 'division': 'B'},
        {'name': 'TOGADIYA VINAY KALPESHBHAI', 'rollNumber': 'CE-B:48', 'semester': 3, 'department': 'CE', 'division': 'B'},
        {'name': 'DOBARIYA HARSHAL JAGDISHBHAI', 'rollNumber': 'CE-B:49', 'semester': 3, 'department': 'CE', 'division': 'B'},
        {'name': 'BAGDA MAHEK DILIPBHAI', 'rollNumber': 'CE-B:50', 'semester': 3, 'department': 'CE', 'division': 'B'},
        {'name': 'FENIL PIPROTAR', 'rollNumber': 'CE-B:51', 'semester': 3, 'department': 'CE', 'division': 'B'},

        // IT Students
        {'name': 'BHALIYA GAURAVBHAI MAVJIBHAI', 'rollNumber': 'IT-B:01', 'semester': 3, 'department': 'IT', 'division': 'B'},
        {'name': 'DUDHAIYA RACHIT VIPULBHAI', 'rollNumber': 'IT-B:02', 'semester': 3, 'department': 'IT', 'division': 'B'},
        {'name': 'JAVIYA ARYAN RAKESHBHAI', 'rollNumber': 'IT-B:03', 'semester': 3, 'department': 'IT', 'division': 'B'},
        {'name': 'KAIDA MOHMADREHAN SIRAJBHAI', 'rollNumber': 'IT-B:04', 'semester': 3, 'department': 'IT', 'division': 'B'},
        {'name': 'KANANI JENISH VINODBHAI', 'rollNumber': 'IT-B:05', 'semester': 3, 'department': 'IT', 'division': 'B'},
        {'name': 'KATHROTIYA HET RAMESHBHAI', 'rollNumber': 'IT-B:06', 'semester': 3, 'department': 'IT', 'division': 'B'},
        {'name': 'KHATRA VRUDANT VIJAYBHAI', 'rollNumber': 'IT-B:07', 'semester': 3, 'department': 'IT', 'division': 'B'},
        {'name': 'PARASARA MUFIZ JAHIDABBAS', 'rollNumber': 'IT-B:08', 'semester': 3, 'department': 'IT', 'division': 'B'},
        {'name': 'PATALIYA NILESH MANOJBHAI', 'rollNumber': 'IT-B:09', 'semester': 3, 'department': 'IT', 'division': 'B'},
        {'name': 'RAMANI HET VIPULKUMA', 'rollNumber': 'IT-B:10', 'semester': 3, 'department': 'IT', 'division': 'B'},
        {'name': 'RAVAL MINAL PANKAJBHAI', 'rollNumber': 'IT-B:11', 'semester': 3, 'department': 'IT', 'division': 'B'},
        {'name': 'SONAGARA DEVAL RAMESHBHAI', 'rollNumber': 'IT-B:12', 'semester': 3, 'department': 'IT', 'division': 'B'},
        {'name': 'NANERA MILAN', 'rollNumber': 'IT-B:13', 'semester': 3, 'department': 'IT', 'division': 'B'},
        {'name': 'RAIJADA JEETRAJSINH KRISHNENDRASINH', 'rollNumber': 'IT-B:14', 'semester': 3, 'department': 'IT', 'division': 'B'},
        {'name': 'KOYANI SMIT HITESHKUMAR', 'rollNumber': 'IT-B:15', 'semester': 3, 'department': 'IT', 'division': 'B'},
        {'name': 'PRINCE KAMLESH PARMAR', 'rollNumber': 'IT-B:16', 'semester': 3, 'department': 'IT', 'division': 'B'},
      ];

      // Insert sample students using transaction for atomicity
      await db.transaction((txn) async {
        for (final studentData in sampleStudents) {
          final student = Student(
            name: studentData['name']! as String,
            rollNumber: studentData['rollNumber']! as String,
            semester: studentData['semester']! as int,
            department: studentData['department']! as String,
            division: studentData['division']! as String,
            timeSlot: '8:00-8:50', // Default time slot for sample data
          );

          await txn.insert('students', student.toMap());
        }
      });

      print('Successfully loaded ${sampleStudents.length} sample students (CEIT-B)');
    } catch (e) {
      print('Error loading sample data: $e');
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
  Future<List<AttendanceRecord>> getAttendanceByDateAndLecture(String date, String? lecture) async {
    final db = await instance.database;
    String whereClause = 'date = ?';
    List<dynamic> whereArgs = [date];

    if (lecture != null && lecture.isNotEmpty) {
      whereClause += ' AND lecture = ?';
      whereArgs.add(lecture);
    }

    final result = await db.query(
      'attendance',
      where: whereClause,
      whereArgs: whereArgs,
    );
    return result.map((map) => AttendanceRecord.fromMap(map)).toList();
  }

  // Get attendance record with lecture filter
  Future<AttendanceRecord?> getAttendanceRecordWithLecture(int studentId, String date, String? lecture) async {
    final db = await instance.database;
    String whereClause = 'student_id = ? AND date = ?';
    List<dynamic> whereArgs = [studentId, date];

    if (lecture != null && lecture.isNotEmpty) {
      whereClause += ' AND lecture = ?';
      whereArgs.add(lecture);
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

  // Get common lectures/subjects for different semesters and departments
  List<String> getLectures(int semester, String department) {
    Map<String, List<String>> lecturesByDept = {
      'CE': [
        'DCN (Parita ma\'am)',
        'DS (Janki ma\'am)',
        'Maths (Purvangi ma\'am)',
        'Maths (MMP sir)',
        'ADBMS (Nikunj sir)',
        'OOP (Neha ma\'am)',
        'OOP (Twinkle ma\'am)',
      ],
      'IT': [
        'DCN (Parita ma\'am)',
        'DS (Janki ma\'am)',
        'Maths (Purvangi ma\'am)',
        'Maths (MMP sir)',
        'ADBMS (Nikunj sir)',
        'OOP (Neha ma\'am)',
        'OOP (Twinkle ma\'am)',
      ],
      'CE/IT': [
        'DCN (Parita ma\'am)',
        'DS (Janki ma\'am)',
        'Maths (Purvangi ma\'am)',
        'Maths (MMP sir)',
        'ADBMS (Nikunj sir)',
        'OOP (Neha ma\'am)',
        'OOP (Twinkle ma\'am)',
      ],
      'EC': [
        'Digital Electronics',
        'Analog Electronics',
        'Signal Processing',
        'Communication Systems',
        'Microprocessors',
        'Control Systems',
        'Mathematics',
        'English',
      ],
      'ME': [
        'Thermodynamics',
        'Fluid Mechanics',
        'Machine Design',
        'Manufacturing Process',
        'Heat Transfer',
        'Material Science',
        'Mathematics',
        'English',
      ],
      'CS': [
        'Data Structures',
        'Algorithms',
        'Database Systems',
        'Software Engineering',
        'Computer Networks',
        'Operating Systems',
        'Programming Languages',
        'Mathematics',
        'English',
      ],
    };

    return lecturesByDept[department] ?? ['General Lecture'];
  }

  // Statistics methods
  Future<Map<String, dynamic>> getStudentAttendanceStats(int studentId, String fromDate, String toDate) async {
    final db = await instance.database;
    final result = await db.rawQuery('''
      SELECT 
        COUNT(*) as total,
        SUM(CASE WHEN is_present = 1 THEN 1 ELSE 0 END) as present,
        SUM(CASE WHEN is_present = 0 THEN 1 ELSE 0 END) as absent
      FROM attendance
      WHERE student_id = ? AND date >= ? AND date <= ?
    ''', [studentId, fromDate, toDate]);

    final data = result.first;
    final total = data['total'] as int;
    final present = data['present'] as int;
    final absent = data['absent'] as int;
    final percentage = total > 0 ? (present / total) * 100 : 0.0;

    return {
      'total': total,
      'present': present,
      'absent': absent,
      'percentage': percentage,
    };
  }

  // Normalize attendance lecture field for a specific date
  // If lecture column contains only subject (e.g., 'DCN') or is empty,
  // try to infer lecture number from the student's time_slot and update
  // lecture to the format 'SUBJECT - Lecture N'. Returns number of rows updated.
  Future<int> normalizeAttendanceLectures(String date) async {
    final db = await instance.database;
    int updatedCount = 0;

    final rows = await db.query(
      'attendance',
      where: 'date = ?',
      whereArgs: [date],
    );

    for (var row in rows) {
      final int id = row['id'] as int;
      final String? lectureField = row['lecture'] as String?;
      final int studentId = row['student_id'] as int;

      if (lectureField == null || lectureField.trim().isEmpty) {
        // nothing to infer
        continue;
      }

      // If already in 'SUBJECT - Lecture N' format, skip
      if (lectureField.contains(' - Lecture ')) continue;

      // lectureField may already be subject like 'DCN' or 'DS'
      final subject = lectureField.trim();

      // Get student's time_slot
      final studentRows = await db.query(
        'students',
        columns: ['time_slot'],
        where: 'id = ?',
        whereArgs: [studentId],
        limit: 1,
      );

      String lectureSlot = '';
      if (studentRows.isNotEmpty) {
        lectureSlot = (studentRows.first['time_slot'] as String?) ?? '';
      }

      int lectureNum = -1;
      switch (lectureSlot) {
        case '8:00-8:50':
          lectureNum = 1;
          break;
        case '8:50-9:45':
          lectureNum = 2;
          break;
        case '10:00-10:50':
          lectureNum = 3;
          break;
        case '10:50-11:40':
          lectureNum = 4;
          break;
        default:
          lectureNum = -1;
      }

      // If we could infer lecture number, update the attendance row
      if (lectureNum > 0) {
        final newLecture = '$subject - Lecture $lectureNum';
        final updated = await db.update(
          'attendance',
          {'lecture': newLecture},
          where: 'id = ?',
          whereArgs: [id],
        );
        if (updated > 0) updatedCount += updated;
      }
    }

    return updatedCount;
  }

  Future<void> close() async {
    final db = await instance.database;
    await db.close();
  }

  // Clear all data methods
  Future<void> clearAllStudents() async {
    final db = await instance.database;
    await db.delete('students');
  }

  Future<void> clearAllAttendance() async {
    final db = await instance.database;
    await db.delete('attendance');
  }
}
