// ...existing code...

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../models/models.dart'; // for ValidationHelper
import '../providers/auth_provider.dart' as app_auth;
import '../utils/token_generator.dart';

class InviteService {
  InviteService._();
  static final InviteService instance = InviteService._();

  final FirebaseFunctions _functions = FirebaseFunctions.instance;
  final fb_auth.FirebaseAuth _auth = fb_auth.FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Creates an invite by calling the `createInvite` Cloud Function.
  ///
  /// Returns the plain token (string) on success. The token should be displayed
  /// to the user or sent by the server via email. In production the backend
  /// should send the email; this client wrapper returns whatever the function
  /// returns for convenience (typically a success message).
  Future<Map<String, dynamic>> createInvite({
    required String invitedEmail,
    required String role,
    required List<String> allowedClasses,
    int expiresInDays = 7,
  }) async {
    // Prefer AuthProvider (canonical) and only fall back to FirebaseAuth currentUser
    final userUid = app_auth.AuthProvider.instance.uid ?? _auth.currentUser?.uid;
    if (userUid == null) throw Exception('Not authenticated');

    // Validate invited email early (server-side check). This mirrors client-side validation
    final normalizedEmail = invitedEmail.trim().toLowerCase();
    if (!ValidationHelper.isValidEmail(normalizedEmail)) {
      throw ArgumentError('Invalid invited email: $invitedEmail');
    }

    try {
      final callable = _functions.httpsCallable('createInvite');
      final result = await callable.call(<String, dynamic>{
        'inviterUid': userUid,
        'invitedEmail': invitedEmail.toLowerCase(),
        'role': role,
        'allowedClasses': allowedClasses,
        'expiresInDays': expiresInDays,
      });

      if (result.data is Map<String, dynamic>) {
        return Map<String, dynamic>.from(result.data as Map);
      }
      return {'result': result.data};
    } on FirebaseFunctionsException catch (e) {
      // If function not found (not deployed) or functions disabled, fall back to
      // creating the invite directly in Firestore. This enables local-dev flow
      // without requiring server functions.
      if (e.code == 'not-found' || e.code == 'unavailable' || e.code == 'failed-precondition') {
        // Create token + hash locally using TokenGenerator for proper entropy
        final token = TokenGenerator.generate(48);
        final hash = sha256.convert(utf8.encode(token)).toString();
        final now = Timestamp.now();
        final expiresAt = Timestamp.fromDate(DateTime.now().add(Duration(days: expiresInDays)));

        final docRef = await _firestore.collection('invites').add({
          'tokenHash': hash,
          'invitedEmail': normalizedEmail,
          'role': role,
          'allowedClasses': allowedClasses,
          'expiresAt': expiresAt,
          'used': false,
          'createdBy': userUid,
          'createdAt': now,
        });

        // Create an outbox entry; a separate worker can process these or the admin console.
        final appUrl = 'https://example.app';
        final inviteLink = '$appUrl/accept-invite?token=${Uri.encodeComponent(token)}';
        final body = 'You have been invited as $role. Use this link to accept: $inviteLink';
        await _firestore.collection('email_outbox').add({
          'to': normalizedEmail,
           'subject': 'You are invited',
           'body': body,
           'metadata': {'inviteId': docRef.id, 'role': role, 'allowedClasses': allowedClasses},
           'createdAt': now,
           'sent': false,
         });

        return {'inviteId': docRef.id, 'token': token, 'message': 'Invite created locally (function not found)'};
      }
      rethrow;
    }
  }

  /// Accept an invite token by calling the `acceptInvite` Cloud Function.
  /// The user must be signed-in when calling this.
  Future<Map<String, dynamic>> acceptInvite({
    required String token,
  }) async {
    // Prefer AuthProvider.first
    final userUid = app_auth.AuthProvider.instance.uid ?? _auth.currentUser?.uid;
    final userEmail = app_auth.AuthProvider.instance.email?.toLowerCase() ?? _auth.currentUser?.email?.toLowerCase();
    if (userUid == null) throw Exception('Not authenticated');

    final callable = _functions.httpsCallable('acceptInvite');
    final result = await callable.call(<String, dynamic>{
      'token': token,
      'authUid': userUid,
      'email': userEmail,
    });

    if (result.data is Map<String, dynamic>) {
      return Map<String, dynamic>.from(result.data as Map);
    }

    return {'result': result.data};
  }

  /// List invites visible to the current user by calling `listInvites` function.
  /// Returns a normalized list of invite maps. The callable may return
  /// either a Map with an 'invites' key or a raw List; normalize both cases.
  Future<List<Map<String, dynamic>>> listInvites() async {
    final userUid = app_auth.AuthProvider.instance.uid ?? _auth.currentUser?.uid;
    if (userUid == null) throw Exception('Not authenticated');

    final callable = _functions.httpsCallable('listInvites');
    final result = await callable.call();

    final data = result.data;
    // Normalize shapes: Map with 'invites', raw List, or empty
    if (data is Map && data.containsKey('invites') && data['invites'] is List) {
      return List<Map<String, dynamic>>.from((data['invites'] as List).map((e) => e is Map ? Map<String, dynamic>.from(e) : <String, dynamic>{}));
    }

    if (data is List) {
      return List<Map<String, dynamic>>.from(data.map((e) => e is Map ? Map<String, dynamic>.from(e) : <String, dynamic>{}));
    }

    // Fallback: return an empty list if shape is unexpected
    return <Map<String, dynamic>>[];
  }

  /// Revoke an invite by inviteId using `revokeInvite` function.
  Future<Map<String, dynamic>> revokeInvite({required String inviteId}) async {
    final userUid = app_auth.AuthProvider.instance.uid ?? _auth.currentUser?.uid;
    if (userUid == null) throw Exception('Not authenticated');

    final callable = _functions.httpsCallable('revokeInvite');
    final result = await callable.call(<String, dynamic>{
      'inviteId': inviteId,
    });

    if (result.data is Map<String, dynamic>) {
      return Map<String, dynamic>.from(result.data as Map);
    }
    return {'result': result.data};
  }

  /// Helper to fetch the AppUser document for current user.
  Future<DocumentSnapshot<Map<String, dynamic>>> getCurrentAppUserDoc() async {
    final userUid = app_auth.AuthProvider.instance.uid ?? _auth.currentUser?.uid;
    if (userUid == null) throw Exception('Not authenticated');
    return _firestore.collection('users').doc(userUid).get();
  }
}
