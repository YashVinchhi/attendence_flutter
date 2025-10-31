// Strengthen SignInScreen: use AuthProvider, attempt limit, input sanitation

import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';
import 'dart:io';
// To enable emulator REST fallback set --dart-define=EMULATOR_HOST=<host> when running in debug.
// Read EMULATOR_HOST if provided via --dart-define (used for emulator REST fallback)
const String _emulatorHost = String.fromEnvironment('EMULATOR_HOST', defaultValue: '');

class SignInScreen extends StatefulWidget {
  const SignInScreen({Key? key}) : super(key: key);

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  // No hard-coded credentials; tester should enter credentials or use the debug sign-in.
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  // Password confirmation controller for sign-up
  final _passwordConfirmCtrl = TextEditingController();
  // Onboarding fields for sign-up
  final _nameCtrl = TextEditingController();
  final _departmentCtrl = TextEditingController();
  final _yearCtrl = TextEditingController();
  final _divisionCtrl = TextEditingController();
  bool _loading = false;
  String? _error;
  int _attempts = 0;
  static const int _maxAttempts = 5;
  bool _isSignUp = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _passwordConfirmCtrl.dispose();
    _nameCtrl.dispose();
    _departmentCtrl.dispose();
    _yearCtrl.dispose();
    _divisionCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSignUp) return _handleSignUp();
    if (_attempts >= _maxAttempts) {
      setState(() { _error = 'Too many failed attempts. Restart the app to retry.'; });
      return;
    }

    if (!_formKey.currentState!.validate()) return;
    setState(() { _loading = true; _error = null; });

    final email = _emailCtrl.text.trim().toLowerCase();
    final password = _passwordCtrl.text;

    try {
      // Use AuthProvider to update global auth state
      await AuthProvider.instance.signIn(email: email, password: password);
      if (!mounted) return;
      context.go('/home');
    } catch (e) {
      _attempts += 1;
      // Log full error for debugging
      // ignore: avoid_print
      print('SIGNIN_ERROR: ${e.toString()}');
      final sanitized = _sanitizeError(e.toString());
      final display = kDebugMode ? '${e.toString()}' : sanitized;
      setState(() { _error = 'Sign-in failed: $display'; });
    } finally {
      if (mounted) setState(() { _loading = false; });
    }
  }

  Future<void> _handleSignUp() async {
    if (_attempts >= _maxAttempts) {
      setState(() { _error = 'Too many failed attempts. Restart the app to retry.'; });
      return;
    }

    if (!_formKey.currentState!.validate()) return;
    setState(() { _loading = true; _error = null; });

    final email = _emailCtrl.text.trim().toLowerCase();
    final password = _passwordCtrl.text;
    final name = _nameCtrl.text.trim();
    final department = _departmentCtrl.text.trim();
    final year = _yearCtrl.text.trim();
    final division = _divisionCtrl.text.trim();

    try {
      // Create auth account (dev mode returns deterministic uid)
      // Pass profile fields to AuthService.signUp which will create the Firestore profile document.
      final signUpResult = await AuthService.instance.signUp(
        email: email,
        password: password,
        name: name.isNotEmpty ? name : null,
        department: department.isNotEmpty ? department : null,
        division: division.isNotEmpty ? division : null,
        year: int.tryParse(year) ?? 0,
        role: 'STUDENT',
        isActive: true,
      );
      final uid = signUpResult.uid;

      // If the signUp reported a write error, surface it and offer retry/continue/cancel
      if (AuthService.instance.useFirebase && signUpResult.errorMessage != null) {
        final choice = await showDialog<String>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('Profile save failed'),
            content: Text('We could not save your profile to Firestore: ${signUpResult.errorMessage}\n\nYou can retry now, continue without a saved profile (you can retry later), or cancel account creation.'),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop('retry'), child: const Text('Retry')),
              TextButton(onPressed: () => Navigator.of(ctx).pop('continue'), child: const Text('Continue')),
              TextButton(onPressed: () => Navigator.of(ctx).pop('cancel'), child: const Text('Cancel')),
            ],
          ),
        );

        if (choice == 'cancel') {
          // Attempt to sign out the partially created auth user to avoid orphaned state.
          try { await AuthService.instance.signOut(); } catch (_) {}
          if (mounted) setState(() { _error = 'Profile creation cancelled'; _loading = false; });
          return;
        }

        if (choice == 'retry') {
          // Attempt to flush pending profiles and re-check
          await AuthService.instance.retryPendingProfiles();
          // give a small delay
          await Future.delayed(const Duration(milliseconds: 500));
          try {
            final exists = (await FirebaseFirestore.instance.collection('users').doc(uid).get()).exists;
            if (!exists) {
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Retry attempt did not find profile. It will be retried in background.')));
            } else {
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile saved successfully.')));
            }
          } catch (e) {
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Retry error: $e')));
          }
        }
        // If choice == 'continue', fall through and attempt sign-in
      }

      // Note: AuthService.signUp now creates the Firestore users/{uid} profile.


      // Sign user in to update app-level state (AuthProvider handles persistence)
      // Use timeout + retry to avoid long buffering when platform channels are misbehaving
      bool signedIn = false;
      try {
        await AuthProvider.instance.signIn(email: email, password: password).timeout(const Duration(seconds: 8));
        signedIn = true;
      } catch (signinErr) {
        // Attempt a single retry with longer timeout
        try {
          await AuthProvider.instance.signIn(email: email, password: password).timeout(const Duration(seconds: 6));
          signedIn = true;
        } catch (_) {
          signedIn = false;
        }
      }

      if (signedIn) {
        // Wait briefly for Firestore profile to appear (client-only flow).
        if (AuthService.instance.useFirebase) {
          try {
            final usersCol = FirebaseFirestore.instance.collection('users');
            bool docExists = false;
            // Poll for up to 6 seconds for the users/{uid} doc to appear
            for (int i = 0; i < 6; i++) {
              final snap = await usersCol.doc(uid).get();
              if (snap.exists) { docExists = true; break; }
              await Future.delayed(const Duration(seconds: 1));
            }

            if (!docExists) {
              // Attempt to flush any pending profile writes persisted locally
              await AuthService.instance.retryPendingProfiles();
              // Check once more
              final snap2 = await usersCol.doc(uid).get();
              docExists = snap2.exists;
            }

            if (!docExists) {
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Account created but profile not yet saved to Firestore; it will be retried in background.')));
            } else {
              if (!signUpResult.profileWritten && mounted) {
                // If the initial write didn't succeed but the doc now exists, it was created via retry — inform user.
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile saved to Firestore successfully.')));
              } else if (!mounted) {
                // do nothing
              }
            }
          } catch (e) {
            // ignore poll errors but notify user
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Warning: could not verify profile creation: $e')));
          }
        }

        if (!mounted) return;
        context.go('/home');
      } else {
        if (mounted) setState(() { _error = 'Account created but sign-in timed out. Please try signing in from the Sign In screen.'; });
      }
    } catch (e) {
      final errStr = e.toString();
      _attempts += 1;
      // ignore: avoid_print
      print('SIGNUP_ERROR: ${e.toString()}');
      // Detect Pigeon/platform decode type error and attempt emulator REST fallback
      if ((errStr.contains("type 'List<Object?>' is not a subtype") || errStr.contains('Pigeon')) && _emulatorHost.isNotEmpty) {
        try {
          final uri = Uri.parse('http://$_emulatorHost:9099/identitytoolkit.googleapis.com/v1/accounts:signUp?key=any');
          final client = HttpClient();
          final req = await client.postUrl(uri);
          req.headers.contentType = ContentType.json;
          final payload = jsonEncode({'email': email, 'password': password, 'returnSecureToken': true});
          req.add(utf8.encode(payload));
          final resp = await req.close();
          final body = await resp.transform(utf8.decoder).join();
          client.close();

          if (resp.statusCode == 200) {
            // REST created the user in emulator; sign in via AuthProvider so app state updates
            try {
              await AuthProvider.instance.signIn(email: email, password: password);
              if (!mounted) return;
              context.go('/home');
              return;
            } catch (signinErr) {
              setState(() { _error = 'Created user via emulator but sign-in failed: ${signinErr.toString()}'; });
              return;
            }
          } else {
            setState(() { _error = 'Emulator REST sign-up failed: ${resp.statusCode} $body'; });
            return;
          }
        } catch (restErr) {
          // ignore: avoid_print
          print('EMULATOR_REST_ERROR: $restErr');
          // fallthrough to show sanitized error below
        }
      }
      final sanitized = _sanitizeError(e.toString());
      final display = kDebugMode ? '${e.toString()}' : sanitized;
      setState(() { _error = 'Sign-up failed: $display'; });
    } finally {
      if (mounted) setState(() { _loading = false; });
    }
  }

  String _sanitizeError(String raw) {
    // Basic sanitization to avoid leaking sensitive details in UI
    final lower = raw.toLowerCase();
    if (lower.contains('invalid-argument') || lower.contains('invalid credentials') || lower.contains('invalid credentials (dev)')) {
      return 'Invalid email or password';
    }
    if (lower.contains('unauthenticated')) return 'Authentication required';
    return 'An unexpected error occurred';
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: AuthProvider.instance,
      child: Scaffold(
        appBar: AppBar(title: const Text('Sign In')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: SingleChildScrollView(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextFormField(
                            controller: _emailCtrl,
                            keyboardType: TextInputType.emailAddress,
                            decoration: const InputDecoration(labelText: 'Email'),
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) return 'Email required';
                              if (!RegExp(r"^[^@\s]+@[^@\s]+\.[^@\s]+$").hasMatch(v.trim())) return 'Invalid email';
                              return null;
                            },
                          ),
                          if (_isSignUp) ...[
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _nameCtrl,
                              decoration: const InputDecoration(labelText: 'Full name'),
                              validator: (v) => (v == null || v.trim().isEmpty) ? 'Name required' : null,
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _departmentCtrl,
                              decoration: const InputDecoration(labelText: 'Department'),
                              validator: (v) => (v == null || v.trim().isEmpty) ? 'Department required' : null,
                            ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<String>(
                              initialValue: _yearCtrl.text.isNotEmpty ? _yearCtrl.text : null,
                              decoration: const InputDecoration(labelText: 'Year / Batch'),
                              // Ensure dropdown doesn't overflow horizontally and uses available width
                              isExpanded: true,
                              items: List.generate(5, (i) => (i + 1).toString()).map((y) => DropdownMenuItem(value: y, child: Text(y))).toList(),
                              onChanged: (v) => _yearCtrl.text = v ?? '',
                              validator: (v) => (v == null || v.trim().isEmpty) ? 'Year required' : null,
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _divisionCtrl,
                              decoration: const InputDecoration(labelText: 'Division / Section'),
                              validator: (v) => (v == null || v.trim().isEmpty) ? 'Division required' : null,
                            ),
                          ],
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _passwordCtrl,
                            decoration: const InputDecoration(labelText: 'Password'),
                            obscureText: true,
                            validator: (v) => (v == null || v.isEmpty) ? 'Password required' : null,
                          ),
                          if (_isSignUp) ...[
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _passwordConfirmCtrl,
                              decoration: const InputDecoration(labelText: 'Confirm password'),
                              obscureText: true,
                              validator: (v) {
                                if (v == null || v.isEmpty) return 'Confirm your password';
                                if (v != _passwordCtrl.text) return 'Passwords do not match';
                                return null;
                              },
                            ),
                          ],
                          const SizedBox(height: 16),
                          if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                          const SizedBox(height: 8),
                          ElevatedButton(
                            onPressed: _loading ? null : _submit,
                            child: _loading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : Text(_isSignUp ? 'Create account' : 'Sign In'),
                          ),
                          const SizedBox(height: 12),
                          // Use Wrap so buttons wrap to the next line instead of causing horizontal overflow
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 12,
                            children: [
                              TextButton(
                                onPressed: () {
                                  // For testing allow going to debug sign-in
                                  context.go('/debug-signin');
                                },
                                child: const Text('Debug Sign-in'),
                              ),
                              TextButton(
                                onPressed: _loading ? null : () { setState(() { _isSignUp = !_isSignUp; _error = null; }); },
                                child: Text(_isSignUp ? 'Already have an account? Sign in' : 'Create account'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text('Attempts: '),
                          Text('$_attempts / $_maxAttempts'),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

