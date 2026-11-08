/// Singapore delivery rules, mirroring `supabase/functions/_shared/delivery.ts`
/// so a bad phone or postal code is caught in the address form instead of
/// failing the delivery quote at checkout.
library;

final _phoneSeparators = RegExp(r'[\s()-]');
final _countryCode = RegExp(r'^\+65');
final _sgPhone = RegExp(r'^[3689]\d{7}$');
final _sgPostalCode = RegExp(r'^\d{6}$');

/// Drops spaces, brackets, dashes and a leading +65, as the server does.
String normalizeSgPhone(String value) =>
    value.replaceAll(_phoneSeparators, '').replaceFirst(_countryCode, '');

String? validateSgPhone(String? value) {
  final phone = normalizeSgPhone(value ?? '');
  if (phone.isEmpty) return 'Required';
  return _sgPhone.hasMatch(phone) ? null : 'Enter an 8-digit Singapore number';
}

String? validateSgPostalCode(String? value) {
  final code = (value ?? '').trim();
  if (code.isEmpty) return 'Required';
  return _sgPostalCode.hasMatch(code) ? null : 'Enter the 6-digit postal code';
}
