import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/providers/student_provider.dart';
import 'package:myapp/services/database_helper.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  group('StudentProvider CSV import tests', () {
    setUpAll(() async {
      // Initialize ffi implementation for sqflite in Dart VM tests
      sqfliteFfiInit();
      DatabaseFactory? databaseFactoryFfi;
      databaseFactory = databaseFactoryFfi;
    });

    setUp(() async {
      await DatabaseHelper.instance.clearAllData();
    });

    tearDown(() async {
      await DatabaseHelper.instance.clearAllData();
    });

    test('bulk import adds students from well-formed CSV', () async {
      final provider = StudentProvider();
      const csv = '''
Name,Roll,Semester,Department,Division
John Doe,CE-B:01,3,CE,B
Jane Roe,IT-B:02,3,IT,B
''';
      final res = await provider.bulkImportFromCsv(csv);
      expect(res['success'], true);
      expect(res['imported'], 2);
      final foundJohn = await provider.searchStudents('John');
      final foundJane = await provider.searchStudents('Jane');
      expect(foundJohn.length, 1);
      expect(foundJohn.first.rollNumber, 'CE-B:01');
      expect(foundJane.length, 1);
      expect(foundJane.first.rollNumber, 'IT-B:02');
    });

    test('duplicate roll numbers in same CSV are reported and only one inserted', () async {
      final provider = StudentProvider();
      const csv = '''
Name,Roll,Semester,Department,Division
Alice,CE-B:10,3,CE,B
Alice Dup,CE-B:10,3,CE,B
''';
      final res = await provider.bulkImportFromCsv(csv);
      expect(res['success'], true);
      expect(res['imported'], 1);
      expect((res['errors'] as List).isNotEmpty, true);
      final found = await provider.searchStudents('Alice');
      expect(found.length, 1);
      expect(found.first.rollNumber, 'CE-B:10');
    });

    test('format B rows with roll then name parse correctly and default semester/department applied', () async {
      final provider = StudentProvider();
      const csv = 'CE-B:03,Mark Twain\n';
      final res = await provider.bulkImportFromCsv(csv);
      expect(res['success'], true);
      expect(res['imported'], 1);
      final found = await provider.searchStudents('Mark');
      expect(found.length, 1);
      final student = found.first;
      expect(student.rollNumber, 'CE-B:03');
      expect(student.semester, 3);
      expect(student.department, 'CE');
      expect(student.division, 'B');
    });

    test('rows with invalid semester are skipped and import reports error with no insert', () async {
      final provider = StudentProvider();
      const csv = '''
Name,Roll,Semester,Department,Division
Bad Sem,CE-B:20,9,CE,B
''';
      final res = await provider.bulkImportFromCsv(csv);
      expect(res['success'], false);
      expect(res['imported'], 0);
      expect((res['errors'] as List).isNotEmpty, true);
      final found = await provider.searchStudents('Bad Sem');
      expect(found.length, 0);
    });
  });
}

void sqfliteFfiInit() {
}
