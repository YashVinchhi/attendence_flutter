import 'package:flutter/material.dart';
import '../services/invite_service.dart';

class InviteListScreen extends StatefulWidget {
  const InviteListScreen({Key? key}) : super(key: key);

  @override
  State<InviteListScreen> createState() => _InviteListScreenState();
}

class _InviteListScreenState extends State<InviteListScreen> {
  bool _loading = false;
  List<Map<String, dynamic>> _items = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final List<Map<String, dynamic>> invites = await InviteService.instance.listInvites();
      setState(() { _items = invites; });
    } catch (e) {
      setState(() { _error = e.toString(); });
    } finally {
      setState(() { _loading = false; });
    }
  }

  Future<void> _revoke(String id) async {
    setState(() { _loading = true; });
    try {
      await InviteService.instance.revokeInvite(inviteId: id);
      await _load();
    } catch (e) {
      setState(() { _error = e.toString(); });
    } finally {
      setState(() { _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Invites')),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            if (_loading) const LinearProgressIndicator(),
            if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            Expanded(
              child: ListView.builder(
                itemCount: _items.length,
                itemBuilder: (context, idx) {
                  final it = _items[idx];
                  return Card(
                    child: ListTile(
                      title: Text(it['invitedEmail'] ?? '—'),
                      subtitle: Text('Role: ${it['role'] ?? '—'}\nClasses: ${(it['allowedClasses'] ?? []).join(', ')}'),
                      trailing: IconButton(
                        icon: const Icon(Icons.block),
                        onPressed: () => _revoke(it['id']),
                        tooltip: 'Revoke invite',
                      ),
                    ),
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
