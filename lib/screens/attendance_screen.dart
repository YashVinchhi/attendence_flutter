import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../models/models.dart';
import '../providers/student_provider.dart';
import '../providers/attendance_provider.dart';
import '../services/database_helper.dart';

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key, this.initialDate});

  final DateTime? initialDate;

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
  String? _selectedTimeSlot; // <- restored time slot selection
  List<Student> _filteredStudents = [];
  Map<int, bool> _attendanceStatus = {};

  // UI additions
  bool _isLoading = false;
  String _searchQuery = '';
  String _sortBy = 'roll'; // 'name' | 'roll'
  String _statusFilter = 'all'; // 'all' | 'present' | 'absent'

  @override
  void initState() {
    super.initState();
    // Apply deep-linked date if provided
    if (widget.initialDate != null) {
      final now = DateTime.now();
      final d = widget.initialDate!;
      if (!d.isAfter(now)) {
        _selectedDate = d;
      }
    }
    // Use post-frame callback to safely access context
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadStudentsAndAttendance();
    });
  }

  Future<void> _loadStudentsAndAttendance() async {
    setState(() => _isLoading = true);
    final studentProvider = Provider.of<StudentProvider>(
        context, listen: false);
    final attendanceProvider = Provider.of<AttendanceProvider>(
        context, listen: false);

    if (studentProvider.students.isEmpty) {
      await studentProvider.fetchStudents();
    }

    await attendanceProvider.fetchAttendanceByDateAndLecture(
      _selectedDate.toIso8601String().substring(0, 10),
      _getLectureString(),
    );

    _filterStudents();
    _loadAttendanceStatus();
    if (mounted) setState(() => _isLoading = false);
  }

  String? _getLectureString() {
    if (_selectedSubject != null && _selectedLectureNumber != null) {
      // Return canonical lecture string used in DB: 'SUBJECT - Lecture N'.
      // Do not append time slot here — time slot is stored/handled separately
      // (or normalized by DB) to avoid mismatches when querying attendance.
      return '$_selectedSubject - Lecture $_selectedLectureNumber';
    }
    return null;
  }

  void _filterStudents() {
    final studentProvider = Provider.of<StudentProvider>(
        context, listen: false);
    List<Student> list = studentProvider.getStudentsByClass(
      _selectedSemester,
      _selectedDepartment,
      _selectedDivision,
    );

    // Search by name or roll
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((s) =>
      s.name.toLowerCase().contains(q) ||
          s.rollNumber.toLowerCase().contains(q)).toList();
    }

    // Apply status filter if we already have attendanceStatus
    if (_statusFilter != 'all' && _attendanceStatus.isNotEmpty) {
      if (_statusFilter == 'present') {
        list = list.where((s) => _attendanceStatus[s.id!] ?? true).toList();
      } else if (_statusFilter == 'absent') {
        list = list.where((s) => !(_attendanceStatus[s.id!] ?? false)).toList();
      }
    }

    int _compareCeItRoll(Student a, Student b) {
      final ceitRegex = RegExp(r'^(CE|IT)-[A-Z]:(\d+)', caseSensitive: false);
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

      if (ma != null && mb == null) return -1;
      if (ma == null && mb != null) return 1;

      final numRegex = RegExp(r'(\d+)');
      final ra = numRegex.firstMatch(a.rollNumber);
      final rb = numRegex.firstMatch(b.rollNumber);
      if (ra != null && rb != null) {
        final na = int.tryParse(ra.group(1)!) ?? 0;
        final nb = int.tryParse(rb.group(1)!) ?? 0;
        return na.compareTo(nb);
      }
      return a.rollNumber.compareTo(b.rollNumber);
    }

    // Sort
    list.sort((a, b) {
      if (_sortBy == 'name') {
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      }
      return _compareCeItRoll(a, b);
    });

    setState(() {
      _filteredStudents = list;
      // Reset attendance status map keys if it was empty
      if (_attendanceStatus.isEmpty) {
        _attendanceStatus = { for (var s in _filteredStudents) s.id!: true};
      }
    });
  }

  void _loadAttendanceStatus() {
    final attendanceProvider = Provider.of<AttendanceProvider>(
        context, listen: false);
    setState(() {
      _attendanceStatus.clear();
      for (var student in _filteredStudents) {
        final dateStr = _selectedDate.toIso8601String().substring(0, 10);
        // If there is an explicit attendance record for this student/date/lecture, respect it.
        // Otherwise default to PRESENT as requested.
        final hasRec = attendanceProvider.hasAttendanceRecord(
            student.id!, dateStr, lecture: _getLectureString(), timeSlot: _selectedTimeSlot);
        final isPresent = hasRec ? attendanceProvider.isStudentPresent(
            student.id!, dateStr, lecture: _getLectureString(), timeSlot: _selectedTimeSlot) : true;
        _attendanceStatus[student.id!] = isPresent;
      }
    });
  }

  Future<void> _markAttendance(int studentId, bool isPresent) async {
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
        SnackBar(content: Text('All students marked present'), backgroundColor: Theme.of(context).colorScheme.primary),
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
        SnackBar(content: Text('All students marked absent'), backgroundColor: Theme.of(context).colorScheme.error),
      );
    }
  }

  List<String> _getSubjects() {
    return ['DCN', 'DS', 'Maths', 'ADBMS', 'OOP'];
  }

  List<Map<String, String>> _getTimeSlots() {
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
      final attendanceProvider = Provider.of<AttendanceProvider>(
          context, listen: false);

      if (_selectedSubject == null || _selectedLectureNumber == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Please select subject and lecture number before saving'),
            backgroundColor: Theme.of(context).colorScheme.tertiary,
          ),
        );
        return;
      }

      final lectureString = _getLectureString();
      final dateString = _selectedDate.toIso8601String().substring(0, 10);

      // Collect save futures and results so we can report failures
      final List<Future<bool>> tasks = [];

      for (var student in _filteredStudents) {
        final isPresent = _attendanceStatus[student.id] ?? true;
        tasks.add(
            attendanceProvider.markAttendance(
              student.id!,
              dateString,
              isPresent,
              lecture: lectureString,
              timeSlot: _selectedTimeSlot,
            )
        );
      }

      final results = await Future.wait(tasks);
      final failedCount = results.where((r) => r == false).length;

      // Refresh provider's internal cache to ensure other screens see updated data
      await attendanceProvider.fetchAttendanceByDateAndLecture(dateString, lectureString, timeSlot: _selectedTimeSlot);

      // Recompute local attendanceStatus based on refreshed provider data
      _loadAttendanceStatus();

      if (failedCount > 0) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Saved with $failedCount failures. Some records could not be updated.'),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Attendance saved successfully for ${_filteredStudents.length} students'),
              backgroundColor: Theme.of(context).colorScheme.primary,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving attendance: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Widget _buildSkeletonList() {
    final scheme = Theme.of(context).colorScheme;
    final baseGrey = scheme.surfaceContainerHighest;
    final lightGrey = scheme.surface;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: List.generate(8, (index) =>
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Row(
                  children: [
                    Container(width: 64,
                        height: 40,
                        decoration: BoxDecoration(color: baseGrey,
                            borderRadius: BorderRadius.circular(6))),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(height: 14, width: 160, color: baseGrey),
                          const SizedBox(height: 8),
                          Container(height: 12, width: 220, color: lightGrey),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                        width: 24, height: 24, color: baseGrey),
                    const SizedBox(width: 8),
                    Container(
                        width: 24, height: 24, color: baseGrey),
                  ],
                ),
              ),
            )),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final onSurface = scheme.onSurface;
    final mutedText = onSurface.withAlpha((0.8 * 255).round());
    return Scaffold(
      appBar: AppBar(
        title: const Text('Take Attendance', style: TextStyle(fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/home'),
        ),
        actions: [
          IconButton(
            onPressed: _filteredStudents.isNotEmpty ? _saveAttendance : null,
            icon: const Icon(Icons.save_outlined),
            tooltip: 'Save Attendance',
          ),
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () {},
          ),
        ],
        elevation: 0,
      ),
      floatingActionButton: _filteredStudents.isNotEmpty ? FloatingActionButton(
        onPressed: () {
          // Quick mark all action
          showModalBottomSheet(
            context: context,
            builder: (context) =>
                Container(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        leading: Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary),
                        title: const Text('Mark All Present'),
                        onTap: () {
                          Navigator.pop(context);
                          _markAllPresent();
                        },
                      ),
                      ListTile(
                        leading: Icon(Icons.cancel, color: Theme.of(context).colorScheme.error),
                        title: const Text('Mark All Absent'),
                        onTap: () {
                          Navigator.pop(context);
                          _markAllAbsent();
                        },
                      ),
                    ],
                  ),
                ),
          );
        },
        child: const Icon(Icons.add),
      ) : null,
      body: RefreshIndicator(
        onRefresh: _loadStudentsAndAttendance,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            // Date Selection Card
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: scheme.outline),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.calendar_today, size: 20, color: mutedText),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Date',
                            style: TextStyle(
                              fontSize: 12,
                              color: mutedText,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _selectedDate.toIso8601String().substring(0, 10),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
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
                      icon: const Icon(Icons.edit_calendar),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Class Selection
            Row(
              children: [
                Expanded(
                  child: _buildFilterChip(
                    label: 'Sem $_selectedSemester',
                    onTap: () => _showSemesterPicker(),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildFilterChip(
                    label: _selectedDepartment,
                    onTap: () => _showDepartmentPicker(),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildFilterChip(
                    label: 'Div $_selectedDivision',
                    onTap: () => _showDivisionPicker(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Subject and Lecture
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: _buildFilterChip(
                    label: _selectedSubject ?? 'Select Subject',
                    onTap: () => _showSubjectPicker(),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildFilterChip(
                    label: _selectedLectureNumber != null
                        ? 'Lec $_selectedLectureNumber'
                        : 'Lec',
                    onTap: _selectedSubject != null
                        ? () => _showLecturePicker()
                        : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Time Slot selector (restored)
            Row(
              children: [
                Expanded(
                  child: _buildFilterChip(
                    label: _selectedTimeSlot ?? 'Select Time Slot',
                    onTap: () => _showTimeSlotPicker(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Search Bar
            TextField(
              decoration: InputDecoration(
                hintText: 'Search by name or roll...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: scheme.outline),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: scheme.outline),
                ),
                filled: true,
                fillColor: scheme.surfaceContainerHighest,
              ),
              onChanged: (v) {
                setState(() => _searchQuery = v.trim());
                _filterStudents();
              },
            ),
            const SizedBox(height: 16),

            // Status Filter Chips
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildStatusChip('All', 'all', Theme.of(context).colorScheme.surfaceContainerHighest),
                  const SizedBox(width: 8),
                  _buildStatusChip('Present', 'present', Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 8),
                  _buildStatusChip('Absent', 'absent', Theme.of(context).colorScheme.error),
                  const SizedBox(width: 8),
                  _buildStatusChip('Late', 'late', Theme.of(context).colorScheme.tertiary),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Sort Options
            Row(
              children: [
                Expanded(
                  child: ChoiceChip(
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.onetwothree, size: 16),
                        SizedBox(width: 4),
                        Text('By Roll'),
                      ],
                    ),
                    selected: _sortBy == 'roll',
                    onSelected: (selected) {
                      if (selected) {
                        setState(() => _sortBy = 'roll');
                        _filterStudents();
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ChoiceChip(
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.sort_by_alpha, size: 16),
                        SizedBox(width: 4),
                        Text('By Name'),
                      ],
                    ),
                    selected: _sortBy == 'name',
                    onSelected: (selected) {
                      if (selected) {
                        setState(() => _sortBy = 'name');
                        _filterStudents();
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Summary Card
            if (_filteredStudents.isNotEmpty)
              Card(
                elevation: 0,
                color: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: scheme.outline),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildSummaryItem(
                        'Total',
                        '${_filteredStudents.length}',
                        Theme.of(context).colorScheme.secondary,
                        Icons.people,
                      ),
                      Container(
                          width: 1, height: 40, color: scheme.outline),
                      _buildSummaryItem(
                        'Present',
                        '${_attendanceStatus.values
                            .where((s) => s)
                            .length}',
                        Theme.of(context).colorScheme.primary,
                        Icons.check_circle,
                      ),
                      Container(
                          width: 1, height: 40, color: scheme.outline),
                      _buildSummaryItem(
                        'Absent',
                        '${_attendanceStatus.values
                            .where((s) => !s)
                            .length}',
                        Theme.of(context).colorScheme.error,
                        Icons.cancel,
                      ),
                    ],
                  ),
                ),
              ),
            if (_filteredStudents.isNotEmpty) const SizedBox(height: 16),

            // Section Header
            if (!_isLoading && _filteredStudents.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Text(
                      'Student List',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: onSurface,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${_filteredStudents.length} students',
                      style: TextStyle(
                        fontSize: 14,
                        color: mutedText,
                      ),
                    ),
                  ],
                ),
              ),

            // Student List or States
            if (_isLoading)
              _buildSkeletonList()
            else
              if (_filteredStudents.isEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(40.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.people_outline,
                          size: 80,
                          color: scheme.outline,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No Students Found',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: onSurface,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Try adjusting your filters or import students',
                          style: TextStyle(
                            color: mutedText,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          onPressed: () => context.go('/students'),
                          icon: const Icon(Icons.upload_file),
                          label: const Text('Import Students'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 24,
                                vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            // Student cards
            ..._filteredStudents.map((student) {
              final isPresent = _attendanceStatus[student.id] ?? true;
              return Card(
                elevation: 0,
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: scheme.outline),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _markAttendance(student.id!, !isPresent),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        // Avatar with initial
                        CircleAvatar(
                          radius: 24,
                          backgroundColor: isPresent
                              ? Theme.of(context).colorScheme.primary.withAlpha(0x12)
                              : Theme.of(context).colorScheme.error.withAlpha(0x12),
                          child: Text(
                            student.name.isNotEmpty
                                ? student.name[0].toUpperCase()
                                : 'S',
                            style: TextStyle(
                              color: isPresent
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).colorScheme.error,
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Student Info
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                student.name,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Roll: ${student.rollNumber}',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: mutedText,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Present/Absent circular buttons
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildCircleToggle(isPresent, true, onTap: () =>
                                _markAttendance(student.id!, true)),
                            const SizedBox(width: 8),
                            _buildCircleToggle(!isPresent, false, onTap: () =>
                                _markAttendance(student.id!, false)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
            const SizedBox(height: 20), // Bottom padding for submit button
            // Submit attendance large CTA
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: ElevatedButton(
                onPressed: _filteredStudents.isNotEmpty
                    ? _saveAttendance
                    : null,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
                child: const Text('Submit Attendance', style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold)),
              ),
            ),

            const SizedBox(height: 80), // Extra bottom padding
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip({required String label, VoidCallback? onTap}) {
    final scheme = Theme.of(context).colorScheme;
    final mutedText = scheme.onSurface.withAlpha((0.8 * 255).round());
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: scheme.outline),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                  color: scheme.onSurface,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 4),
              Icon(Icons.arrow_drop_down, size: 20, color: mutedText),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusChip(String label, String value, Color color) {
    final scheme = Theme.of(context).colorScheme;
    final mutedText = scheme.onSurface.withAlpha((0.8 * 255).round());
    final isSelected = _statusFilter == value;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        setState(() => _statusFilter = value);
        _filterStudents();
      },
      backgroundColor: scheme.surfaceContainerHighest,
      selectedColor: color.withAlpha((0.2 * 255).round()),
      checkmarkColor: color,
      labelStyle: TextStyle(
        color: isSelected ? color : mutedText,
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
      ),
      side: BorderSide(
        color: isSelected ? color : scheme.outline,
      ),
    );
  }

  Widget _buildSummaryItem(String label, String count, Color color,
      IconData icon) {
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurface.withAlpha((0.8 * 255).round());
    return Column(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 8),
        Text(
          count,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: muted,
          ),
        ),
      ],
    );
  }

  Widget _buildCircleToggle(bool active, bool positive,
      {required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(28),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: active ? (positive ? Theme.of(context).colorScheme.primary.withAlpha(0x12) : Theme.of(context).colorScheme.error.withAlpha(0x12)) : Theme.of(context).colorScheme.surfaceContainerHighest,
          shape: BoxShape.circle,
          border: Border.all(color: active ? (positive ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.error) : Theme.of(context).colorScheme.outline, width: active ? 2 : 1),
        ),
        child: Center(
          child: Icon(
            positive ? Icons.check : Icons.close,
            color: active ? (positive ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.error) : Theme.of(context).colorScheme.onSurface.withAlpha((0.8 * 255).round()),
            size: 20,
          ),
        ),
      ),
    );
  }

  // Picker methods
  void _showSemesterPicker() {
    showModalBottomSheet(
      context: context,
      builder: (context) =>
          Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: DatabaseHelper.instance.getSemesters().map((sem) {
                return ListTile(
                  title: Text('Semester $sem'),
                  trailing: _selectedSemester == sem
                      ? const Icon(Icons.check)
                      : null,
                  onTap: () {
                    setState(() => _selectedSemester = sem);
                    _loadStudentsAndAttendance();
                    Navigator.pop(context);
                  },
                );
              }).toList(),
            ),
          ),
    );
  }

  void _showDepartmentPicker() {
    showModalBottomSheet(
      context: context,
      builder: (context) =>
          Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: DatabaseHelper.instance.getDepartments().map((dept) {
                return ListTile(
                  title: Text(dept),
                  trailing: _selectedDepartment == dept ? const Icon(
                      Icons.check) : null,
                  onTap: () {
                    setState(() => _selectedDepartment = dept);
                    _loadStudentsAndAttendance();
                    Navigator.pop(context);
                  },
                );
              }).toList(),
            ),
          ),
    );
  }

  void _showDivisionPicker() {
    showModalBottomSheet(
      context: context,
      builder: (context) =>
          Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: DatabaseHelper.instance.getDivisions().map((div) {
                return ListTile(
                  title: Text('Division $div'),
                  trailing: _selectedDivision == div
                      ? const Icon(Icons.check)
                      : null,
                  onTap: () {
                    setState(() => _selectedDivision = div);
                    _loadStudentsAndAttendance();
                    Navigator.pop(context);
                  },
                );
              }).toList(),
            ),
          ),
    );
  }

  void _showSubjectPicker() {
    showModalBottomSheet(
      context: context,
      builder: (context) =>
          Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: _getSubjects().map((subject) {
                return ListTile(
                  title: Text(subject),
                  trailing: _selectedSubject == subject ? const Icon(
                      Icons.check) : null,
                  onTap: () {
                    setState(() {
                      _selectedSubject = subject;
                      _selectedLectureNumber = null;
                    });
                    _loadStudentsAndAttendance();
                    Navigator.pop(context);
                  },
                );
              }).toList(),
            ),
          ),
    );
  }

  void _showLecturePicker() {
    showModalBottomSheet(
      context: context,
      builder: (context) =>
          Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(6, (i) => i + 1).map((num) {
                return ListTile(
                  title: Text('Lecture $num'),
                  trailing: _selectedLectureNumber == num ? const Icon(
                      Icons.check) : null,
                  onTap: () {
                    setState(() => _selectedLectureNumber = num);
                    _loadStudentsAndAttendance();
                    Navigator.pop(context);
                  },
                );
              }).toList(),
            ),
          ),
    );
  }

  void _showTimeSlotPicker() {
    showModalBottomSheet(
      context: context,
      builder: (context) =>
          Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: _getTimeSlots().map((m) {
                return ListTile(
                  title: Text(m['label'] ?? m['value']!),
                  trailing: _selectedTimeSlot == m['value'] ? const Icon(
                      Icons.check) : null,
                  onTap: () {
                    setState(() => _selectedTimeSlot = m['value']);
                    _loadStudentsAndAttendance();
                    Navigator.pop(context);
                  },
                );
              }).toList(),
            ),
          ),
    );
  }
}
