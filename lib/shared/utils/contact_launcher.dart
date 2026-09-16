import 'package:url_launcher/url_launcher.dart';

/// Opens WhatsApp (preferred) or the phone dialer to reach the shop,
/// used by the "Contact for price" flow and the always-visible "Contact
/// shop" affordance. `phone` comes from `settings.shop_phone`.
Future<void> launchShopContact(String phone, {String? message}) async {
  final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return;

  final whatsappUri = Uri.parse(
    'https://wa.me/$digits${message != null ? '?text=${Uri.encodeComponent(message)}' : ''}',
  );
  if (await canLaunchUrl(whatsappUri)) {
    await launchUrl(whatsappUri, mode: LaunchMode.externalApplication);
    return;
  }

  final telUri = Uri.parse('tel:$digits');
  if (await canLaunchUrl(telUri)) {
    await launchUrl(telUri);
  }
}
