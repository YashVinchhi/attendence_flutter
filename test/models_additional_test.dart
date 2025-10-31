import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/models/models.dart';
import 'package:myapp/utils/token_generator.dart';

void main() {
  group('Models additional tests', () {
    test('TokenGenerator generates string of requested length and allowed chars', () {
      final token = TokenGenerator.generate(24);
      expect(token.length, 24);
      expect(RegExp(r'^[A-Za-z0-9]+$').hasMatch(token), true);
    });

    test('ValidationHelper allows roll numbers with colon and slash', () {
      expect(ValidationHelper.isValidRollNumber('CE-B:01'), true);
      expect(ValidationHelper.isValidRollNumber('3CE/IT-B'), true);
      expect(ValidationHelper.isValidRollNumber('INVALID@ROLL'), false);
    });

    test('AppUser.fromMap parses allowed_classes provided as structured maps', () {
      final map = {
        'uid': 'u123',
        'email': 'test@example.com',
        'name': 'Tester',
        'role': 'CC',
        'allowed_classes': [
          {'semester': 3, 'department': 'CE', 'division': 'B'},
          {'semester': 4, 'department': 'IT', 'division': 'A'},
        ],
      };

      final user = AppUser.fromMap(map);
      expect(user.allowedClasses.length, 2);
      expect(user.allowedClasses[0].semester, 3);
      expect(user.allowedClasses[0].department, 'CE');
      expect(user.allowedClasses[0].division, 'B');
    });

    test('AppUser.fromMap parses allowed_classes provided as strings in common patterns', () {
      final map = {
        'uid': 'u456',
        'email': 'x@example.com',
        'name': 'X',
        'role': 'CR',
        'allowed_classes': ['3CE-B', '4IT-A']
      };

      final user = AppUser.fromMap(map);
      expect(user.allowedClasses.length, 2);
      expect(user.allowedClasses[0].semester, 3);
      expect(user.allowedClasses[0].department.toUpperCase(), contains('CE'));
      expect(user.allowedClasses[0].division, isNotEmpty);
    });

    test('InviteToken constructor rejects past expiry dates', () {
      expect(() => InviteToken(
        token: 'abc',
        invitedEmail: 'inv@example.com',
        role: UserRole.CC,
        expiresAt: DateTime.now().subtract(Duration(days: 1)),
        createdByUid: 'u',
      ), throwsA(isA<ArgumentError>()));
    });
  });
}
