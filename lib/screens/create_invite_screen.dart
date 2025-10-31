import 'package:flutter/material.dart';
import '../services/invite_service.dart';
import '../models/models.dart';

class CreateInviteScreen extends StatefulWidget {
  const CreateInviteScreen({Key? key}) : super(key: key);

  @override
  State<CreateInviteScreen> createState() => _CreateInviteScreenState();
}

class _CreateInviteScreenState extends State<CreateInviteScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  String _selectedRole = 'CR';
  final _classesController = TextEditingController();
  bool _loading = false;
  String? _message;

  @override
  void dispose() {
    _emailController.dispose();
    _classesController.dispose();
    super.dispose();
  }

  Future<void> _onCreate() async {
    // Run form validators first
    if (!_formKey.currentState!.validate()) return;

    final email = _emailController.text.trim();
    final role = _selectedRole.trim();
    final classes = _classesController.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

    setState(() { _loading = true; _message = null; });
    try {
      final res = await InviteService.instance.createInvite(invitedEmail: email, role: role, allowedClasses: classes);
      setState(() { _message = 'Invite created: ${res['inviteId']} (token shown for dev)'; });
      // Clear form on success
      _emailController.clear();
      _classesController.clear();
      setState(() { _selectedRole = 'CR'; });
      // For dev convenience, show token if returned
      if (res.containsKey('token')) {
        setState(() { _message = (_message ?? '') + '\nToken: ${res['token']}'; });
      }
    } catch (e) {
      setState(() { _message = 'Failed to create invite: ${e.toString()}'; });
    } finally {
      setState(() { _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Invite')),
      body: Builder(builder: (context) {
        final bottomInset = MediaQuery.of(context).viewInsets.bottom;
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomInset),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Invited Email'),
                  validator: (value) {
                    final v = (value ?? '').trim();
                    if (v.isEmpty) return 'Please enter an email address';
                    if (!ValidationHelper.isValidEmail(v)) return 'Enter a valid email address';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _selectedRole,
                  decoration: const InputDecoration(labelText: 'Role'),
                  items: const [
                    DropdownMenuItem(value: 'CR', child: Text('CR')),
                    DropdownMenuItem(value: 'CC', child: Text('CC')),
                    DropdownMenuItem(value: 'HOD', child: Text('HOD')),
                    DropdownMenuItem(value: 'ADMIN', child: Text('ADMIN')),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() { _selectedRole = v; });
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _classesController,
                  decoration: const InputDecoration(labelText: 'Allowed classes (comma-separated, e.g. 2CEIT-B)'),
                  validator: (value) {
                    // optional, but if provided, ensure comma-separated tokens are non-empty
                    final v = (value ?? '').trim();
                    if (v.isEmpty) return null;
                    final parts = v.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty);
                    if (parts.isEmpty) return 'Please enter at least one valid class or leave empty';
                    return null;
                  },
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _loading ? null : _onCreate,
                  child: _loading
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Create Invite'),
                ),
                const SizedBox(height: 12),
                if (_message != null)
                  Text(
                    _message!,
                    style: TextStyle(color: Theme.of(context).colorScheme.primary),
                  ),
              ],
            ),
          ),
        );
      }),
    );
  }
}
