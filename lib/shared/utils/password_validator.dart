/// Shared password-strength check for the two screens that create a new
/// password (signup, password reset) — sign-in's own password field is
/// deliberately NOT validated against this (see login_screen.dart), since
/// a real account created before this tightened must never be locked out
/// of signing in by a stricter client-side rule.
///
/// At least 8 characters plus one letter and one digit; not a
/// complexity-scoring meter, just enough to rule out "123456"/"password"-
/// style throwaway values.
String? validateNewPassword(String? value) {
  if (value == null || value.length < 8) return 'Minimum 8 characters';
  if (!value.contains(RegExp(r'[A-Za-z]')) || !value.contains(RegExp(r'[0-9]'))) {
    return 'Must include at least one letter and one number';
  }
  return null;
}
