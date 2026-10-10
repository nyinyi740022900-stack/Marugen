import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens WhatsApp (preferred) or the phone dialer to reach the shop,
/// used by the "Contact for price" flow and the always-visible "Contact
/// shop" affordance. `phone` comes from `settings.shop_phone`.
Future<bool> launchShopContact(String phone, {String? message}) async {
  final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return false;

  final whatsappUri = Uri.parse(
    'https://wa.me/$digits${message != null ? '?text=${Uri.encodeComponent(message)}' : ''}',
  );
  if (await canLaunchUrl(whatsappUri)) {
    if (await launchUrl(whatsappUri, mode: LaunchMode.externalApplication)) {
      return true;
    }
  }

  final telUri = Uri.parse('tel:$digits');
  if (await canLaunchUrl(telUri)) {
    return launchUrl(telUri);
  }
  return false;
}

/// A contact action must explain a missing number or unavailable external app.
Future<void> contactShop(
  BuildContext context,
  String phone, {
  String? message,
}) async {
  try {
    if (await launchShopContact(phone, message: message)) return;
  } catch (_) {
    // Recover in this screen rather than exposing a platform exception.
  }
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text(
        'Could not open shop contact. Try again or use FAQ & Support in your profile.',
      ),
    ),
  );
}
