import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/models/models.dart';

void main() {
  group('Student Model Tests', () {
    test('should create a valid student', () {
      final student = Student(
        name: 'John Doe',
        rollNumber: 'CS001',
        semester: 3,
        department: 'CS',
        division: 'A',
        timeSlot: '8:00-8:50',
      );

      expect(student.name, 'John Doe');
      expect(student.rollNumber, 'CS001');
      expect(student.semester, 3);
      expect(student.department, 'CS');
      expect(student.division, 'A');
    });

    test('should throw error for invalid semester', () {
      expect(
        () => Student(
          name: 'John Doe',
          rollNumber: 'CS001',
          semester: 9, // Invalid semester
          department: 'CS',
          division: 'A',
          timeSlot: '8:00-8:50',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('should throw error for empty name', () {
      expect(
        () => Student(
          name: '', // Empty name
          rollNumber: 'CS001',
          semester: 3,
          department: 'CS',
          division: 'A',
          timeSlot: '8:00-8:50',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('should throw error for empty roll number', () {
      expect(
        () => Student(
          name: 'John Doe',
          rollNumber: '', // Empty roll number
          semester: 3,
          department: 'CS',
          division: 'A',
          timeSlot: '8:00-8:50',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('should convert to and from map correctly', () {
      final student = Student(
        id: 1,
        name: 'John Doe',
        rollNumber: 'CS001',
        semester: 3,
        department: 'CS',
        division: 'A',
        timeSlot: '8:00-8:50',
      );

      final map = student.toMap();
      final reconstructed = Student.fromMap(map);

      expect(reconstructed.id, student.id);
      expect(reconstructed.name, student.name);
      expect(reconstructed.rollNumber, student.rollNumber);
      expect(reconstructed.semester, student.semester);
      expect(reconstructed.department, student.department);
      expect(reconstructed.division, student.division);
    });

    test('should normalize data in toMap', () {
      final student = Student(
        name: '  john doe  ',
        rollNumber: '  cs001  ',
        semester: 3,
        department: '  cs  ',
        division: '  a  ',
        timeSlot: '8:00-8:50',
      );

      final map = student.toMap();

      expect(map['name'], 'john doe');
      expect(map['roll_number'], 'CS001');
      expect(map['department'], 'CS');
      expect(map['division'], 'A');
    });
  });

  group('AttendanceRecord Model Tests', () {
    test('should create a valid attendance record', () {
      final record = AttendanceRecord(
        studentId: 1,
        date: DateTime(2024, 1, 15),
        isPresent: true,
        notes: 'Present in class',
      );

      expect(record.studentId, 1);
      expect(record.date, DateTime(2024, 1, 15));
      expect(record.isPresent, true);
      expect(record.notes, 'Present in class');
    });

    test('should throw error for future date', () {
      final futureDate = DateTime.now().add(const Duration(days: 1));

      expect(
        () => AttendanceRecord(
          studentId: 1,
          date: futureDate,
          isPresent: true,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('should throw error for invalid student id', () {
      expect(
        () => AttendanceRecord(
          studentId: -1, // Invalid student ID
          date: DateTime(2024, 1, 15),
          isPresent: true,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('should convert to and from map correctly', () {
      final record = AttendanceRecord(
        id: 1,
        studentId: 1,
        date: DateTime(2024, 1, 15),
        isPresent: true,
        notes: 'Present in class',
      );

      final map = record.toMap();
      final reconstructed = AttendanceRecord.fromMap(map);

      expect(reconstructed.id, record.id);
      expect(reconstructed.studentId, record.studentId);
      expect(reconstructed.date.toIso8601String().substring(0, 10),
             record.date.toIso8601String().substring(0, 10));
      expect(reconstructed.isPresent, record.isPresent);
      expect(reconstructed.notes, record.notes);
    });
  });

  group('ValidationHelper Tests', () {
    test('should validate email correctly', () {
      expect(ValidationHelper.isValidEmail('test@example.com'), true);
      expect(ValidationHelper.isValidEmail('invalid-email'), false);
      expect(ValidationHelper.isValidEmail(''), false);
    });

    test('should validate roll number correctly', () {
      expect(ValidationHelper.isValidRollNumber('CS001'), true);
      expect(ValidationHelper.isValidRollNumber('CS-001'), true);
      expect(ValidationHelper.isValidRollNumber('CS_001'), true);
      expect(ValidationHelper.isValidRollNumber('CS@001'), false);
      expect(ValidationHelper.isValidRollNumber(''), false);
    });

    test('should validate name correctly', () {
      expect(ValidationHelper.isValidName('John Doe'), true);
      expect(ValidationHelper.isValidName("John O'Connor"), true);
      expect(ValidationHelper.isValidName('John-Doe'), true);
      expect(ValidationHelper.isValidName('John123'), false);
      expect(ValidationHelper.isValidName(''), false);
    });

    test('should sanitize input correctly', () {
      expect(ValidationHelper.sanitizeInput('  <script>alert("xss")</script>  '),
             'scriptalert(xss)/script');
      expect(ValidationHelper.sanitizeInput('Normal text'), 'Normal text');
      expect(ValidationHelper.sanitizeInput('Text with "quotes"'), 'Text with quotes');
    });

    test('should validate date range correctly', () {
      final today = DateTime.now();
      final yesterday = today.subtract(const Duration(days: 1));
      final tomorrow = today.add(const Duration(days: 1));

      expect(ValidationHelper.isValidDateRange(yesterday, today), true);
      expect(ValidationHelper.isValidDateRange(today, tomorrow), false);
      expect(ValidationHelper.isValidDateRange(tomorrow, today), false);
      expect(ValidationHelper.isValidDateRange(null, today), false);
    });
  });

  group('AttendanceData Tests', () {
    test('should create valid attendance data', () {
      final data = AttendanceData(
        total: 10,
        present: 8,
        absent: 2,
        percentage: 80.0,
      );

      expect(data.total, 10);
      expect(data.present, 8);
      expect(data.absent, 2);
      expect(data.percentage, 80.0);
    });

    test('should throw error for invalid data', () {
      expect(
        () => AttendanceData(
          total: 10,
          present: 8,
          absent: 3, // present + absent != total
          percentage: 80.0,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('should create from map correctly', () {
      final map = {
        'total': 10,
        'present': 8,
        'absent': 2,
      };

      final data = AttendanceData.fromMap(map);

      expect(data.total, 10);
      expect(data.present, 8);
      expect(data.absent, 2);
      expect(data.percentage, 80.0);
    });
  });

  group('ClassInfo Tests', () {
    test('should create valid class info', () {
      final classInfo = ClassInfo(
        semester: 3,
        department: 'CS',
        division: 'A',
      );

      expect(classInfo.semester, 3);
      expect(classInfo.department, 'CS');
      expect(classInfo.division, 'A');
      expect(classInfo.displayName, '3CS-A');
    });

    test('should throw error for invalid semester', () {
      expect(
        () => ClassInfo(
          semester: 9, // Invalid semester
          department: 'CS',
          division: 'A',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('should handle equality correctly', () {
      final class1 = ClassInfo(semester: 3, department: 'CS', division: 'A');
      final class2 = ClassInfo(semester: 3, department: 'cs', division: 'a');
      final class3 = ClassInfo(semester: 4, department: 'CS', division: 'A');

      expect(class1 == class2, true); // Case insensitive
      expect(class1 == class3, false);
    });
  });
}
