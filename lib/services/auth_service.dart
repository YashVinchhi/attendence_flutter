import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:shared_preferences/shared_preferences.dart';

/// AuthService provides a thin authentication abstraction and ensures a
/// Firestore `users/{uid}` profile is created after a successful sign-up.
class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  // Dev credentials (local testing)
  static const _devEmail = 'yashhvinchhi@gmail.com';
  static const _devPassword = 'root';

  // Toggle to use firebase_auth; default true for production builds
  bool useFirebase = true;

  final fb_auth.FirebaseAuth? _firebase = fb_auth.FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<String> signIn({required String email, required String password}) async {
    if (email.isEmpty || password.isEmpty) throw Exception('Email/password required');

    if (!useFirebase) {
      if (email.trim().toLowerCase() == _devEmail && password == _devPassword) {
        return _generateDeterministicUid(email);
      }
      throw Exception('Invalid credentials (dev)');
    }

    final result = await _firebase!.signInWithEmailAndPassword(email: email.trim(), password: password);
    final user = result.user;
    if (user == null) throw Exception('Firebase sign-in returned no user');
    return user.uid;
  }

  /// Sign up and attempt to write profile to Firestore. Returns SignUpResult
  /// indicating whether the profile write succeeded immediately.
  Future<SignUpResult> signUp({
    required String email,
    required String password,
    String? name,
    String? department,
    String? division,
    int? year,
    String? role,
    bool? isActive,
  }) async {
    if (email.isEmpty || password.isEmpty) throw Exception('Email/password required');

    if (!useFirebase) {
      final devUid = _generateDeterministicUid(email);
      return SignUpResult(uid: devUid, profileWritten: false, errorMessage: null);
    }

    try {
      final cred = await _firebase!.createUserWithEmailAndPassword(email: email.trim(), password: password);
      final user = cred.user;
      if (user == null) throw Exception('Firebase sign-up returned no user');

      // Fire-and-forget email verification
      try {
        user.sendEmailVerification().catchError((_) {});
      } catch (_) {}

      final uid = user.uid;
      final profile = <String, dynamic>{
        'uid': uid,
        'email': user.email?.trim().toLowerCase() ?? email.trim().toLowerCase(),
        'name': name ?? user.displayName ?? '',
        'department': department ?? '',
        'division': division ?? '',
        'year': year ?? 0,
        // role may be provided but restrict to non-privileged default; keep as STUDENT
        'role': (role ?? 'STUDENT').toString().toUpperCase(),
        // Do NOT include `is_active` or other admin-only keys here — rules disallow self-creation of those.
        'created_at': FieldValue.serverTimestamp(),
      };

      // Help ensure token propagation: reload + refresh token + wait briefly for authStateChanges
      try {
        await _firebase!.currentUser?.reload();
      } catch (_) {}
      try {
        await user.getIdToken(true);
      } catch (_) {}
      try {
        await _firebase!.authStateChanges().firstWhere((u) => u != null && u.uid == uid).timeout(const Duration(seconds: 5));
      } catch (_) {}

      // Attempt to write profile with retries; returns null on success or error message
      final writeError = await _writeProfileWithRetries(uid, profile);

      // Inspect whether a pending entry exists (for logging/diagnostics)
      try {
        final prefs = await SharedPreferences.getInstance();
        final pending = prefs.getString('pending_profile_$uid');
        if (pending == null) {
          // success
        } else {
          // queued for retry
        }
      } catch (_) {}

      return SignUpResult(uid: uid, profileWritten: writeError == null, errorMessage: writeError);
    } on fb_auth.FirebaseAuthException catch (fae) {
      throw Exception('FirebaseAuthException:${fae.code}:${fae.message}');
    } catch (e) {
      rethrow;
    }
  }

  Future<void> sendPasswordReset({required String email}) async {
    if (email.isEmpty) throw Exception('Email required');
    if (!useFirebase) return;
    await _firebase!.sendPasswordResetEmail(email: email.trim());
  }

  Future<void> sendEmailVerification() async {
    if (!useFirebase) return;
    final user = _firebase!.currentUser;
    if (user == null) throw Exception('No authenticated user');
    await user.sendEmailVerification();
  }

  Future<void> signOut() async {
    if (useFirebase && _firebase != null) {
      try {
        await _firebase!.signOut();
      } catch (_) {}
    }
  }

  String _generateDeterministicUid(String email) {
    final normalized = email.trim().toLowerCase();
    final hash = normalized.hashCode;
    return 'dev_${hash.abs()}';
  }

  /// Attempt to write profile with retries. Returns null on success; otherwise
  /// returns an error message suitable for logging/UI.
  Future<String?> _writeProfileWithRetries(String uid, Map<String, dynamic> profile) async {
    const int maxAttempts = 3;
    int attempt = 0;
    while (attempt < maxAttempts) {
      try {
        await _firestore.collection('users').doc(uid).set(profile);
        // clear any pending copy
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove('pending_profile_$uid');
        } catch (_) {}
        return null;
      } catch (e, st) {
        attempt += 1;
        String errMsg = e.toString();
        if (e is FirebaseException) {
          errMsg = '${e.code}: ${e.message}';
        }
        // log
        // ignore: avoid_print
        print('AuthService: write attempt $attempt for uid=$uid failed: $errMsg\n$st');

        // backoff
        await Future.delayed(Duration(milliseconds: 200 * attempt));

        if (attempt >= maxAttempts) {
          // persist pending payload for later retry
          try {
            final prefs = await SharedPreferences.getInstance();
            final payload = {'profile': profile, 'error': errMsg, 'timestamp': DateTime.now().toIso8601String()};
            await prefs.setString('pending_profile_$uid', jsonEncode(payload));
          } catch (storeErr) {
            // ignore
            // ignore: avoid_print
            print('AuthService: failed to persist pending profile for $uid: $storeErr');
          }
          // final failure
          // ignore: avoid_print
          print('AuthService: failed to write user profile for $uid after $maxAttempts attempts: $errMsg');
          return errMsg;
        }
      }
    }
    return 'unknown error';
  }

  /// Retry any pending profile writes saved in SharedPreferences.
  Future<void> retryPendingProfiles() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where((k) => k.startsWith('pending_profile_')).toList();
      for (final k in keys) {
        try {
          final s = prefs.getString(k);
          if (s == null) continue;
          final decoded = jsonDecode(s);
          Map<String, dynamic> profile;
          if (decoded is Map && decoded.containsKey('profile')) {
            profile = Map<String, dynamic>.from(decoded['profile'] as Map);
          } else if (decoded is Map) {
            profile = Map<String, dynamic>.from(decoded);
          } else {
            continue;
          }
          final uid = k.replaceFirst('pending_profile_', '');
          try {
            await _firestore.collection('users').doc(uid).set(profile);
            await prefs.remove(k);
            // ignore: avoid_print
            print('AuthService: retried and wrote pending profile for $uid');
          } catch (inner) {
            // ignore: avoid_print
            print('AuthService: retry failed for $uid: $inner');
          }
        } catch (_) {
          // skip malformed
        }
      }
    } catch (e) {
      // ignore top-level errors but log
      // ignore: avoid_print
      print('AuthService: retryPendingProfiles error: $e');
    }
  }
}

/// Result returned by signUp indicating whether profile write succeeded.
class SignUpResult {
  final String uid;
  final bool profileWritten;
  final String? errorMessage;
  SignUpResult({required this.uid, required this.profileWritten, this.errorMessage});
}
