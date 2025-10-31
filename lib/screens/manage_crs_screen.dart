import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

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

  Future<List<Map<String, dynamic>>> _loadPendingProfilesWithRole(String role) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where((k) => k.startsWith('pending_profile_')).toList();
      final List<Map<String, dynamic>> out = [];
      for (final k in keys) {
        final s = prefs.getString(k);
        if (s == null) continue;
        try {
          final decoded = jsonDecode(s);
          Map<String, dynamic> profile;
          if (decoded is Map && decoded.containsKey('profile')) {
            profile = Map<String, dynamic>.from(decoded['profile'] as Map);
          } else if (decoded is Map) {
            profile = Map<String, dynamic>.from(decoded);
          } else {
            continue;
          }
          final r = (profile['role'] ?? '').toString().toUpperCase();
          if (r == role.toUpperCase()) {
            out.add(profile);
          }
        } catch (_) {
          continue;
        }
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  Future<Map<String, dynamic>?> _searchStudentByEmail(String email) async {
    final q = await _firestore.collection('users').where('email', isEqualTo: email.toLowerCase()).limit(1).get();
    if (q.docs.isEmpty) return null;
    final doc = q.docs.first;
    final data = Map<String, dynamic>.from(doc.data() as Map<String, dynamic>);
    data['uid'] = (data['uid'] ?? doc.id).toString();
    return data;
  }

  Future<void> _assignCr(String uid) async {
    setState(() { _loading = true; _message = null; });
    try {
      await _firestore.collection('users').doc(uid).set({'role': 'CR'}, SetOptions(merge: true));
      setState(() { _message = 'Assigned CR successfully'; });
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
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: _crsStream(),
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                  if (snap.hasError) {
                    final err = snap.error;
                    String msg = 'Failed to load Class Representatives';
                    if (err is FirebaseException && err.code == 'permission-denied') {
                      msg = 'You do not have permission to view Class Representatives.';
                    } else if (err is Exception) {
                      msg = err.toString();
                    }
                    return Center(child: Padding(padding: const EdgeInsets.all(16.0), child: Text(msg, textAlign: TextAlign.center)));
                  }
                  final docs = snap.data?.docs ?? [];
                  return FutureBuilder<List<Map<String, dynamic>>>(
                    future: _loadPendingProfilesWithRole('CR'),
                    builder: (context, pendingSnap) {
                      final pending = pendingSnap.data ?? [];
                      final seen = <String>{};
                      final items = <Map<String, dynamic>>[];
                      for (final d in docs) {
                        final data = Map<String, dynamic>.from(d.data() as Map);
                        final uid = (data['uid'] ?? d.id).toString();
                        seen.add(uid);
                        items.add({'uid': uid, 'name': data['name'] ?? data['email'] ?? uid, 'pending': false});
                      }
                      for (final p in pending) {
                        final uid = (p['uid'] ?? '').toString();
                        if (uid.isEmpty) continue;
                        if (seen.contains(uid)) continue;
                        items.add({'uid': uid, 'name': p['name'] ?? p['email'] ?? uid, 'pending': true});
                      }
                      if (items.isEmpty) return const Center(child: Text('No Class Representatives found'));
                      return ListView.builder(
                        itemCount: items.length,
                        itemBuilder: (ctx, i) {
                          final entry = items[i];
                          final uid = entry['uid']!.toString();
                          final name = entry['name']!.toString();
                          final isPending = entry['pending'] == true;
                          return Card(
                            child: ListTile(
                              title: Text(name + (isPending ? ' (pending)' : '')),
                              subtitle: Text(uid),
                              trailing: IconButton(
                                icon: const Icon(Icons.remove_circle_outline),
                                tooltip: 'Revoke CR',
                                onPressed: _loading || isPending ? null : () async {
                                  final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
                                    title: const Text('Revoke CR'),
                                    content: Text('Revoke CR role for "$name"?'),
                                    actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')), TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Revoke'))],
                                  ));
                                  if (ok == true) await _revokeCr(uid);
                                  setState(() {});
                                },
                              ),
                            ),
                          );
                        },
                      );
                    },
                  );
                },
              ),
            )
          ],
        ),
      ),
    );
  }
}
