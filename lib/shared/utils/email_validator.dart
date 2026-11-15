/// Shared email check for the auth forms. Not RFC-complete on purpose:
/// it catches the typos people actually make (missing domain, spaces,
/// no dot after the @) without rejecting unusual but valid addresses.
final _email = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');

bool isValidEmail(String? value) {
  final v = value?.trim() ?? '';
  return v.isNotEmpty && _email.hasMatch(v);
}

String? validateEmail(String? value) =>
    isValidEmail(value) ? null : 'Enter a valid email address';
