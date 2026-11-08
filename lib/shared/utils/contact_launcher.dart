import 'package:flutter/material.dart';
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

enum _ContactChannel { whatsApp, call }

/// Lets the customer choose WhatsApp or a phone call to reach the shop, for
/// "Contact for price" and the always-visible "Contact shop" button. The
/// wa.me link used to win every time — it opens a web page when WhatsApp is
/// missing — so customers without WhatsApp never reached the dialer.
/// `phone` comes from `settings.shop_phone`.
Future<void> contactShop(
  BuildContext context,
  String phone, {
  String? message,
}) async {
  final digits = internationalDigits(phone);
  if (digits.isEmpty) {
    _showContactProblem(context);
    return;
  }
  final channel = await showModalBottomSheet<_ContactChannel>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.chat_outlined),
            title: const Text('WhatsApp'),
            subtitle: const Text('Message the shop'),
            onTap: () => Navigator.pop(sheetContext, _ContactChannel.whatsApp),
          ),
          ListTile(
            leading: const Icon(Icons.call_outlined),
            title: const Text('Call'),
            subtitle: Text('+$digits'),
            onTap: () => Navigator.pop(sheetContext, _ContactChannel.call),
          ),
        ],
      ),
    ),
  );
  if (channel == null) return;
  var opened = false;
  try {
    opened = await launchUrl(
      channel == _ContactChannel.whatsApp
          ? whatsAppUri(digits, message: message)
          : Uri.parse('tel:+$digits'),
      mode: LaunchMode.externalApplication,
    );
  } catch (_) {
    // Recover in this screen rather than exposing a platform exception.
  }
  if (!opened && context.mounted) _showContactProblem(context);
}

void _showContactProblem(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text(
        'Could not open shop contact. Try again or use FAQ & Support in your profile.',
      ),
    ),
  );
}
