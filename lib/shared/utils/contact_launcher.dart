import 'package:url_launcher/url_launcher.dart';

/// wa.me and tel: links need the country code, and Singapore numbers are
/// usually saved as just their 8 digits (addresses store them that way).
String internationalDigits(String phone) {
  final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
  return RegExp(r'^[3689]\d{7}$').hasMatch(digits) ? '65$digits' : digits;
}

Uri whatsAppUri(String digits, {String? message}) => Uri.parse(
  'https://wa.me/$digits${message != null ? '?text=${Uri.encodeComponent(message)}' : ''}',
);

/// Opens WhatsApp (preferred) or the phone dialer to reach [phone] — staff
/// contacting a buyer about an order.
Future<bool> launchShopContact(String phone, {String? message}) async {
  final digits = internationalDigits(phone);
  if (digits.isEmpty) return false;

  final whatsappUri = whatsAppUri(digits, message: message);
  if (await canLaunchUrl(whatsappUri)) {
    if (await launchUrl(whatsappUri, mode: LaunchMode.externalApplication)) {
      return true;
    }
  }

  final telUri = Uri.parse('tel:+$digits');
  if (await canLaunchUrl(telUri)) {
    return launchUrl(telUri);
  }
  return false;
}
