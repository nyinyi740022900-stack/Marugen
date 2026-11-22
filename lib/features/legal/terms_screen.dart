import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/providers/settings_providers.dart';
import '../orders/utils/checkout_totals.dart' show gstPercentText;

/// The GST sentence of the Terms, from the shop's settings (Admin ›
/// Settings). Until the settings are known, and at a 0% rate, the shop is
/// not GST-registered and charges none.
String termsGstSentence(Map<String, dynamic>? settings) {
  final percent = (settings?['gst_percent'] as num?)?.toDouble() ?? 0;
  if (settings == null || percent <= 0) {
    return 'Marugen Fish Farm is not GST-registered, so no GST is charged.';
  }
  final rate = '${gstPercentText(percent)}%';
  final included = settings['gst_included_in_price'] as bool? ?? true;
  return included
      ? 'Prices include Goods and Services Tax (GST) at $rate.'
      : 'Goods and Services Tax (GST) at $rate is added at checkout.';
}

/// Customer-facing terms for use of the shop and product orders.
class TermsScreen extends ConsumerWidget {
  const TermsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gstSentence = termsGstSentence(
      ref.watch(shopSettingsProvider).valueOrNull,
    );
    return Scaffold(
      backgroundColor: AppPalette.of(context).background,
      appBar: AppBar(title: const Text('Terms of Service')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          const _Section(
            title: '1. Introduction',
            body:
                'These Terms of Service ("Terms") govern your use of the Marugen Fish Farm '
                'app and your purchase of products through it. By creating an account or '
                'placing an order, you agree to these Terms.',
          ),
          _Section(
            title: '2. Orders & Pricing',
            body:
                'All prices are shown in Singapore Dollars (SGD). $gstSentence '
                'Some products may be marked '
                '"Contact us for price" and require you to reach out to the shop directly. '
                'We reserve the right to correct pricing errors and to cancel or refuse an '
                'order at our discretion, for example when a product is no longer available.',
          ),
          const _Section(
            title: '3. Product Information & Support',
            body:
                'Please check the product description, selected option and quantity before '
                'ordering. If an item is missing, damaged or different from your order, '
                'contact the shop with your order number and relevant photos so we can '
                'review the issue and explain the available next steps.',
          ),
          const _Section(
            title: '4. Payment',
            body:
                'Payments are processed securely through Stripe. We do not store your '
                'card details. All payments must be completed before an order is confirmed '
                'and packed.',
          ),
          const _Section(
            title: '5. Shipping & Delivery',
            body:
                'Deliveries within Singapore are arranged by the shop or a delivery partner. '
                'Any delivery fee is shown at checkout before payment. Delivery dates are '
                'estimates and may vary due to order preparation, weather or courier delays.',
          ),
          const _Section(
            title: '6. Cancellations & Refunds',
            body:
                'An order that has not been paid for can be cancelled by the customer '
                'from the order page in the app. After payment, you can send a '
                'cancellation request from the order page while the order has no '
                'delivery booking; the shop reviews each request, and sending one does '
                'not by itself cancel the order or issue a refund. Once delivery has '
                'been booked or the order has shipped, contact the shop. Refunds, when '
                'approved, are made to the original payment method.',
          ),
          const _Section(
            title: '7. Live Fish',
            body:
                'Each live fish is a unique animal and is packed for transit. If a fish '
                'arrives unwell, contact the shop within 24 hours of delivery with your '
                'order number and relevant photos, so we can review it and explain '
                'the available next steps.',
          ),
          const _Section(
            title: '8. Account Responsibility',
            body:
                'You are responsible for maintaining the confidentiality of your account '
                'credentials and for all activity under your account.',
          ),
          const _Section(
            title: '9. Limitation of Liability',
            body:
                'To the fullest extent permitted by Singapore law, Marugen Fish Farm is not '
                'liable for indirect or consequential losses arising from your use of the '
                'app or products purchased through it.',
          ),
          const _Section(
            title: '10. Changes to These Terms',
            body:
                'We may update these Terms from time to time. Continued use of the app '
                'after changes take effect constitutes acceptance of the revised Terms.',
          ),
          const _Section(
            title: '11. Contact',
            body:
                'Questions about these Terms can be sent to the shop from '
                'Profile › FAQ & Support › Contact Support in the app.',
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final String body;
  const _Section({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: TextStyle(
              fontSize: 13.5,
              height: 1.5,
              color: AppPalette.of(context).text,
            ),
          ),
        ],
      ),
    );
  }
}
