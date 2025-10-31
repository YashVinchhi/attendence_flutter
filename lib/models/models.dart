import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;

// Helper: parse created_at style fields from Firestore/SQLite sources.
DateTime _parseDateTime(dynamic v) {
  if (v == null) return DateTime.now();
  if (v is DateTime) return v;
  if (v is Timestamp) return v.toDate();
  if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
  if (v is double) return DateTime.fromMillisecondsSinceEpoch(v.toInt());
  if (v is String) {
    try {
      return DateTime.parse(v);
    } catch (_) {
      // try parsing as int string
      final n = int.tryParse(v);
      if (n != null) return DateTime.fromMillisecondsSinceEpoch(n);
    }
  }
  return DateTime.now();
}

DateTime? _parseDateTimeNullable(dynamic v) {
  if (v == null) return null;
  return _parseDateTime(v);
}

class Student {
  final int? id;
  final String name;
  final String rollNumber;
  final int semester;
  final String department;
  final String division;
  final String timeSlot;
  final String enrollmentNumber; // New field for primary key
  final DateTime createdAt;

  Student({
    this.id,
    required this.name,
    required this.rollNumber,
    required this.semester,
    required this.department,
    required this.division,
    required this.timeSlot,
    required this.enrollmentNumber, // Added enrollmentNumber
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now() {
    // Validation
    _validateStudent();
  }

  void _validateStudent() {
    if (name.trim().isEmpty) {
      throw ArgumentError('Student name cannot be empty');
    }
    if (rollNumber.trim().isEmpty) {
      throw ArgumentError('Roll number cannot be empty');
    }
    if (semester < 1 || semester > 8) {
      throw ArgumentError('Semester must be between 1 and 8');
    }
    if (department.trim().isEmpty) {
      throw ArgumentError('Department cannot be empty');
    }
    if (division.trim().isEmpty) {
      throw ArgumentError('Division cannot be empty');
    }

    // timeSlot is optional in CSV import; do not require non-empty value here.

    // Validate roll number format (alphanumeric, max length)
    if (rollNumber.length > 20) {
      throw ArgumentError('Roll number cannot exceed 20 characters');
    }

    // Validate name length
    if (name.length > 100) {
      throw ArgumentError('Name cannot exceed 100 characters');
    }
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name.trim(),
      'roll_number': rollNumber.trim().toUpperCase(),
      'semester': semester,
      'department': department.trim().toUpperCase(),
      'division': division.trim().toUpperCase(),
      'time_slot': timeSlot,
      'enrollment_number': enrollmentNumber.trim().toUpperCase(), // Include in map
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory Student.fromMap(Map<String, dynamic> map) {
    return Student(
      id: map['id'],
      name: map['name'] ?? '',
      rollNumber: map['roll_number'] ?? '',
      semester: map['semester'] ?? 1,
      department: map['department'] ?? '',
      division: map['division'] ?? '',
      timeSlot: map['time_slot'] ?? '',
      enrollmentNumber: map['enrollment_number'] ?? '', // Parse enrollment number
      createdAt: _parseDateTime(map['created_at']),
    );
  }

  Student copyWith({
    int? id,
    String? name,
    String? rollNumber,
    int? semester,
    String? department,
    String? division,
    String? timeSlot,
    String? enrollmentNumber, // Add to copyWith
    DateTime? createdAt,
  }) {
    return Student(
      id: id ?? this.id,
      name: name ?? this.name,
      rollNumber: rollNumber ?? this.rollNumber,
      semester: semester ?? this.semester,
      department: department ?? this.department,
      division: division ?? this.division,
      timeSlot: timeSlot ?? this.timeSlot,
      enrollmentNumber: enrollmentNumber ?? this.enrollmentNumber, // Include in copy
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Student &&
        other.id == id &&
        other.rollNumber == rollNumber;
  }

  @override
  int get hashCode => id.hashCode ^ rollNumber.hashCode;

  @override
  String toString() {
    return 'Student(id: $id, name: $name, rollNumber: $rollNumber, semester: $semester, department: $department, division: $division)';
  }
}

class AttendanceRecord {
  final int? id;
  final int studentId;
  final DateTime date;
  final bool isPresent;
  final String? notes;
  final String? lecture; // Added lecture/subject field
  final String? timeSlot; // New: optional time slot e.g., '8:00-8:50'
  final DateTime? createdAt;
  final DateTime? updatedAt;

  AttendanceRecord({
    this.id,
    required this.studentId,
    required this.date,
    required this.isPresent,
    this.notes,
    this.lecture,
    this.timeSlot,
    this.createdAt,
    this.updatedAt,
  }) {
    _validateAttendanceRecord();
  }

  void _validateAttendanceRecord() {
    if (studentId <= 0) {
      throw ArgumentError('Student ID must be positive');
    }

    // Don't allow future dates for attendance
    final now = DateTime.now();
    final recordDate = DateTime(date.year, date.month, date.day);
    final today = DateTime(now.year, now.month, now.day);

    if (recordDate.isAfter(today)) {
      throw ArgumentError('Cannot mark attendance for future dates');
    }

    // Validate notes length
    if (notes != null && notes!.length > 500) {
      throw ArgumentError('Notes cannot exceed 500 characters');
    }

    // Validate lecture length
    if (lecture != null && lecture!.length > 100) {
      throw ArgumentError('Lecture name cannot exceed 100 characters');
    }
    // Validate time slot length and pattern
    if (timeSlot != null && timeSlot!.length > 32) {
      throw ArgumentError('Time slot cannot exceed 32 characters');
    }
  }

  Map<String, dynamic> toMap() {
    final now = DateTime.now().toIso8601String();
    return {
      'id': id,
      'student_id': studentId,
      'date': date.toIso8601String().substring(0, 10),
      'is_present': isPresent ? 1 : 0,
      'notes': notes?.trim(),
      'lecture': lecture?.trim(),
      'time_slot': timeSlot ?? '',
      'created_at': createdAt?.toIso8601String() ?? now,
      'updated_at': updatedAt?.toIso8601String() ?? now,
    };
  }

  factory AttendanceRecord.fromMap(Map<String, dynamic> map) {
    return AttendanceRecord(
      id: map['id'],
      studentId: map['student_id'] ?? 0,
      date: map['date'] != null ? DateTime.parse(map['date']) : DateTime.now(),
      isPresent: (map['is_present'] ?? 0) == 1,
      notes: map['notes'],
      lecture: map['lecture'],
      timeSlot: (map['time_slot'] is String) ? (map['time_slot'] as String).trim() : (map['time_slot']?.toString() ?? ''),
      createdAt: _parseDateTimeNullable(map['created_at']),
      updatedAt: _parseDateTimeNullable(map['updated_at']),
    );
  }

  AttendanceRecord copyWith({
    int? id,
    int? studentId,
    DateTime? date,
    bool? isPresent,
    String? notes,
    String? lecture,
    String? timeSlot,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return AttendanceRecord(
      id: id ?? this.id,
      studentId: studentId ?? this.studentId,
      date: date ?? this.date,
      isPresent: isPresent ?? this.isPresent,
      notes: notes ?? this.notes,
      lecture: lecture ?? this.lecture,
      timeSlot: timeSlot ?? this.timeSlot,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AttendanceRecord &&
        other.studentId == studentId &&
        other.date.toIso8601String().substring(0, 10) == date.toIso8601String().substring(0, 10) &&
        other.lecture == lecture &&
        (other.timeSlot ?? '') == (timeSlot ?? '');
  }

  @override
  int get hashCode => studentId.hashCode ^ date.hashCode ^ lecture.hashCode ^ (timeSlot?.hashCode ?? 0);

  @override
  String toString() {
    return 'AttendanceRecord(id: $id, studentId: $studentId, date: ${date.toIso8601String().substring(0, 10)}, isPresent: $isPresent, lecture: $lecture, timeSlot: $timeSlot)';
  }
}

class AttendanceData {
  final int total;
  final int present;
  final int absent;
  final double percentage;

  AttendanceData({
    required this.total,
    required this.present,
    required this.absent,
    required this.percentage,
  }) {
    if (total < 0 || present < 0 || absent < 0) {
      throw ArgumentError('Attendance counts cannot be negative');
    }
    if (present + absent != total) {
      throw ArgumentError('Present + Absent must equal Total');
    }
    if (percentage < 0 || percentage > 100) {
      throw ArgumentError('Percentage must be between 0 and 100');
    }
  }

  factory AttendanceData.fromMap(Map<String, dynamic> map) {
    final total = map['total'] as int? ?? 0;
    final present = map['present'] as int? ?? 0;
    final absent = map['absent'] as int? ?? 0;
    final percentage = total > 0 ? (present / total * 100) : 0.0;

    return AttendanceData(
      total: total,
      present: present,
      absent: absent,
      percentage: percentage,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'total': total,
      'present': present,
      'absent': absent,
      'percentage': percentage,
    };
  }

  @override
  String toString() {
    return 'AttendanceData(total: $total, present: $present, absent: $absent, percentage: ${percentage.toStringAsFixed(1)}%)';
  }
}

// New class for class information
class ClassInfo {
  final int semester;
  final String department;
  final String division;

  ClassInfo({
    required this.semester,
    required this.department,
    required this.division,
  }) {
    _validateClassInfo();
  }

  void _validateClassInfo() {
    if (semester < 1 || semester > 8) {
      throw ArgumentError('Semester must be between 1 and 8');
    }
    if (department.trim().isEmpty) {
      throw ArgumentError('Department cannot be empty');
    }
    if (division.trim().isEmpty) {
      throw ArgumentError('Division cannot be empty');
    }
  }

  String get displayName => '$semester${department.toUpperCase()}-${division.toUpperCase()}';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ClassInfo &&
        other.semester == semester &&
        other.department.toUpperCase() == department.toUpperCase() &&
        other.division.toUpperCase() == division.toUpperCase();
  }

  @override
  int get hashCode => semester.hashCode ^ department.hashCode ^ division.hashCode;

  @override
  String toString() => displayName;
}

// Helper class for validation
class ValidationHelper {
  static bool isValidEmail(String email) {
    return RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}?$').hasMatch(email);
  }

  static bool isValidRollNumber(String rollNumber) {
    // Allow alphanumeric characters, hyphens, colons and slashes commonly used in roll numbers like "CE-B:01".
    return RegExp(r'^[A-Za-z0-9_\-:\/]+$').hasMatch(rollNumber.trim()) && rollNumber.trim().length <= 50;
  }

  static bool isValidName(String name) {
    // Allow letters, spaces, and common punctuation
    return RegExp(r"^[A-Za-z\s\.\-']+$").hasMatch(name) && name.trim().isNotEmpty && name.length <= 100;
  }

  static String sanitizeInput(String input) {
    // Remove potentially harmful characters and trim
    return input.replaceAll(RegExp(r'[<>"&]'), '').replaceAll("'", '').trim();
  }

  static bool isValidDateRange(DateTime? fromDate, DateTime? toDate) {
    if (fromDate == null || toDate == null) return false;
    final now = DateTime.now();
    return !fromDate.isAfter(now) && !toDate.isAfter(now) && !fromDate.isAfter(toDate);
  }
}

// New types for role-based access and invite-based one-time login
enum UserRole { CR, CC, HOD, ADMIN, STUDENT }

extension UserRoleExtension on UserRole {
  String get name {
    switch (this) {
      case UserRole.CR:
        return 'CR';
      case UserRole.CC:
        return 'CC';
      case UserRole.HOD:
        return 'HOD';
      case UserRole.ADMIN:
        return 'ADMIN';
      case UserRole.STUDENT:
        return 'STUDENT';
    }
  }

  static UserRole fromString(String value) {
    final v = value.toUpperCase();
    switch (v) {
      case 'CR':
        return UserRole.CR;
      case 'CC':
        return UserRole.CC;
      case 'HOD':
        return UserRole.HOD;
      case 'ADMIN':
        return UserRole.ADMIN;
      case 'STUDENT':
        return UserRole.STUDENT;
      default:
        // Unknown role: default to CR to maintain older behavior but avoid throwing.
        return UserRole.CR;
    }
  }
}

class AppUser {
  final int? id;
  final String uid; // auth provider uid (e.g., Firebase UID)
  final String email;
  final String name;
  final UserRole role;
  final List<String> permissions; // granular permission tokens
  final List<ClassInfo> allowedClasses; // classes the user can access
  final bool isActive;
  final DateTime createdAt;

  AppUser({
    this.id,
    required this.uid,
    required this.email,
    required this.name,
    required this.role,
    List<ClassInfo>? allowedClasses,
    List<String>? permissions,
    this.isActive = true,
    DateTime? createdAt,
  })  : allowedClasses = allowedClasses ?? [],
        permissions = permissions ?? [],
        createdAt = createdAt ?? DateTime.now() {
    _validate();
  }

  void _validate() {
    if (!ValidationHelper.isValidEmail(email)) {
      throw ArgumentError('Invalid email: $email');
    }
    if (!ValidationHelper.isValidName(name)) {
      throw ArgumentError('Invalid name: $name');
    }
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'uid': uid,
      'email': email.trim().toLowerCase(),
      'name': name.trim(),
      'role': role.name,
      'permissions': permissions,
      // Store allowed classes as structured maps for robustness
      'allowed_classes': allowedClasses.map((c) => {
        'semester': c.semester,
        'department': c.department,
        'division': c.division,
      }).toList(),
      'is_active': isActive ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory AppUser.fromMap(Map<String, dynamic> map) {
    final allowedRaw = map['allowed_classes'] as List<dynamic>?;
    List<ClassInfo> allowed = [];
    if (allowedRaw != null) {
      for (final r in allowedRaw) {
        try {
          if (r is Map) {
            final sem = (r['semester'] is int) ? r['semester'] as int : int.tryParse('${r['semester']}') ?? 1;
            final dept = (r['department'] as String?) ?? '';
            final div = (r['division'] as String?) ?? '';
            if (dept.isNotEmpty && div.isNotEmpty) {
              allowed.add(ClassInfo(semester: sem, department: dept, division: div));
            }
          } else if (r is String) {
            // Try to parse common string patterns like "3CE/IT-B", "3CE-B" or "3CEIT-B"
            final s = r.trim();
            final m = RegExp(r'^(\d{1,2})\s*([A-Za-z\/]+)-([A-Za-z]+)?$').firstMatch(s);
            if (m != null) {
              final sem = int.tryParse(m.group(1)!) ?? 1;
              final dept = m.group(2)!;
              final div = m.group(3)!;
              allowed.add(ClassInfo(semester: sem, department: dept, division: div));
            }
          }
        } catch (_) {
          // ignore malformed entry
        }
      }
    }

    return AppUser(
      id: map['id'],
      uid: map['uid'] ?? '',
      email: map['email'] ?? '',
      name: map['name'] ?? '',
      role: map['role'] != null
          ? UserRoleExtension.fromString(map['role'] as String)
          : UserRole.CR,
      allowedClasses: allowed,
      permissions: (map['permissions'] is List) ? List<String>.from(map['permissions']) : <String>[],
      isActive: (map['is_active'] ?? 1) == 1,
      createdAt: _parseDateTime(map['created_at']),
    );
  }

  AppUser copyWith({
    int? id,
    String? uid,
    String? email,
    String? name,
    UserRole? role,
    List<ClassInfo>? allowedClasses,
    List<String>? permissions,
    bool? isActive,
    DateTime? createdAt,
  }) {
    return AppUser(
      id: id ?? this.id,
      uid: uid ?? this.uid,
      email: email ?? this.email,
      name: name ?? this.name,
      role: role ?? this.role,
      allowedClasses: allowedClasses ?? this.allowedClasses,
      permissions: permissions ?? this.permissions,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  String toString() {
    return 'AppUser(uid: $uid, email: $email, role: ${role.name}, allowedClasses: ${allowedClasses.length})';
  }
}

class InviteToken {
  final String token; // random token string
  final String invitedEmail;
  final UserRole role; // role the invite grants
  final List<ClassInfo> allowedClasses; // classes granted by this invite
  final DateTime expiresAt;
  final bool used;
  final String createdByUid; // who created the invite (CC uid)
  final DateTime createdAt;

  InviteToken({
    required this.token,
    required this.invitedEmail,
    required this.role,
    List<ClassInfo>? allowedClasses,
    required this.expiresAt,
    this.used = false,
    required this.createdByUid,
    DateTime? createdAt,
  })  : allowedClasses = allowedClasses ?? [],
        createdAt = createdAt ?? DateTime.now() {
    _validate();
  }

  void _validate() {
    if (!ValidationHelper.isValidEmail(invitedEmail)) {
      throw ArgumentError('Invalid invited email: $invitedEmail');
    }
    if (token.trim().isEmpty) {
      throw ArgumentError('Token cannot be empty');
    }
    if (expiresAt.isBefore(DateTime.now())) {
      throw ArgumentError('ExpiresAt must be in the future');
    }
  }

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  Map<String, dynamic> toMap() {
    return {
      'token': token,
      'invited_email': invitedEmail.toLowerCase().trim(),
      'role': role.name,
      'allowed_classes': allowedClasses.map((c) => {
        'semester': c.semester,
        'department': c.department,
        'division': c.division,
      }).toList(),
      'expires_at': expiresAt.toIso8601String(),
      'used': used ? 1 : 0,
      'created_by': createdByUid,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory InviteToken.fromMap(Map<String, dynamic> map) {
    final allowedRaw = map['allowed_classes'] as List<dynamic>?;
    List<ClassInfo> allowed = [];
    if (allowedRaw != null) {
      for (final r in allowedRaw) {
        try {
          if (r is Map) {
            final sem = (r['semester'] is int) ? r['semester'] as int : int.tryParse('${r['semester']}') ?? 1;
            final dept = (r['department'] as String?) ?? '';
            final div = (r['division'] as String?) ?? '';
            if (dept.isNotEmpty && div.isNotEmpty) {
              allowed.add(ClassInfo(semester: sem, department: dept, division: div));
            }
          } else if (r is String) {
            final s = r.trim();
            final m = RegExp(r'^(\d{1,2})\s*([A-Za-z\/]+)-([A-Za-z]+)?$').firstMatch(s);
            if (m != null) {
              final sem = int.tryParse(m.group(1)!) ?? 1;
              final dept = m.group(2)!;
              final div = m.group(3)!;
              allowed.add(ClassInfo(semester: sem, department: dept, division: div));
            }
          }
        } catch (_) {
          // ignore malformed entry
        }
      }
    }

    return InviteToken(
      token: map['token'] ?? '',
      invitedEmail: map['invited_email'] ?? '',
      role: map['role'] != null
          ? UserRoleExtension.fromString(map['role'] as String)
          : UserRole.CR,
      allowedClasses: allowed,
      expiresAt: _parseDateTime(map['expires_at']),
      used: (map['used'] ?? 0) == 1,
      createdByUid: map['created_by'] ?? '',
      createdAt: _parseDateTime(map['created_at']),
    );
  }

  InviteToken copyWith({
    String? token,
    String? invitedEmail,
    UserRole? role,
    List<ClassInfo>? allowedClasses,
    DateTime? expiresAt,
    bool? used,
    String? createdByUid,
    DateTime? createdAt,
  }) {
    return InviteToken(
      token: token ?? this.token,
      invitedEmail: invitedEmail ?? this.invitedEmail,
      role: role ?? this.role,
      allowedClasses: allowedClasses ?? this.allowedClasses,
      expiresAt: expiresAt ?? this.expiresAt,
      used: used ?? this.used,
      createdByUid: createdByUid ?? this.createdByUid,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  String toString() {
    return 'InviteToken(token: $token, invitedEmail: $invitedEmail, role: ${role.name}, expiresAt: $expiresAt, used: $used)';
  }
}
