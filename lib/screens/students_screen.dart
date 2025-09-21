import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../models/models.dart';
import '../providers/student_provider.dart';
import '../services/database_helper.dart';

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
  bool _isAddingStudent = false;
  // Reuse _isAddingStudent as a generic "saving" flag for add/update
  Student? _editingStudent; // currently editing student reference

  // Time slot selection removed from Add Student dialog. Use this default when creating students.
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
        // Use default time slot
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
    if (_searchQuery.isEmpty) return students;

    return students.where((student) {
      return student.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
             student.rollNumber.toLowerCase().contains(_searchQuery.toLowerCase()) ||
             student.department.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();
  }

  Future<void> _importFromCsv() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        final csvData = await file.readAsString();

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
      builder: (context) {
        return AlertDialog(
          title: const Text('Import Students from CSV'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('CSV Format Expected:'),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'Name, Roll Number, Semester, Department, Division\n'
                  'Example:\n'
                  'John Doe, 21CE001, 3, CE, A\n'
                  'Jane Smith, 21IT002, 3, IT, B',
                  style: TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
              const SizedBox(height: 16),
              const Text('This will import all valid students from the CSV file.'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => _performCsvImport(csvData),
              child: const Text('Import'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _performCsvImport(String csvData) async {
    Navigator.of(context).pop(); // Close the dialog

    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('Importing students...'),
          ],
        ),
      ),
    );

    try {
      final studentProvider = Provider.of<StudentProvider>(context, listen: false);
      final result = await studentProvider.bulkImportFromCsv(csvData);

      if (mounted) {
        Navigator.of(context).pop(); // Close loading dialog
        _showImportResultDialog(result);
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop(); // Close loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Import failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
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
        ],
      ),
      body: Consumer<StudentProvider>(
        builder: (context, studentProvider, child) {
          if (studentProvider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          final filteredStudents = _getFilteredStudents(studentProvider.students);

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: TextField(
                  controller: _searchController,
                  decoration: const InputDecoration(
                    hintText: 'Search students...',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value;
                    });
                  },
                ),
              ),
              Expanded(
                child: filteredStudents.isEmpty
                    ? const Center(
                        child: Text(
                          'No students found.\nTap + to add a student.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 16),
                        ),
                      )
                    : ListView.builder(
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
              ),
            ],
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
