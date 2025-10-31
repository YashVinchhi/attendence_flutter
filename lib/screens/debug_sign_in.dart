import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:go_router/go_router.dart';
import '../providers/auth_provider.dart' as app_auth;

class DebugSignInScreen extends StatefulWidget {
  const DebugSignInScreen({Key? key}) : super(key: key);

  @override
  State<DebugSignInScreen> createState() => _DebugSignInScreenState();
}

class _DebugSignInScreenState extends State<DebugSignInScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;
  String? _message;
  // Read EMULATOR_HOST if provided via --dart-define for quick diagnostics
  // To enable emulator REST fallback set --dart-define=EMULATOR_HOST=<host> when running in debug.
  static const String _emulatorHost = String.fromEnvironment('EMULATOR_HOST', defaultValue: '');

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    setState(() { _loading = true; _message = null; });
    try {
      final auth = FirebaseAuth.instance;
      final email = _emailController.text.trim();
      final password = _passwordController.text;

      // Try sign in via SDK
      await auth.signInWithEmailAndPassword(email: email, password: password);
      setState(() { _message = 'Signed in as $email'; });
      // Inform AuthProvider so the app router and listeners update
      try {
        await app_auth.AuthProvider.instance.signIn(email: email, password: password);
      } catch (_) {}
      if (mounted) context.go('/home');
    } on FirebaseAuthException catch (e) {
      // Surface explicit auth error code/message
      setState(() { _message = 'Auth error (${e.code}): ${e.message}'; });
      // If user not found, attempt create
      if (e.code == 'user-not-found') {
        try {
          await FirebaseAuth.instance.createUserWithEmailAndPassword(
            email: _emailController.text.trim(),
            password: _passwordController.text,
          );
          setState(() { _message = 'User created and signed in.'; });
        } catch (e2, st) {
          // Show more diagnostic info (include stack trace) to locate the cast error origin
          final errStr = e2.toString();
          final stackLines = st.toString().split('\n').take(10).join('\n');
          final msg = 'Failed to create user: $errStr\n$stackLines';
          // Log for developer
          // ignore: avoid_print
          print('DEBUG_SIGN_IN: $msg');

          // If this looks like the Pigeon/platform decode type error, show a clearer hint
          if (errStr.contains("type 'List<Object?>' is not a subtype") || errStr.contains('Pigeon')) {
            // Attempt emulator REST fallback: create user via auth emulator REST API then sign in.
            if (_emulatorHost.isNotEmpty) {
              try {
                final uri = Uri.parse('http://$_emulatorHost:9099/identitytoolkit.googleapis.com/v1/accounts:signUp?key=any');
                final client = HttpClient();
                final req = await client.postUrl(uri);
                req.headers.contentType = ContentType.json;
                final payload = jsonEncode({
                  'email': _emailController.text.trim(),
                  'password': _passwordController.text,
                  'returnSecureToken': true,
                });
                req.add(utf8.encode(payload));
                final resp = await req.close();
                final respBody = await resp.transform(utf8.decoder).join();
                client.close();

                if (resp.statusCode == 200) {
                  // REST create succeeded; sign in via FirebaseAuth to get local user/session
                  try {
                    await FirebaseAuth.instance.signInWithEmailAndPassword(
                      email: _emailController.text.trim(),
                      password: _passwordController.text,
                    );
                    setState(() { _message = 'User created via REST emulator and signed in.'; });
                    // Update AuthProvider and navigate
                    try {
                      await app_auth.AuthProvider.instance.signIn(email: _emailController.text.trim(), password: _passwordController.text);
                    } catch (_) {}
                    if (mounted) context.go('/home');
                  } catch (signinErr) {
                    setState(() { _message = 'User created via REST but sign-in failed: ${signinErr.toString()}'; });
                  }
                } else {
                  setState(() { _message = 'Emulator REST user creation failed (${resp.statusCode}): $respBody'; });
                }
              } catch (restErr) {
                setState(() { _message = 'Platform auth shape error and REST fallback failed: ${restErr.toString()}'; });
              }
            } else {
              setState(() { _message = 'Platform auth response had unexpected shape (Pigeon decode error).\nCheck plugin/native mismatches, run flutter clean and rebuild, and verify emulator is running and EMULATOR_HOST matches the device. See logs for details.'; });
            }
          } else {
            setState(() { _message = msg; });
          }
        }
      } else {
        // already set message above
      }
    } catch (e) {
      setState(() { _message = 'Error: ${e.toString()}'; });
    } finally {
      if (mounted) setState(() { _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(title: const Text('Debug Sign In')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (user != null) ...[
              Text('Currently signed in as ${user.email}'),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () async {
                  await FirebaseAuth.instance.signOut();
                  setState(() {});
                },
                child: const Text('Sign out'),
              ),
            ],

            TextField(
              controller: _emailController,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(labelText: 'Password'),
              obscureText: true,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _loading ? null : _signIn,
              child: _loading ? const CircularProgressIndicator.adaptive() : const Text('Sign in / Create'),
            ),
            const SizedBox(height: 12),
            if (kDebugMode) Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Text(
                'Tip: run the Firebase Auth emulator and start the app in debug mode to test sign-in/create without touching production auth.',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withAlpha((0.6 * 255).round()), fontSize: 12),
              ),
            ),
            const SizedBox(height: 8),
            Text('Emulator host: $_emulatorHost', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withAlpha((0.6*255).round()), fontSize: 12)),
            const SizedBox(height: 12),
            if (_message != null) Text(_message!),

            const SizedBox(height: 20),
            Text('Recent Activity', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SizedBox(
              height: 200,
              child: ListView(
                children: [
                  _buildActivityItem(Icons.check_circle, 'Auth debug event', 'now', Theme.of(context).colorScheme.primary),
                  _buildActivityItem(Icons.info, 'Another event', 'a bit ago', Theme.of(context).colorScheme.secondary),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActivityItem(IconData icon, String title, String time, Color color) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: CircleAvatar(backgroundColor: color.withAlpha((0.12 * 255).round()), child: Icon(icon, color: color)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(time),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}
