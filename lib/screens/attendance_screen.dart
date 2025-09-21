import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../models/models.dart';
import '../providers/student_provider.dart';
import '../providers/attendance_provider.dart';
import '../services/database_helper.dart';

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  DateTime _selectedDate = DateTime.now();
  int _selectedSemester = 3;
  String _selectedDepartment = 'CE/IT';
  String _selectedDivision = 'B';
  String? _selectedSubject;
  int? _selectedLectureNumber;
  String _selectedTimeSlot = '8:00-8:50';
  List<Student> _filteredStudents = [];
  Map<int, bool> _attendanceStatus = {};

  @override
  void initState() {
    super.initState();
    // Use post-frame callback to safely access context
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadStudentsAndAttendance();
    });
  }

  Future<void> _loadStudentsAndAttendance() async {
    final studentProvider = Provider.of<StudentProvider>(context, listen: false);
    final attendanceProvider = Provider.of<AttendanceProvider>(context, listen: false);

    if (studentProvider.students.isEmpty) {
      await studentProvider.fetchStudents();
    }

    await attendanceProvider.fetchAttendanceByDateAndLecture(
      _selectedDate.toIso8601String().substring(0, 10),
      _getLectureString(),
    );

    _filterStudents();
    _loadAttendanceStatus();
  }

  String? _getLectureString() {
    if (_selectedSubject != null && _selectedLectureNumber != null) {
      return '$_selectedSubject - Lecture $_selectedLectureNumber';
    }
    return null;
  }

  void _filterStudents() {
    final studentProvider = Provider.of<StudentProvider>(context, listen: false);
    setState(() {
      _filteredStudents = studentProvider.getStudentsByClass(
        _selectedSemester,
        _selectedDepartment,
        _selectedDivision,
      );
      // Reset attendance status for new list of students
      _attendanceStatus = {
        for (var student in _filteredStudents) student.id!: true
      };
    });
  }

  void _loadAttendanceStatus() {
    final attendanceProvider = Provider.of<AttendanceProvider>(context, listen: false);
    setState(() {
      _attendanceStatus.clear();
      for (var student in _filteredStudents) {
        bool isPresent = attendanceProvider.isStudentPresent(
          student.id!,
          _selectedDate.toIso8601String().substring(0, 10),
          lecture: _getLectureString(),
        );
        _attendanceStatus[student.id!] = isPresent;
      }
    });
  }

  Future<void> _markAttendance(int studentId, bool isPresent) async {
    // No need to call provider here, just update local state
    // The final save will be done with the _saveAttendance method
    setState(() {
      _attendanceStatus[studentId] = isPresent;
    });
  }

  Future<void> _markAllPresent() async {
    setState(() {
      for (var student in _filteredStudents) {
        _attendanceStatus[student.id!] = true;
      }
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All students marked present')),
      );
    }
  }

  Future<void> _markAllAbsent() async {
    setState(() {
      for (var student in _filteredStudents) {
        _attendanceStatus[student.id!] = false;
      }
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All students marked absent')),
      );
    }
  }

  List<String> _getSubjects() {
    // This can be fetched from a provider or database in a real app
    return ['DCN', 'DS', 'Maths', 'ADBMS', 'OOP'];
  }

  List<Map<String, String>> _getTimeSlots() {
    // Return the exact time slots requested by the user
    return [
      {'value': '8:00-8:50', 'label': '08:00 AM - 08:50 AM'},
      {'value': '8:50-9:45', 'label': '08:50 AM - 09:45 AM'},
      {'value': '10:00-10:50', 'label': '10:00 AM - 10:50 AM'},
      {'value': '10:50-11:40', 'label': '10:50 AM - 11:40 AM'},
      {'value': '12:30-1:20', 'label': '12:30 PM - 01:20 PM'},
      {'value': '1:20-2:10', 'label': '01:20 PM - 02:10 PM'},
    ];
  }

  Future<void> _saveAttendance() async {
    try {
      final attendanceProvider = Provider.of<AttendanceProvider>(context, listen: false);

      if (_selectedSubject == null || _selectedLectureNumber == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select subject and lecture number before saving'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      List<Future> saveTasks = [];
      final lectureString = _getLectureString();
      final dateString = _selectedDate.toIso8601String().substring(0, 10);

      for (var student in _filteredStudents) {
        final isPresent = _attendanceStatus[student.id] ?? true;
        saveTasks.add(
            attendanceProvider.markAttendance(
              student.id!,
              dateString,
              isPresent,
              lecture: lectureString,
            )
        );
      }

      await Future.wait(saveTasks);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Attendance saved successfully for ${_filteredStudents.length} students'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving attendance: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Take Attendance'),
        leading: IconButton(
          icon: const Icon(Icons.home),
          onPressed: () => context.go('/home'),
        ),
        actions: [
          IconButton(
            onPressed: _filteredStudents.isNotEmpty ? _saveAttendance : null,
            icon: const Icon(Icons.save),
            tooltip: 'Save Attendance',
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'all_present') {
                _markAllPresent();
              } else if (value == 'all_absent') {
                _markAllAbsent();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'all_present',
                child: Text('Mark All Present'),
              ),
              const PopupMenuItem(
                value: 'all_absent',
                child: Text('Mark All Absent'),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // All selection filters are grouped into one card
          Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Date Selection
                  Row(
                    children: [
                      const Icon(Icons.calendar_today, size: 20),
                      const SizedBox(width: 8),
                      const Text('Date: '),
                      const Spacer(),
                      TextButton(
                        onPressed: () async {
                          final date = await showDatePicker(
                            context: context,
                            initialDate: _selectedDate,
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now(),
                          );
                          if (date != null) {
                            setState(() => _selectedDate = date);
                            _loadStudentsAndAttendance();
                          }
                        },
                        child: Text(
                          _selectedDate.toIso8601String().substring(0, 10),
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Class Selection
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          decoration: const InputDecoration(labelText: 'Sem', border: OutlineInputBorder()),
                          initialValue: _selectedSemester,
                          items: DatabaseHelper.instance.getSemesters()
                              .map((sem) => DropdownMenuItem(value: sem, child: Text('$sem')))
                              .toList(),
                          onChanged: (value) {
                            if (value != null) {
                              setState(() => _selectedSemester = value);
                              _loadStudentsAndAttendance();
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          decoration: const InputDecoration(labelText: 'Dept', border: OutlineInputBorder()),
                          initialValue: _selectedDepartment,
                          items: DatabaseHelper.instance.getDepartments()
                              .map((dept) => DropdownMenuItem(value: dept, child: Text(dept)))
                              .toList(),
                          onChanged: (value) {
                            if (value != null) {
                              setState(() => _selectedDepartment = value);
                              _loadStudentsAndAttendance();
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          decoration: const InputDecoration(labelText: 'Div', border: OutlineInputBorder()),
                          initialValue: _selectedDivision,
                          items: DatabaseHelper.instance.getDivisions()
                              .map((div) => DropdownMenuItem(value: div, child: Text(div)))
                              .toList(),
                          onChanged: (value) {
                            if (value != null) {
                              setState(() => _selectedDivision = value);
                              _loadStudentsAndAttendance();
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Subject and Lecture Number Selection
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: DropdownButtonFormField<String>(
                          decoration: const InputDecoration(labelText: 'Subject', border: OutlineInputBorder()),
                          initialValue: _selectedSubject,
                          items: _getSubjects()
                              .map((sub) => DropdownMenuItem(value: sub, child: Text(sub)))
                              .toList(),
                          onChanged: (value) {
                            setState(() {
                              _selectedSubject = value;
                              if (value == null) _selectedLectureNumber = null;
                            });
                            _loadStudentsAndAttendance();
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          decoration: const InputDecoration(labelText: 'Lec No.', border: OutlineInputBorder()),
                          initialValue: _selectedLectureNumber,
                          items: List.generate(6, (i) => i + 1)
                              .map((num) => DropdownMenuItem(value: num, child: Text('$num')))
                              .toList(),
                          onChanged: _selectedSubject != null ? (value) {
                            setState(() => _selectedLectureNumber = value);
                            _loadStudentsAndAttendance();
                          } : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Time Slot Selection
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(labelText: 'Time Slot', border: OutlineInputBorder()),
                    initialValue: _selectedTimeSlot,
                    items: _getTimeSlots()
                        .map((ts) => DropdownMenuItem(value: ts['value'], child: Text(ts['label']!)))
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _selectedTimeSlot = value);
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
          // Attendance Summary
          if (_filteredStudents.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildSummaryColumn('Total', '${_filteredStudents.length}', Colors.black),
                      _buildSummaryColumn('Present', '${_attendanceStatus.values.where((s) => s).length}', Colors.green),
                      _buildSummaryColumn('Absent', '${_attendanceStatus.values.where((s) => !s).length}', Colors.red),
                    ],
                  ),
                ),
              ),
            ),
          // Student List
          Expanded(
            child: _filteredStudents.isEmpty
                ? const Center(
              child: Text(
                'No students found for selected class.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            )
                : ListView.builder(
              itemCount: _filteredStudents.length,
              itemBuilder: (context, index) {
                final student = _filteredStudents[index];
                final isPresent = _attendanceStatus[student.id] ?? true;
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: ListTile(
                    leading: Container(
                      width: 64,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isPresent ? Colors.green.shade100 : Colors.red.shade100,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Text(
                        student.rollNumber.toString(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isPresent ? Colors.green.shade800 : Colors.red.shade800,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    title: Text(student.name),
                    subtitle: Text('ID: ${student.id}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          onPressed: () => _markAttendance(student.id!, true),
                          icon: Icon(Icons.check_circle, color: isPresent ? Colors.green : Colors.grey),
                          tooltip: 'Mark Present',
                        ),
                        IconButton(
                          onPressed: () => _markAttendance(student.id!, false),
                          icon: Icon(Icons.cancel, color: !isPresent ? Colors.red : Colors.grey),
                          tooltip: 'Mark Absent',
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // Helper widget for the summary card
  Widget _buildSummaryColumn(String title, String count, Color color) {
    return Column(
      children: [
        Text(
          count,
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color),
        ),
        Text(title),
      ],
    );
  }
}