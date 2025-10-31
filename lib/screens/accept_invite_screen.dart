// Note: Firebase Dynamic Links is deprecated (Aug 25, 2025). Consider migrating to a different
// deep-linking strategy (universal links / app links or a custom URL handler) when time permits.

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/auth_provider.dart' as app_auth;

import '../services/invite_service.dart';

class AcceptInviteScreen extends StatefulWidget {
  // Accept a named parameter `token` (router supplies this).
  final String? token;
  const AcceptInviteScreen({Key? key, this.token}) : super(key: key);

  @override
  State<AcceptInviteScreen> createState() => _AcceptInviteScreenState();
}

class _AcceptInviteScreenState extends State<AcceptInviteScreen> {
  String? _token;
  bool _loading = false;
  String? _message;

  final FirebaseAuth _auth = FirebaseAuth.instance;

  @override
  void initState() {
    super.initState();
    // Initialize internal token from widget.token (router or call-site)
    _token = widget.token;
  }

  Future<void> _signInAnonymouslyForDemo() async {
    // NOTE: In production you should require the invited user to sign-in with the invited email.
    // This helper is only to speed up developer testing.
    if (_auth.currentUser == null) {
      await _auth.signInAnonymously();
      // Also update AuthProvider with the anonymous uid for app-level consistency
      final anonUid = _auth.currentUser?.uid;
      if (anonUid != null) {
        // Persist minimal state so other services that fallback to AuthProvider.uid will work
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('auth_uid', anonUid);
          await prefs.setString('auth_email', _auth.currentUser?.email ?? '');
        } catch (_) {}
        // Re-initialize the app-level AuthProvider so it picks up persisted state
        try { await app_auth.AuthProvider.instance.initialize(); } catch (_) {}
      }
      setState(() {});
    }
  }

  Future<void> _accept() async {
    if (_token == null) return setState(() => _message = 'No token provided');
    setState(() {
      _loading = true;
      _message = null;
    });

    try {
      // Use AuthProvider as the canonical client-side auth state. If not logged in,
      // in debug mode allow demo anonymous sign-in, otherwise prompt the user.
      final isLoggedIn = app_auth.AuthProvider.instance.isLoggedIn;
      if (!isLoggedIn) {
        if (kDebugMode) {
          _message = 'Not signed in — attempting demo sign-in';
          await _signInAnonymouslyForDemo();
        } else {
          setState(() { _message = 'Please sign in first (use invited email)'; });
          return;
        }
      }

      final res = await InviteService.instance.acceptInvite(token: _token!);
      setState(() {
        _message = 'Invite accepted: ${res['result'] ?? res}';
      });
    } catch (e) {
      setState(() {
        _message = 'Failed to accept invite: ${e.toString()}';
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokenField = TextFormField(
      initialValue: _token ?? '',
      onChanged: (v) => _token = v.trim(),
      decoration: const InputDecoration(labelText: 'Invite token'),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Accept Invite')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Open the invite link or paste the token below.'),
            const SizedBox(height: 12),
            tokenField,
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _loading ? null : _accept,
              child: _loading ? const CircularProgressIndicator() : const Text('Accept Invite'),
            ),
            const SizedBox(height: 12),
            if (_message != null) Text(_message!),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () async {
                await _signInAnonymouslyForDemo();
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Signed in anonymously (demo)')));
              },
              child: const Text('Sign in (demo)'),
            ),
          ],
        ),
      ),
    );
  }
}
