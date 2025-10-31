import 'package:flutter/material.dart';
import '../services/invite_service.dart';
import '../services/database_helper.dart';
import 'edit_cc_screen.dart';

class ManageCcScreen extends StatefulWidget {
  const ManageCcScreen({Key? key}) : super(key: key);

  @override
  State<ManageCcScreen> createState() => _ManageCcScreenState();
}

class _ManageCcScreenState extends State<ManageCcScreen> {
  final _emailController = TextEditingController();
  final Set<String> _selected = {};
  bool _submitting = false;
  String? _message;

  Future<List<Map<String, dynamic>>> _loadClasses() async {
    final combos = await DatabaseHelper.instance.getClassCombinations();
    return combos;
  }

  Future<List<Map<String, dynamic>>> _loadCcs() async {
    // Fetch the list of CCs from the database
    return await DatabaseHelper.instance.getUsersByRole('CC');
  }

  void _editCc(Map<String, dynamic> cc) {
    // Navigate to a screen to edit the CC's assigned classes
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditCcScreen(cc: cc),
      ),
    );
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      setState(() => _message = 'Please enter an email');
      return;
    }
    if (_selected.isEmpty) {
      setState(() => _message = 'Please select at least one class');
      return;
    }

    setState(() { _submitting = true; _message = null; });

    try {
      final resp = await InviteService.instance.createInvite(
        invitedEmail: email,
        role: 'CC',
        allowedClasses: _selected.toList(),
        expiresInDays: 30,
      );

      setState(() {
        _message = 'Invite created: ${resp['inviteId'] ?? resp['token'] ?? 'ok'}';
      });
      _emailController.clear();
      _selected.clear();
    } catch (e) {
      setState(() { _message = 'Failed to create invite: ${e.toString()}'; });
    } finally {
      setState(() { _submitting = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Manage CC')),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Invite a CC by email and assign classes they can manage.'),
            const SizedBox(height: 12),
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(labelText: 'CC Email', border: OutlineInputBorder()),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 12),
            const Text('Select classes to assign'),
            const SizedBox(height: 8),
            Expanded(
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _loadClasses(),
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
                  final list = snap.data ?? [];
                  if (list.isEmpty) return const Text('No classes found');
                  return ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (context, idx) {
                      final item = list[idx];
                      final display = '${item['semester']}${item['department']}-${item['division']}';
                      final checked = _selected.contains(display);
                      return CheckboxListTile(
                        title: Text(display),
                        value: checked,
                        onChanged: (v) {
                          setState(() {
                            if (v == true) _selected.add(display); else _selected.remove(display);
                          });
                        },
                      );
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            const Text('Existing CCs'),
            const SizedBox(height: 8),
            Expanded(
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _loadCcs(),
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final list = snap.data ?? [];
                  if (list.isEmpty) {
                    return const Text('No CCs found');
                  }
                  return ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (context, idx) {
                      final cc = list[idx];
                      return ListTile(
                        title: Text(cc['email'] ?? 'Unknown'),
                        subtitle: Text('Assigned Classes: ${cc['classes'] ?? 'None'}'),
                        trailing: IconButton(
                          icon: const Icon(Icons.edit),
                          onPressed: () => _editCc(cc),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            if (_message != null) Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Text(_message!, style: const TextStyle(color: Colors.red)),
            ),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: _submitting ? null : _submit,
                  icon: const Icon(Icons.send),
                  label: _submitting ? const Text('Sending...') : const Text('Send Invite'),
                ),
                const SizedBox(width: 12),
                TextButton(onPressed: () { setState(() { _emailController.clear(); _selected.clear(); _message = null; }); }, child: const Text('Clear'))
              ],
            )
          ],
        ),
      ),
    );
  }
}
