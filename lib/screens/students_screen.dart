import 'dart:io';
import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';
import '../providers/student_provider.dart';
import '../services/database_helper.dart';
import '../services/navigation_service.dart';

class StudentsScreen extends StatefulWidget {
  const StudentsScreen({super.key});

  @override
  State<StudentsScreen> createState() => _StudentsScreenState();
}

class _StudentsScreenState extends State<StudentsScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _rollNumberController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();

  int _selectedSemester = 1;
  String _selectedDepartment = 'CE';
  String _selectedDivision = 'A';
  String _searchQuery = '';
  String _sortBy = 'roll'; // 'roll' | 'name'
  bool _isAddingStudent = false;
  Student? _editingStudent; // currently editing student reference

  final String _defaultTimeSlot = '8:00-8:50';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<StudentProvider>(context, listen: false).fetchStudents();
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _rollNumberController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _showAddStudentDialog() async {
    _nameController.clear();
    _rollNumberController.clear();
    _selectedSemester = 1;
    _selectedDepartment = 'CE';
    _selectedDivision = 'A';

    return showDialog(
      context: context,
      useRootNavigator: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Add New Student'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Student Name',
                        border: OutlineInputBorder(),
                        hintText: 'Enter student full name',
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _rollNumberController,
                      decoration: const InputDecoration(
                        labelText: 'Roll Number',
                        border: OutlineInputBorder(),
                        hintText: 'Enter unique roll number',
                      ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<int>(
                      decoration: const InputDecoration(
                        labelText: 'Semester',
                        border: OutlineInputBorder(),
                      ),
                      initialValue: _selectedSemester,
                      items: DatabaseHelper.instance.getSemesters()
                          .map((sem) => DropdownMenuItem(
                                value: sem,
                                child: Text('Semester $sem'),
                              ))
                          .toList(),
                      onChanged: (value) {
                        setDialogState(() {
                          _selectedSemester = value!;
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      decoration: const InputDecoration(
                        labelText: 'Department',
                        border: OutlineInputBorder(),
                      ),
                      initialValue: _selectedDepartment,
                      items: DatabaseHelper.instance.getIndividualDepartments()
                          .map((dept) => DropdownMenuItem(
                                value: dept,
                                child: Text(dept),
                              ))
                          .toList(),
                      onChanged: (value) {
                        setDialogState(() {
                          _selectedDepartment = value!;
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      decoration: const InputDecoration(
                        labelText: 'Division',
                        border: OutlineInputBorder(),
                      ),
                      initialValue: _selectedDivision,
                      items: DatabaseHelper.instance.getDivisions()
                          .map((div) => DropdownMenuItem(
                                value: div,
                                child: Text('Division $div'),
                              ))
                          .toList(),
                      onChanged: (value) {
                        setDialogState(() {
                          _selectedDivision = value!;
                        });
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: _isAddingStudent ? null : () => _addStudent(),
                  child: _isAddingStudent
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Add Student'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _addStudent() async {
    if (_nameController.text.trim().isEmpty ||
        _rollNumberController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all fields')),
      );
      return;
    }

    setState(() {
      _isAddingStudent = true;
    });

    try {
      final student = Student(
        name: _nameController.text.trim(),
        rollNumber: _rollNumberController.text.trim(),
        semester: _selectedSemester,
        department: _selectedDepartment,
        division: _selectedDivision,
        timeSlot: _defaultTimeSlot,
      );

      final studentProvider = Provider.of<StudentProvider>(context, listen: false);
      final success = await studentProvider.addStudent(student);

      if (mounted) {
        setState(() {
          _isAddingStudent = false;
        });

        if (success) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Student added successfully'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(studentProvider.errorMessage ?? 'Failed to add student'),
              backgroundColor: Colors.red,
            ),
          );
          studentProvider.clearError();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isAddingStudent = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error adding student: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _showEditStudentDialog(Student student) async {
    _editingStudent = student;
    _nameController.text = student.name;
    _rollNumberController.text = student.rollNumber;
    _selectedSemester = student.semester;
    _selectedDepartment = student.department;
    _selectedDivision = student.division;

    return showDialog(
      context: context,
      useRootNavigator: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Edit Student'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Student Name',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _rollNumberController,
                      decoration: const InputDecoration(
                        labelText: 'Roll Number',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<int>(
                      decoration: const InputDecoration(
                        labelText: 'Semester',
                        border: OutlineInputBorder(),
                      ),
                      initialValue: _selectedSemester,
                      items: DatabaseHelper.instance.getSemesters()
                          .map((sem) => DropdownMenuItem(
                                value: sem,
                                child: Text('Semester $sem'),
                              ))
                          .toList(),
                      onChanged: (value) {
                        setDialogState(() {
                          _selectedSemester = value!;
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      decoration: const InputDecoration(
                        labelText: 'Department',
                        border: OutlineInputBorder(),
                      ),
                      initialValue: _selectedDepartment,
                      items: DatabaseHelper.instance.getIndividualDepartments()
                          .map((dept) => DropdownMenuItem(
                                value: dept,
                                child: Text(dept),
                              ))
                          .toList(),
                      onChanged: (value) {
                        setDialogState(() {
                          _selectedDepartment = value!;
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      decoration: const InputDecoration(
                        labelText: 'Division',
                        border: OutlineInputBorder(),
                      ),
                      initialValue: _selectedDivision,
                      items: DatabaseHelper.instance.getDivisions()
                          .map((div) => DropdownMenuItem(
                                value: div,
                                child: Text('Division $div'),
                              ))
                          .toList(),
                      onChanged: (value) {
                        setDialogState(() {
                          _selectedDivision = value!;
                        });
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    _editingStudent = null;
                    Navigator.of(context).pop();
                  },
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: _isAddingStudent ? null : () => _updateStudent(),
                  child: _isAddingStudent
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Update'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _updateStudent() async {
    if (_editingStudent == null) return;

    if (_nameController.text.trim().isEmpty || _rollNumberController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please fill all fields')));
      return;
    }

    setState(() {
      _isAddingStudent = true;
    });

    try {
      final updated = Student(
        id: _editingStudent!.id,
        name: _nameController.text.trim(),
        rollNumber: _rollNumberController.text.trim(),
        semester: _selectedSemester,
        department: _selectedDepartment,
        division: _selectedDivision,
        timeSlot: _editingStudent!.timeSlot,
        createdAt: _editingStudent!.createdAt,
      );

      final studentProvider = Provider.of<StudentProvider>(context, listen: false);
      final success = await studentProvider.updateStudent(updated);

      if (mounted) {
        setState(() {
          _isAddingStudent = false;
        });

        if (success) {
          Navigator.of(context).pop();
          _editingStudent = null;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Student updated successfully'), backgroundColor: Colors.green),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(studentProvider.errorMessage ?? 'Failed to update student'), backgroundColor: Colors.red),
          );
          studentProvider.clearError();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isAddingStudent = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating student: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _deleteStudent(Student student) async {
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (context) => AlertDialog(
        title: const Text('Delete Student'),
        content: Text('Are you sure you want to delete ${student.name}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await Provider.of<StudentProvider>(context, listen: false)
            .deleteStudent(student.id!);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Student deleted successfully')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting student: $e')),
          );
        }
      }
    }
  }

  List<Student> _getFilteredStudents(List<Student> students) {
    List<Student> list = students;

    if (_searchQuery.isNotEmpty) {
      list = list.where((student) {
        return student.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
               student.rollNumber.toLowerCase().contains(_searchQuery.toLowerCase()) ||
               student.department.toLowerCase().contains(_searchQuery.toLowerCase());
      }).toList();
    }

    int _compareCeItRoll(Student a, Student b) {
      final ceitRegex = RegExp(r'^(CE|IT)-[A-Z]:(\d+)', caseSensitive: false);
      final ma = ceitRegex.firstMatch(a.rollNumber.toUpperCase());
      final mb = ceitRegex.firstMatch(b.rollNumber.toUpperCase());

      if (ma != null && mb != null) {
        final deptA = ma.group(1)!; // CE or IT
        final deptB = mb.group(1)!;
        if (deptA != deptB) return deptA == 'CE' ? -1 : 1; // CE before IT
        final numA = int.tryParse(ma.group(2)!) ?? 0;
        final numB = int.tryParse(mb.group(2)!) ?? 0;
        return numA.compareTo(numB);
      }

      // If only one matches the CE/IT pattern, prefer the matching one
      if (ma != null && mb == null) return -1;
      if (ma == null && mb != null) return 1;

      // Fallback: compare by first numeric sequence found
      final numRegex = RegExp(r'(\d+)');
      final ra = numRegex.firstMatch(a.rollNumber);
      final rb = numRegex.firstMatch(b.rollNumber);
      if (ra != null && rb != null) {
        final na = int.tryParse(ra.group(1)!) ?? 0;
        final nb = int.tryParse(rb.group(1)!) ?? 0;
        return na.compareTo(nb);
      }

      // Last resort: alphabetical roll string
      return a.rollNumber.compareTo(b.rollNumber);
    }

    list.sort((a, b) {
      if (_sortBy == 'name') {
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      }
      // Default: CE group first, then IT group, each by numeric roll
      return _compareCeItRoll(a, b);
    });

    return list;
  }

  Future<void> _importFromCsv() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        allowMultiple: false,
        withData: true,
      );

      if (result != null) {
        String csvData;
        if (result.files.single.path != null) {
          final file = File(result.files.single.path!);
          csvData = await file.readAsString();
        } else if (result.files.single.bytes != null) {
          csvData = String.fromCharCodes(result.files.single.bytes!);
        } else {
          throw Exception('Unable to read file data');
        }

        if (mounted) {
          _showImportDialog(csvData);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error reading file: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showImportDialog(String csvData) {
    showDialog(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Import Students from CSV'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('CSV Formats Supported:'),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'Format A (5 columns):\n'
                  'Name, Roll Number, Semester, Department, Division\n'
                  'Example:\n'
                  'John Doe, 21CE001, 3, CE, A\n'
                  'Jane Smith, 21IT002, 3, IT, B\n\n'
                  'Format B (2 columns, CE/IT style):\n'
                  'Roll, Name  (e.g., CE-B:01, JOHN DOE)\n'
                  'Example:\n'
                  'CE-B:01, KANJARIYA VAISHALIBEN BHIKHABHAI\n'
                  'IT-B:02, DUDHAIYA RACHIT VIPULBHAI',
                  style: TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Tips:'),
              const SizedBox(height: 4),
              const Text('- Headers are optional and will be detected automatically.'),
              const Text('- Empty lines are ignored. Non-student label lines may be reported as errors.'),
              const SizedBox(height: 16),
              const Text('This will import all valid students from the CSV file.'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                await Future.delayed(const Duration(milliseconds: 100));
                if (context.mounted) {
                  _performCsvImport(csvData);
                }
              },
              child: const Text('Import'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _performCsvImport(String csvData) async {
    if (!mounted) return;

    final navigationService = Provider.of<NavigationService>(context, listen: false);
    final loadingDialog = AlertDialog(
      title: const Text('Importing Students'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const LinearProgressIndicator(),
          const SizedBox(height: 16),
          Consumer<StudentProvider>(
            builder: (context, provider, child) {
              return const Text('Processing CSV data...');
            },
          ),
        ],
      ),
    );

    navigationService.showDialogSafely(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: loadingDialog,
      ),
    );

    try {
      final studentProvider = Provider.of<StudentProvider>(context, listen: false);
      final result = await studentProvider.bulkImportFromCsv(csvData);

      if (mounted) {
        await navigationService.popDialog(context, useRootNavigator: true);
        await Future.delayed(const Duration(milliseconds: 200));
        if (mounted) {
          _showImportResultDialog(result);
        }
      }
    } catch (e) {
      if (mounted) {
        await navigationService.popDialog(context, useRootNavigator: true);
        await Future.delayed(const Duration(milliseconds: 200));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Import failed: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  void _showImportResultDialog(Map<String, dynamic> result) {
    final bool success = result['success'] ?? false;
    final int imported = result['imported'] ?? 0;
    final int total = result['total'] ?? 0;
    final List<String> errors = List<String>.from(result['errors'] ?? []);

    showDialog(
      context: context,
      useRootNavigator: true,
      builder: (context) {
        return AlertDialog(
          title: Text(success ? 'Import Completed' : 'Import Failed'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Successfully imported: $imported out of $total students'),
                if (errors.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Text('Errors:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Container(
                    height: 200,
                    width: double.maxFinite,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: ListView.builder(
                      itemCount: errors.length,
                      itemBuilder: (context, index) {
                        return Padding(
                          padding: const EdgeInsets.all(4),
                          child: Text(
                            errors[index],
                            style: const TextStyle(fontSize: 12, color: Colors.red),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSkeletonList() {
    final scheme = Theme.of(context).colorScheme;
    final base = scheme.surfaceContainerHighest.withValues(alpha: 0.5);
    final highlight = scheme.surfaceContainerHighest.withValues(alpha: 0.9);

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemBuilder: (_, __) => _Shimmer(
        baseColor: base,
        highlightColor: highlight,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                const CircleAvatar(radius: 20, backgroundColor: Colors.white24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(height: 14, width: 160, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(8))),
                      const SizedBox(height: 8),
                      Container(height: 12, width: 220, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(8))),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Container(width: 24, height: 24, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(6))),
                const SizedBox(width: 8),
                Container(width: 24, height: 24, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(6))),
              ],
            ),
          ),
        ),
      ),
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemCount: 8,
    );
  }

  Future<void> _resetSampleData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset Sample Data'),
        content: const Text('This will clear all current students and attendance, then reload the built-in sample students. Continue?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Reset')),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await DatabaseHelper.instance.clearAllData();
      // Ensure sample loader is allowed
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('user_cleared_data', false);
      // Re-fetch; this will auto-load sample if DB is empty
      await Provider.of<StudentProvider>(context, listen: false).fetchStudents();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sample data reloaded')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Reset failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Students'),
        leading: IconButton(
          icon: const Icon(Icons.home),
          onPressed: () => context.go('/home'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _showAddStudentDialog,
            tooltip: 'Add Student',
          ),
          IconButton(
            icon: const Icon(Icons.upload_file),
            onPressed: _importFromCsv,
            tooltip: 'Import Students from CSV',
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'reset') _resetSampleData();
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'reset', child: Text('Reset sample data')),
            ],
          ),
        ],
      ),
      body: Consumer<StudentProvider>(
        builder: (context, studentProvider, child) {
          final isLoading = studentProvider.isLoading;
          final filteredStudents = _getFilteredStudents(studentProvider.students);
          final total = studentProvider.students.length;
          final shown = filteredStudents.length;

          return RefreshIndicator(
            onRefresh: () => studentProvider.fetchStudents(),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: 'Search students by name or roll...',
                          prefixIcon: const Icon(Icons.search),
                          border: const OutlineInputBorder(),
                          suffixIcon: _searchController.text.isEmpty
                              ? null
                              : IconButton(
                                  icon: const Icon(Icons.clear),
                                  tooltip: 'Clear',
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() => _searchQuery = '');
                                  },
                                ),
                        ),
                        onChanged: (value) {
                          setState(() {
                            _searchQuery = value;
                          });
                        },
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text('Showing $shown of $total', style: Theme.of(context).textTheme.labelMedium),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: SegmentedButton<String>(
                              segments: const [
                                ButtonSegment(value: 'roll', label: Text('Sort: Roll'), icon: Icon(Icons.onetwothree)),
                                ButtonSegment(value: 'name', label: Text('Sort: Name'), icon: Icon(Icons.sort_by_alpha)),
                              ],
                              selected: {_sortBy},
                              style: ButtonStyle(
                                shape: const WidgetStatePropertyAll(StadiumBorder()),
                                side: WidgetStateProperty.resolveWith((states) {
                                  final selected = states.contains(WidgetState.selected);
                                  return BorderSide(color: selected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.outlineVariant);
                                }),
                                foregroundColor: WidgetStateProperty.resolveWith((states) {
                                  final selected = states.contains(WidgetState.selected);
                                  return selected ? Colors.white : Theme.of(context).colorScheme.onSurface;
                                }),
                                backgroundColor: WidgetStateProperty.resolveWith((states) {
                                  final selected = states.contains(WidgetState.selected);
                                  return selected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.surfaceContainerHighest;
                                }),
                              ),
                              onSelectionChanged: (s) {
                                setState(() => _sortBy = s.first);
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Quick CTA chip
                          ActionChip(
                            avatar: const Icon(Icons.download, size: 18),
                            label: const Text('Import CSV'),
                            onPressed: _importFromCsv,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (isLoading)
                  SizedBox(height: MediaQuery.of(context).size.height * 0.6, child: _buildSkeletonList())
                else if (filteredStudents.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Center(
                      child: Column(
                        children: [
                          const Icon(Icons.people_outline, size: 72),
                          const SizedBox(height: 12),
                          const Text('No Students Found', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          const Text('Add students or import from a CSV file to get started.', textAlign: TextAlign.center),
                          const SizedBox(height: 16),
                          Wrap(
                            spacing: 8,
                            children: [
                              ElevatedButton.icon(
                                onPressed: _showAddStudentDialog,
                                icon: const Icon(Icons.person_add),
                                label: const Text('Add Student'),
                              ),
                              OutlinedButton.icon(
                                onPressed: _importFromCsv,
                                icon: const Icon(Icons.upload_file),
                                label: const Text('Import Students from CSV'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  ListView.builder(
                    physics: const NeverScrollableScrollPhysics(),
                    shrinkWrap: true,
                    itemCount: filteredStudents.length,
                    itemBuilder: (context, index) {
                      final student = filteredStudents[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        child: ListTile(
                          leading: CircleAvatar(
                            child: Text(
                              student.name.isNotEmpty
                                  ? student.name[0].toUpperCase()
                                  : '?',
                            ),
                          ),
                          title: Text(student.name),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Roll No: ${student.rollNumber}'),
                              Text(
                                'Sem ${student.semester} • ${student.department} • Div ${student.division}',
                              ),
                              Text('Time Slot: ${student.timeSlot}'),
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit, color: Colors.blue),
                                onPressed: () => _showEditStudentDialog(student),
                                tooltip: 'Edit',
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red),
                                onPressed: () => _deleteStudent(student),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddStudentDialog,
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _Shimmer extends StatefulWidget {
  final Widget child;
  final Color baseColor;
  final Color highlightColor;
  const _Shimmer({required this.child, required this.baseColor, required this.highlightColor});

  @override
  State<_Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<_Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))
      ..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final v = _controller.value; // 0..1
        final gradient = LinearGradient(
          begin: Alignment(-1.0 + 2.0 * v, 0.0),
          end: Alignment(1.0 + 2.0 * v, 0.0),
          colors: [
            widget.baseColor,
            widget.highlightColor,
            widget.baseColor,
          ],
          stops: const [0.35, 0.5, 0.65],
        );
        return ShaderMask(
          shaderCallback: (rect) => gradient.createShader(rect),
          blendMode: BlendMode.srcATop,
          child: child,
        );
      },
    );
  }
}
