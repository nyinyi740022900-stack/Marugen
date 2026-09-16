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
  final UserRole role;

  const AppUser({
    required this.id,
    this.email,
    this.phone,
    this.fullName,
    this.role = UserRole.customer,
  });

  factory AppUser.fromMap(Map<String, dynamic> map) {
    return AppUser(
      id: map['id'] as String,
      email: map['email'] as String?,
      phone: map['phone'] as String?,
      fullName: map['full_name'] as String?,
      role: userRoleFromString(map['role'] as String?),
    );
  }
}
