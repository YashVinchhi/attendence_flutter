class Student {
  final int? id;
  final String name;
  final String rollNumber;
  final int semester;
  final String department;
  final String division;
  final String timeSlot;
  final DateTime createdAt;

  Student({
    this.id,
    required this.name,
    required this.rollNumber,
    required this.semester,
    required this.department,
    required this.division,
    required this.timeSlot,
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
    if (timeSlot.trim().isEmpty) {
      throw ArgumentError('Time slot cannot be empty');
    }

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
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'])
          : DateTime.now(),
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
  final DateTime? createdAt;
  final DateTime? updatedAt;

  AttendanceRecord({
    this.id,
    required this.studentId,
    required this.date,
    required this.isPresent,
    this.notes,
    this.lecture,
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
      createdAt: map['created_at'] != null ? DateTime.parse(map['created_at']) : null,
      updatedAt: map['updated_at'] != null ? DateTime.parse(map['updated_at']) : null,
    );
  }

  AttendanceRecord copyWith({
    int? id,
    int? studentId,
    DateTime? date,
    bool? isPresent,
    String? notes,
    String? lecture,
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
        other.lecture == lecture;
  }

  @override
  int get hashCode => studentId.hashCode ^ date.hashCode ^ lecture.hashCode;

  @override
  String toString() {
    return 'AttendanceRecord(id: $id, studentId: $studentId, date: ${date.toIso8601String().substring(0, 10)}, isPresent: $isPresent, lecture: $lecture)';
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
    return RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email);
  }

  static bool isValidRollNumber(String rollNumber) {
    // Allow alphanumeric characters, hyphens, and underscores
    return RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(rollNumber) && rollNumber.length <= 20;
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

