// Simple Invite model used by client-side code.

class Invite {
  final String id;
  final String invitedEmail;
  final String role;
  final List<String> allowedClasses;
  final DateTime createdAt;
  final DateTime expiresAt;
  final String status; // e.g. 'pending', 'accepted', 'expired'

  Invite({
    required this.id,
    required this.invitedEmail,
    required this.role,
    required this.allowedClasses,
    required this.createdAt,
    required this.expiresAt,
    this.status = 'pending',
  });

  factory Invite.fromJson(Map<String, dynamic> json) {
    return Invite(
      id: json['id'] as String,
      invitedEmail: json['invitedEmail'] as String,
      role: json['role'] as String,
      allowedClasses: (json['allowedClasses'] as List<dynamic>?)?.map((e) => e as String).toList() ?? [],
      createdAt: DateTime.parse(json['createdAt'] as String),
      expiresAt: DateTime.parse(json['expiresAt'] as String),
      status: json['status'] as String? ?? 'pending',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'invitedEmail': invitedEmail,
        'role': role,
        'allowedClasses': allowedClasses,
        'createdAt': createdAt.toIso8601String(),
        'expiresAt': expiresAt.toIso8601String(),
        'status': status,
      };
}

