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

  const AppUser({
    required this.id,
    this.email,
    this.phone,
    this.fullName,
    this.avatarUrl,
    this.role = UserRole.customer,
    this.notificationsEnabled = true,
  });

  factory AppUser.fromMap(Map<String, dynamic> map) {
    return AppUser(
      id: map['id'] as String,
      email: map['email'] as String?,
      phone: map['phone'] as String?,
      fullName: map['full_name'] as String?,
      avatarUrl: map['avatar_url'] as String?,
      role: userRoleFromString(map['role'] as String?),
      notificationsEnabled: map['notifications_enabled'] as bool? ?? true,
    );
  }
}
