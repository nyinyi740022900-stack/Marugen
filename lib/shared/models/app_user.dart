import '../utils/server_time.dart';

enum UserRole { customer, staff, owner }

UserRole userRoleFromString(String? value) {
  switch (value) {
    case 'owner':
      return UserRole.owner;
    case 'staff':
      return UserRole.staff;
    default:
      return UserRole.customer;
  }
}

extension UserRoleX on UserRole {
  /// Owners and staff both see the admin side of the app.
  bool get isAdmin => this == UserRole.owner || this == UserRole.staff;
}

class AppUser {
  final String id;
  final String? email;
  final String? phone;
  final String? fullName;
  final String? avatarUrl;
  final UserRole role;
  final bool notificationsEnabled;
  final DateTime? createdAt;

  /// Signs in with email and password (not Google or Apple), so Profile
  /// offers "Change password". Comes from the auth session, not the row.
  final bool usesPassword;

  const AppUser({
    required this.id,
    this.email,
    this.phone,
    this.fullName,
    this.avatarUrl,
    this.role = UserRole.customer,
    this.notificationsEnabled = true,
    this.createdAt,
    this.usesPassword = false,
  });

  factory AppUser.fromMap(
    Map<String, dynamic> map, {
    bool usesPassword = false,
  }) {
    return AppUser(
      id: map['id'] as String,
      email: map['email'] as String?,
      phone: map['phone'] as String?,
      fullName: map['full_name'] as String?,
      avatarUrl: map['avatar_url'] as String?,
      role: userRoleFromString(map['role'] as String?),
      notificationsEnabled: map['notifications_enabled'] as bool? ?? true,
      createdAt: map['created_at'] != null
          ? tryParseServerTime(map['created_at'])
          : null,
      usesPassword: usesPassword,
    );
  }
}
