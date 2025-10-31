import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class ManageCcsScreen extends StatefulWidget {
  const ManageCcsScreen({Key? key}) : super(key: key);

  @override
  State<ManageCcsScreen> createState() => _ManageCcsScreenState();
}

class _ManageCcsScreenState extends State<ManageCcsScreen> {
  final _searchCtrl = TextEditingController();
  bool _loading = false;
  String? _message;
  final _firestore = FirebaseFirestore.instance;

  // Use real-time snapshots so the list updates automatically when Firestore changes
  Stream<QuerySnapshot> _ccsStream() {
    return _firestore.collection('users').where('role', isEqualTo: 'CC').snapshots();
  }

  // Load pending_profile_* entries that match the given role (e.g., 'CC')
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

  Future<Map<String, dynamic>?> _searchByEmail(String email) async {
    final q = await _firestore.collection('users').where('email', isEqualTo: email.toLowerCase()).limit(1).get();
    if (q.docs.isEmpty) return null;
    final doc = q.docs.first;
    final data = Map<String, dynamic>.from(doc.data() as Map<String, dynamic>);
    // Ensure we always return a uid key (fallback to doc id)
    data['uid'] = (data['uid'] ?? doc.id).toString();
    return data;
  }

  Future<void> _assignCc(String uid) async {
    setState(() { _loading = true; _message = null; });
    try {
      await _firestore.collection('users').doc(uid).set({'role': 'CC'}, SetOptions(merge: true));
      setState(() { _message = 'Assigned CC successfully'; });
    } catch (e) {
      if (e is FirebaseException && e.code == 'permission-denied') {
        setState(() { _message = 'Assign failed: insufficient permissions'; });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('You do not have permission to assign CCs')));
      } else {
        setState(() { _message = 'Assign failed: $e'; });
      }
    } finally {
      setState(() { _loading = false; });
    }
  }

  Future<void> _revokeCc(String uid) async {
    setState(() { _loading = true; _message = null; });
    try {
      await _firestore.collection('users').doc(uid).set({'role': 'FACULTY'}, SetOptions(merge: true));
      setState(() { _message = 'Revoked CC successfully'; });
    } catch (e) {
      if (e is FirebaseException && e.code == 'permission-denied') {
        setState(() { _message = 'Revoke failed: insufficient permissions'; });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('You do not have permission to revoke CCs')));
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
      appBar: AppBar(title: const Text('Manage Class Coordinators')),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: const InputDecoration(labelText: 'Search user by email'),
                    keyboardType: TextInputType.emailAddress,
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _loading ? null : () async {
                    final email = _searchCtrl.text.trim();
                    if (email.isEmpty) return;
                    setState(() { _loading = true; _message = null; });
                    final user = await _searchByEmail(email);
                    if (user == null) {
                      setState(() { _message = 'No user found with that email'; _loading = false; });
                      return;
                    }
                    final uid = user['uid']?.toString();
                    final name = user['name']?.toString() ?? user['email']?.toString() ?? uid;
                    // confirm assign
                    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
                      title: const Text('Assign CC'),
                      content: Text('Make "$name" a Class Coordinator?'),
                      actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')), TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Assign'))],
                    ));
                    if (ok == true && uid != null) {
                      await _assignCc(uid);
                      setState(() {});
                    }
                  },
                  child: const Text('Assign CC'),
                )
              ],
            ),
            if (_message != null) Padding(padding: const EdgeInsets.symmetric(vertical:8.0), child: Text(_message!)),
            const SizedBox(height: 12),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: _ccsStream(),
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                  if (snap.hasError) {
                    final err = snap.error;
                    String msg = 'Failed to load Class Coordinators';
                    if (err is FirebaseException && err.code == 'permission-denied') {
                      msg = 'You do not have permission to view Class Coordinators.';
                    } else if (err is Exception) {
                      msg = err.toString();
                    }
                    return Center(child: Padding(padding: const EdgeInsets.all(16.0), child: Text(msg, textAlign: TextAlign.center)));
                  }

                  final docs = snap.data?.docs ?? [];

                  // Load pending local entries and merge them into the list
                  return FutureBuilder<List<Map<String, dynamic>>>(
                    future: _loadPendingProfilesWithRole('CC'),
                    builder: (context, pendingSnap) {
                      final pending = pendingSnap.data ?? [];
                      // Build a map of existing UIDs to avoid duplicates
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

                      if (items.isEmpty) return const Center(child: Text('No Class Coordinators found'));

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
                                tooltip: 'Revoke CC',
                                onPressed: _loading || isPending ? null : () async {
                                  final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
                                    title: const Text('Revoke CC'),
                                    content: Text('Revoke CC role for "$name"?'),
                                    actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')), TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Revoke'))],
                                  ));
                                  if (ok == true) await _revokeCc(uid);
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
