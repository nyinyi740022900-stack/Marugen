import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Customer-facing terms for use of the shop and product orders.
class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.of(context).background,
      appBar: AppBar(title: const Text('Terms of Service')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: const [
          _Section(
            title: '1. Introduction',
            body:
                'These Terms of Service ("Terms") govern your use of the Marugen Fish Farm '
                'app and your purchase of products through it. By creating an account or '
                'placing an order, you agree to these Terms.',
          ),
          _Section(
            title: '2. Orders & Pricing',
            body:
                'All prices are shown in Singapore Dollars (SGD) and, where indicated, '
                'include Goods and Services Tax (GST). Some products may be marked '
                '"Contact us for price" and require you to reach out to the shop directly. '
                'We reserve the right to correct pricing errors and to cancel or refuse an '
                'order at our discretion, for example when a product is no longer available.',
          ),
          _Section(
            title: '3. Product Information & Support',
            body:
                'Please check the product description, selected option and quantity before '
                'ordering. If an item is missing, damaged or different from your order, '
                'contact the shop with your order number and relevant photos so we can '
                'review the issue and explain the available next steps.',
          ),
          _Section(
            title: '4. Payment',
            body:
                'Payments are processed securely through Stripe. We do not store your '
                'card details. All payments must be completed before an order is confirmed '
                'and packed.',
          ),
          _Section(
            title: '5. Shipping & Delivery',
            body:
                'Deliveries within Singapore are arranged by the shop or a delivery partner. '
                'Any delivery fee is shown at checkout before payment. Delivery dates are '
                'estimates and may vary due to order preparation, weather or courier delays.',
          ),
          _Section(
            title: '6. Cancellations & Refunds',
            body:
                'Orders may be cancelled by the customer before they enter packing, '
                'via the order detail screen in the app. Once an order has been packed or '
                'shipped, cancellations are handled at the shop\'s discretion. Refunds, when '
                'applicable, are processed back to the original payment method.',
          ),
          _Section(
            title: '7. Account Responsibility',
            body:
                'You are responsible for maintaining the confidentiality of your account '
                'credentials and for all activity under your account.',
          ),
          _Section(
            title: '8. Limitation of Liability',
            body:
                'To the fullest extent permitted by Singapore law, Marugen Fish Farm is not '
                'liable for indirect or consequential losses arising from your use of the '
                'app or products purchased through it.',
          ),
          _Section(
            title: '9. Changes to These Terms',
            body:
                'We may update these Terms from time to time. Continued use of the app '
                'after changes take effect constitutes acceptance of the revised Terms.',
          ),
          _Section(
            title: '10. Contact',
            body:
                'Questions about these Terms can be sent to the shop via the "Contact us" '
                'option in the app.',
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
