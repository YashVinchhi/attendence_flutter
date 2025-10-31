import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/models.dart';
import '../services/invite_service.dart';
import 'auth_provider.dart';

class UserProvider extends ChangeNotifier {
  UserProvider._();
  static final UserProvider instance = UserProvider._();

  AppUser? _user;
  bool _initialized = false;

  // Firestore subscription for users/{uid}
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;
  String? _listeningUid;

  AppUser? get user => _user;
  bool get isInitialized => _initialized;
  bool get isLoggedIn => _user != null;
  List<String> get permissions => _user?.permissions ?? [];

  bool hasPermission(String p) => _user != null && (_user!.permissions.contains(p) || _user!.role == UserRole.ADMIN || _user!.role == UserRole.HOD);

  bool get isHod => _user != null && _user!.role == UserRole.HOD;
  bool get isCc => _user != null && _user!.role == UserRole.CC;
  bool get isCr => _user != null && _user!.role == UserRole.CR;

  /// Load the current AppUser document for the logged-in auth uid.
  /// Safe to call multiple times; will no-op if already initialized.
  Future<void> initialize() async {
    if (_initialized) return;
    final authUid = AuthProvider.instance.uid;
    if (authUid == null) {
      _initialized = true;
      notifyListeners();
      return;
    }
    // If superadmin local bypass is in use, create local admin user without Firestore
    if (authUid == 'superadmin_local') {
      _user = AppUser(
        id: null,
        uid: authUid,
        email: AuthProvider.instance.email ?? '',
        name: 'Super Admin',
        role: UserRole.ADMIN,
        allowedClasses: [],
        isActive: true,
        createdAt: DateTime.now(),
      );
      _initialized = true;
      notifyListeners();
      return;
    }
    // Start listening so UI updates in real-time
    _startListening(authUid);
    _initialized = true;
    notifyListeners();
  }

  void _startListening(String uid) {
    if (_listeningUid == uid && _sub != null) return;
    // Cancel any existing subscription
    _sub?.cancel();
    _listeningUid = uid;
    _sub = FirebaseFirestore.instance.collection('users').doc(uid).snapshots().listen((snap) {
      if (snap.exists) {
        try {
          final data = snap.data() ?? {};
          _user = AppUser.fromMap(data);
        } catch (e) {
          _user = null;
        }
      } else {
        _user = null;
      }
      notifyListeners();
    }, onError: (err) {
      // On stream error, clear user but keep subscription active (it may recover)
      _user = null;
      notifyListeners();
    });
  }

  /// Force refresh of the AppUser document from Firestore.
  Future<void> refresh() async {
    final authUid = AuthProvider.instance.uid;
    if (authUid == null) {
      _user = null;
      // Cancel subscription if any
      _sub?.cancel();
      _sub = null;
      _listeningUid = null;
      notifyListeners();
      return;
    }

    // Superadmin local short-circuit
    if (authUid == 'superadmin_local') {
      _user = AppUser(
        id: null,
        uid: authUid,
        email: AuthProvider.instance.email ?? '',
        name: 'Super Admin',
        role: UserRole.ADMIN,
        allowedClasses: [],
        isActive: true,
        createdAt: DateTime.now(),
      );
      notifyListeners();
      return;
    }

    // Ensure we are listening to the right uid
    if (_listeningUid != authUid) {
      _startListening(authUid);
      return;
    }

    try {
      final docSnap = await InviteService.instance.getCurrentAppUserDoc();
      if (docSnap.exists) {
        final data = docSnap.data() ?? {};
        _user = AppUser.fromMap(data);
      } else {
        _user = null;
      }
    } catch (e) {
      // On error, set user to null but don't throw (UI can decide what to do)
      _user = null;
    }
    notifyListeners();
  }

  String? get role => _user?.role.name;
  List<String> get allowedClasses => _user?.allowedClasses.map((c) => c.displayName).toList() ?? [];
  bool get isAdmin => _user != null && (_user!.role == UserRole.HOD || _user!.role == UserRole.ADMIN);

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
