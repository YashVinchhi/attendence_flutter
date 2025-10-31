// Persist auth state using SharedPreferences and provide an async initialize method
import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_service.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;


/// AuthProvider keeps the app-level authentication state. It's a simple
/// ChangeNotifier singleton so GoRouter can listen to it for redirects.
class AuthProvider extends ChangeNotifier {
  AuthProvider._();
  static final AuthProvider instance = AuthProvider._();

  String? _uid;
  String? _email;
  StreamSubscription<fb_auth.User?>? _fbSub;
  Timer? _retryTimer;

  bool get isLoggedIn => _uid != null;
  String? get uid => _uid;
  String? get email => _email;

  bool _initialized = false;

  /// Initialize auth state from persisted storage. Call this at app startup
  /// before creating the router if you want the router to see restored state.
  Future<void> initialize() async {
    if (_initialized) {
      // ensure firebase listener attached if not already
      _attachFirebaseListener();
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final uid = prefs.getString('auth_uid');
    final email = prefs.getString('auth_email');
    if (uid != null) {
      _uid = uid;
      _email = email;
    }
    _initialized = true;

    // Start listening to FirebaseAuth state changes so AuthProvider stays in sync
    _attachFirebaseListener();

    // Start a periodic background retry timer that runs when network is reachable.
    // Using a lightweight TCP reachability check avoids a hard dependency on
    // the connectivity_plus package; it also works in most network environments.
    _startPeriodicRetry();

    notifyListeners();
  }

  void _startPeriodicRetry() {
    // If a timer already exists, keep it
    if (_retryTimer != null) return;
    _retryTimer = Timer.periodic(const Duration(seconds: 15), (t) async {
      try {
        // Quick reachability check; uses DNS / TCP connect heuristics
        final reachable = await _isHostReachable('8.8.8.8', 53, const Duration(milliseconds: 800));
        if (!reachable) return;
        await AuthService.instance.retryPendingProfiles();
      } catch (_) {
        // ignore individual retry errors
      }
    });
  }

  void _attachFirebaseListener() {
    if (_fbSub != null) return;
    try {
      _fbSub = fb_auth.FirebaseAuth.instance.authStateChanges().listen((user) async {
        if (user != null) {
          _uid = user.uid;
          _email = user.email;
          // persist minimal auth state for app restart
          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('auth_uid', _uid!);
            if (_email != null) await prefs.setString('auth_email', _email!);
          } catch (_) {}
        } else {
          _uid = null;
          _email = null;
          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.remove('auth_uid');
            await prefs.remove('auth_email');
          } catch (_) {}
        }
        notifyListeners();
      });
    } catch (_) {
      // ignore if FirebaseAuth is not available in this environment
    }
  }

  /// Sign in using the underlying AuthService and update state.
  Future<void> signIn({required String email, required String password}) async {
    try {
      final uid = await AuthService.instance.signIn(email: email, password: password);
      _uid = uid;
      _email = email.trim().toLowerCase();
      // Persist minimal auth state
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('auth_uid', _uid!);
        if (_email != null) await prefs.setString('auth_email', _email!);
      } catch (_) {}
      notifyListeners();
      return;
    } catch (e) {
      // If running locally against the emulator in debug, attempt a REST fallback
      if (kDebugMode) {
        // Detect emulator host from dart-define (same as main reads)
        const String emulatorHost = String.fromEnvironment('EMULATOR_HOST', defaultValue: '10.0.2.2');
        if (emulatorHost.isNotEmpty) {
          // Quick reachability check to avoid long timeouts on devices that cannot reach the host
          final reachable = await _isHostReachable(emulatorHost, 9099, const Duration(milliseconds: 800));
          if (!reachable) {
            debugPrint('AuthProvider: emulator host $emulatorHost:9099 not reachable, skipping REST fallback');
          } else {
           HttpClient? client;
           try {
            client = HttpClient();
             // Try REST signInWithPassword first (common when SDK/native integration fails)
             try {
              final signInUri = Uri.parse('http://$emulatorHost:9099/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=any');
              final req = await client.postUrl(signInUri).timeout(const Duration(seconds: 8));
               req.headers.contentType = ContentType.json;
               final payload = jsonEncode({'email': email.trim(), 'password': password, 'returnSecureToken': true});
               req.add(utf8.encode(payload));
               final resp = await req.close();
               final body = await resp.transform(utf8.decoder).join();

               if (resp.statusCode == 200) {
                 final parsed = jsonDecode(body) as Map<String, dynamic>;
                 final localId = parsed['localId']?.toString();
                 if (localId != null && localId.isNotEmpty) {
                   _uid = localId;
                   _email = email.trim().toLowerCase();
                   try {
                     final prefs = await SharedPreferences.getInstance();
                     await prefs.setString('auth_uid', _uid!);
                     if (_email != null) await prefs.setString('auth_email', _email!);
                   } catch (_) {}
                   notifyListeners();
                   return;
                 }
               } else {
                 // If user not found, try signUp then signIn
                 try {
                   final parsedErr = jsonDecode(body) as Map<String, dynamic>?;
                   final errMsg = (parsedErr != null && parsedErr['error'] is Map) ? parsedErr['error']['message']?.toString() ?? '' : '';
                   if (errMsg.contains('EMAIL_NOT_FOUND') || errMsg.contains('INVALID_PASSWORD')) {
                     // fallthrough to signUp attempt below
                   } else if (errMsg.contains('EMAIL_EXISTS')) {
                     // Unexpected: email exists but signIn failed; attempt signIn again is pointless. Proceed to throw.
                     debugPrint('AuthProvider: emulator signIn returned EMAIL_EXISTS unexpectedly');
                   }
                 } catch (_) {}
               }
             } catch (restSignInErr) {
              final msg = restSignInErr.toString().toLowerCase();
              if (msg.contains('timeout') || msg.contains('timed out')) {
                debugPrint('AuthProvider: REST signIn attempt timed out after 8s');
              } else {
                debugPrint('AuthProvider: REST signIn attempt failed: $restSignInErr');
              }
             }

             // If we reach here, attempt signUp then signIn (handle race where user doesn't exist)
             try {
               final signUpUri = Uri.parse('http://$emulatorHost:9099/identitytoolkit.googleapis.com/v1/accounts:signUp?key=any');
               final req2 = await client.postUrl(signUpUri).timeout(const Duration(seconds: 8));
               req2.headers.contentType = ContentType.json;
               final payload2 = jsonEncode({'email': email.trim(), 'password': password, 'returnSecureToken': true});
               req2.add(utf8.encode(payload2));
               final resp2 = await req2.close();
               final body2 = await resp2.transform(utf8.decoder).join();

               if (resp2.statusCode == 200) {
                 // user created; extract localId and persist
                 try {
                   final parsed2 = jsonDecode(body2) as Map<String, dynamic>;
                   final localId2 = parsed2['localId']?.toString();
                   if (localId2 != null && localId2.isNotEmpty) {
                     _uid = localId2;
                     _email = email.trim().toLowerCase();
                     try {
                       final prefs = await SharedPreferences.getInstance();
                       await prefs.setString('auth_uid', _uid!);
                       if (_email != null) await prefs.setString('auth_email', _email!);
                     } catch (_) {}
                     notifyListeners();
                     return;
                   }
                 } catch (parseErr) {
                   debugPrint('AuthProvider: failed to parse emulator signUp response: $parseErr');
                 }
               } else {
                 debugPrint('Auth emulator REST signUp failed: ${resp2.statusCode} $body2');
                 // Try to parse EMAIL_EXISTS and in that case attempt signIn once more
                 try {
                   final parsed2 = jsonDecode(body2) as Map<String, dynamic>?;
                   final errMsg2 = (parsed2 != null && parsed2['error'] is Map) ? parsed2['error']['message']?.toString() ?? '' : '';
                   if (errMsg2.contains('EMAIL_EXISTS')) {
                     // Try signIn once more
                     final signInUri2 = Uri.parse('http://$emulatorHost:9099/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=any');
                     final req3 = await client.postUrl(signInUri2).timeout(const Duration(seconds: 8));
                     req3.headers.contentType = ContentType.json;
                     final payload3 = jsonEncode({'email': email.trim(), 'password': password, 'returnSecureToken': true});
                     req3.add(utf8.encode(payload3));
                     final resp3 = await req3.close();
                     final body3 = await resp3.transform(utf8.decoder).join();
                     if (resp3.statusCode == 200) {
                       final parsed3 = jsonDecode(body3) as Map<String, dynamic>;
                       final localId3 = parsed3['localId']?.toString();
                       if (localId3 != null && localId3.isNotEmpty) {
                         _uid = localId3;
                         _email = email.trim().toLowerCase();
                         try {
                           final prefs = await SharedPreferences.getInstance();
                           await prefs.setString('auth_uid', _uid!);
                           if (_email != null) await prefs.setString('auth_email', _email!);
                         } catch (_) {}
                         notifyListeners();
                         return;
                       }
                     } else {
                       debugPrint('Auth emulator REST re-signIn after EMAIL_EXISTS failed: ${resp3.statusCode} $body3');
                     }
                   }
                 } catch (p2) {
                   debugPrint('AuthProvider: could not parse emulator signUp error body: $p2');
                 }
               }
             } catch (signUpErr) {
              final msg2 = signUpErr.toString().toLowerCase();
              if (msg2.contains('timeout') || msg2.contains('timed out')) {
                debugPrint('AuthProvider: emulator REST signUp attempt timed out after 8s');
              } else {
                debugPrint('AuthProvider: emulator REST signUp attempt failed: $signUpErr');
              }
             }
           } catch (restErr) {
             debugPrint('AuthProvider: emulator REST fallback failed: ${restErr.toString()}');
           } finally {
             try {
               client?.close(force: true);
             } catch (_) {}
           }
          }
         }
       }

       // rethrow original error for upstream handling
       rethrow;
     }
   }

  // Helper: quick TCP connect to check if emulator host:port is reachable
  Future<bool> _isHostReachable(String host, int port, Duration timeout) async {
    try {
      final socket = await Socket.connect(host, port, timeout: timeout);
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> signOut() async {
    await AuthService.instance.signOut();
    _uid = null;
    _email = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('auth_uid');
      await prefs.remove('auth_email');
    } catch (_) {}
    notifyListeners();
  }

  @override
  void dispose() {
    _fbSub?.cancel();
    _retryTimer?.cancel();
    super.dispose();
  }
}
