// A tiny invite repository abstraction plus an in-memory implementation.
// Used for UI development and tests. Replace with a real implementation
// that calls your backend (e.g. via Firebase Cloud Functions) when ready.

import 'dart:collection';
import 'package:uuid/uuid.dart';
import '../models/invite.dart';

abstract class InviteRepository {
  Future<Invite> createInvite({
    required String invitedEmail,
    required String role,
    required List<String> allowedClasses,
    required int expiresInDays,
  });

  Future<List<Invite>> listInvites();

  Future<Invite?> getById(String id);
}

/// In-memory repository implementation (singleton) for quick UI demos.
class InMemoryInviteRepository implements InviteRepository {
  InMemoryInviteRepository._internal();

  static final InMemoryInviteRepository instance = InMemoryInviteRepository._internal();

  final _items = <String, Invite>{};
  final _uuid = const Uuid();

  @override
  Future<Invite> createInvite({
    required String invitedEmail,
    required String role,
    required List<String> allowedClasses,
    required int expiresInDays,
  }) async {
    final now = DateTime.now().toUtc();
    final id = _uuid.v4();
    final invite = Invite(
      id: id,
      invitedEmail: invitedEmail.toLowerCase(),
      role: role,
      allowedClasses: allowedClasses,
      createdAt: now,
      expiresAt: now.add(Duration(days: expiresInDays)),
    );

    _items[id] = invite;
    return invite;
  }

  @override
  Future<List<Invite>> listInvites() async => UnmodifiableListView(_items.values).toList();

  @override
  Future<Invite?> getById(String id) async => _items[id];
}
