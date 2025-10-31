import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/database_helper.dart';

class ManageCrsScreen extends StatefulWidget {
  const ManageCrsScreen({Key? key}) : super(key: key);

  @override
  State<ManageCrsScreen> createState() => _ManageCrsScreenState();
}

class _ManageCrsScreenState extends State<ManageCrsScreen> {
  final _searchCtrl = TextEditingController();
  bool _loading = false;
  String? _message;
  final _firestore = FirebaseFirestore.instance;

  Stream<QuerySnapshot> _crsStream() {
    return _firestore.collection('users').where('role', isEqualTo: 'CR').snapshots();
  }

  Future<Map<String, dynamic>?> _searchStudentByEmail(String email) async {
    final q = await _firestore.collection('users').where('email', isEqualTo: email.toLowerCase()).limit(1).get();
    if (q.docs.isEmpty) return null;
    final doc = q.docs.first;
    final data = doc.data();
    data['uid'] = (data['uid'] ?? doc.id).toString();
    return data;
  }

  // Updated the CR assignment flow to include class/division selection
  Future<void> _assignCr(String uid) async {
    // New flow: prompt to select a class to assign to this CR, then write role + assignedClasses
    final classes = await DatabaseHelper.instance.getClassCombinations();
    if (classes.isEmpty) {
      setState(() { _message = 'No classes or divisions available to assign'; });
      return;
    }

    // Build display strings and track selection
    final displayList = classes.map((c) => '${c['semester']}${c['department']}-${c['division'] ?? c['class']}').toList();
    final Set<int> selectedIndices = {}; // Moved here for broader scope

    // Updated to use CheckboxListTile for managing selections
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx2, setState2) {
          return AlertDialog(
            title: const Text('Select classes for CR'),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView.builder(
                itemCount: displayList.length,
                itemBuilder: (context, index) {
                  return CheckboxListTile(
                    title: Text(displayList[index]),
                    value: selectedIndices.contains(index),
                    onChanged: (isChecked) {
                      setState2(() {
                        if (isChecked == true) {
                          selectedIndices.add(index);
                        } else {
                          selectedIndices.remove(index);
                        }
                      });
                    },
                  );
                },
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx2).pop(false), child: const Text('Cancel')),
              TextButton(onPressed: () => Navigator.of(ctx2).pop(true), child: const Text('Assign')),
            ],
          );
        });
      }
    );

    if (ok != true || selectedIndices.isEmpty) {
      setState(() { _message = 'Assignment cancelled'; });
      return;
    }

    setState(() { _loading = true; _message = null; });
    try {
      // Convert selected indices to structured class maps
      final assignedClasses = selectedIndices.map((i) => {
        'semester': classes[i]['semester'],
        'department': classes[i]['department'],
        'division': classes[i]['division'],
      }).toList();

      await _firestore.collection('users').doc(uid).set({
        'role': 'CR',
        'assignedClasses': FieldValue.arrayUnion(assignedClasses),
      }, SetOptions(merge: true));

      setState(() { _message = 'Assigned CR to classes successfully'; });
    } catch (e) {
      if (e is FirebaseException && e.code == 'permission-denied') {
        setState(() { _message = 'Assign failed: insufficient permissions'; });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('You do not have permission to assign CRs')));
      } else {
        setState(() { _message = 'Assign failed: $e'; });
      }
    } finally {
      setState(() { _loading = false; });
    }
  }

  Future<void> _revokeCr(String uid) async {
    setState(() { _loading = true; _message = null; });
    try {
      await _firestore.collection('users').doc(uid).set({'role': 'STUDENT'}, SetOptions(merge: true));
      setState(() { _message = 'Revoked CR successfully'; });
    } catch (e) {
      if (e is FirebaseException && e.code == 'permission-denied') {
        setState(() { _message = 'Revoke failed: insufficient permissions'; });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('You do not have permission to revoke CRs')));
      } else {
        setState(() { _message = 'Revoke failed: $e'; });
      }
    } finally {
      setState(() { _loading = false; });
    }
  }

  void _editCr(Map<String, dynamic> cr) {
    // Navigate to a screen to edit the CR's assigned classes
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditCrScreen(cr: cr),
      ),
    );
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Manage Class Representatives')),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: const InputDecoration(labelText: 'Search student by email'),
                    keyboardType: TextInputType.emailAddress,
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _loading ? null : () async {
                    final email = _searchCtrl.text.trim();
                    if (email.isEmpty) return;
                    setState(() { _loading = true; _message = null; });
                    final user = await _searchStudentByEmail(email);
                    if (user == null) {
                      setState(() { _message = 'No student found with that email'; _loading = false; });
                      return;
                    }
                    final uid = user['uid']?.toString();
                    final name = user['name']?.toString() ?? user['email']?.toString() ?? uid;
                    // confirm assign
                    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
                      title: const Text('Assign CR'),
                      content: Text('Make "$name" a Class Representative?'),
                      actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')), TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Assign'))],
                    ));
                    if (ok == true && uid != null) {
                      await _assignCr(uid);
                      setState(() {});
                    }
                  },
                  child: const Text('Assign CR'),
                )
              ],
            ),
            if (_message != null) Padding(padding: const EdgeInsets.symmetric(vertical:8.0), child: Text(_message!)),
            const SizedBox(height: 12),
            const Text('Existing CRs'),
            const SizedBox(height: 8),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: _crsStream(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError || !snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return const Text('No CRs found');
                  }
                  final crs = snapshot.data!.docs;
                  return ListView.builder(
                    itemCount: crs.length,
                    itemBuilder: (context, idx) {
                      final cr = crs[idx].data() as Map<String, dynamic>;
                      return Card(
                        child: ListTile(
                          title: Text(cr['email'] ?? 'Unknown'),
                          subtitle: Text('Assigned Classes: ${cr['assignedClasses']?.join(', ') ?? 'None'}'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit),
                                onPressed: () => _editCr(cr),
                              ),
                              IconButton(
                                icon: const Icon(Icons.remove_circle_outline),
                                tooltip: 'Revoke CR',
                                onPressed: _loading ? null : () async {
                                  final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
                                    title: const Text('Revoke CR'),
                                    content: Text('Revoke CR role for "${cr['email'] ?? 'Unknown'}"?'),
                                    actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')), TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Revoke'))],
                                  ));
                                  if (ok == true) await _revokeCr(cr['uid']);
                                  setState(() {});
                                },
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class EditCrScreen extends StatelessWidget {
  final Map<String, dynamic> cr;

  const EditCrScreen({Key? key, required this.cr}) : super(key: key);

  // Fixing the return type issue by ensuring the function returns a Future<List<Map<String, dynamic>>>
  Future<List<Map<String, dynamic>>> _fetchCombinedClassesAndDivisions() async {
    final classSnapshot = await FirebaseFirestore.instance.collection('classes').get();
    final divisionSnapshot = await FirebaseFirestore.instance.collection('divisions').get();

    final combinedDocs = [...classSnapshot.docs, ...divisionSnapshot.docs]
        .map((doc) => {
              'id': doc.id,
              ...doc.data(),
            })
        .toList();

    return combinedDocs;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit Class Representative')),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            Text('Editing CR: ${cr['email'] ?? 'Unknown'}'),
            const SizedBox(height: 16),
            Expanded(
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _fetchCombinedClassesAndDivisions(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(child: Text('Error: ${snapshot.error}'));
                  }
                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return const Center(child: Text('No classes or divisions available'));
                  }
                  final classes = snapshot.data!;
                  return ListView.builder(
                    itemCount: classes.length,
                    itemBuilder: (context, idx) {
                      final classData = classes[idx];
                      final className = classData['name'] ?? 'Unnamed Class';
                      final isAssigned = (cr['assignedClasses'] as List<dynamic>?)?.contains(classData['id']) ?? false;
                      return Card(
                        child: ListTile(
                          title: Text(className),
                          trailing: Icon(
                            isAssigned ? Icons.check_box : Icons.check_box_outline_blank,
                            color: isAssigned ? Colors.green : null,
                          ),
                          onTap: () async {
                            // Toggle class assignment
                            final newAssignedClasses = List<String>.from(cr['assignedClasses'] ?? []);
                            if (isAssigned) {
                              newAssignedClasses.remove(classData['id']);
                            } else {
                              newAssignedClasses.add(classData['id']);
                            }
                            await FirebaseFirestore.instance.collection('users').doc(cr['uid']).set({
                              'assignedClasses': newAssignedClasses
                            }, SetOptions(merge: true));
                          },
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
