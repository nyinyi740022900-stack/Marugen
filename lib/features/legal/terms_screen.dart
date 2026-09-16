import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Static Terms of Service. Placeholder legal text — reasonable generic
/// boilerplate for a Singapore koi/arowana e-commerce shop, but the shop
/// owner should have an actual lawyer review it before relying on it.
class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.offWhite,
      appBar: AppBar(title: const Text('Terms of Service')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: const [
          _DisclaimerBanner(),
          SizedBox(height: AppSpacing.lg),
          _Section(
            title: '1. Introduction',
            body: 'These Terms of Service ("Terms") govern your use of the Marugen Koi Farm '
                'app and your purchase of products through it, including live koi and '
                'arowana, fish food, and aquarium accessories. By creating an account or '
                'placing an order, you agree to these Terms.',
          ),
          _Section(
            title: '2. Orders & Pricing',
            body: 'All prices are shown in Singapore Dollars (SGD) and, where indicated, '
                'include Goods and Services Tax (GST). Some products may be marked '
                '"Contact us for price" and require you to reach out to the shop directly. '
                'We reserve the right to correct pricing errors and to cancel or refuse an '
                'order at our discretion, e.g. if a live fish has already been sold.',
          ),
          _Section(
            title: '3. Live Fish Guarantee',
            body: 'Every koi and arowana listed is a unique, single-stock animal. We take '
                'care to ship healthy fish and package them appropriately for transit. '
                'Please refer to our FAQ for guidance on our live-arrival guarantee and how '
                'to report an issue — claims must generally be reported with photo/video '
                'evidence within a short window of delivery.',
          ),
          _Section(
            title: '4. Payment',
            body: 'Payments are processed securely through Stripe. We do not store your '
                'card details. All payments must be completed before an order is confirmed '
                'and packed.',
          ),
          _Section(
            title: '5. Shipping & Delivery',
            body: 'Deliveries within Singapore are arranged via our courier partner. '
                'Delivery timelines are estimates and may vary due to weather, fish health '
                'and quarantine considerations, or courier delays.',
          ),
          _Section(
            title: '6. Cancellations & Refunds',
            body: 'Orders may be cancelled by the customer before they enter packing, '
                'via the order detail screen in the app. Once an order has been packed or '
                'shipped, cancellations are handled at the shop\'s discretion. Refunds, when '
                'applicable, are processed back to the original payment method.',
          ),
          _Section(
            title: '7. Account Responsibility',
            body: 'You are responsible for maintaining the confidentiality of your account '
                'credentials and for all activity under your account.',
          ),
          _Section(
            title: '8. Limitation of Liability',
            body: 'To the fullest extent permitted by Singapore law, Marugen Koi Farm is not '
                'liable for indirect or consequential losses arising from your use of the '
                'app or products purchased through it.',
          ),
          _Section(
            title: '9. Changes to These Terms',
            body: 'We may update these Terms from time to time. Continued use of the app '
                'after changes take effect constitutes acceptance of the revised Terms.',
          ),
          _Section(
            title: '10. Contact',
            body: 'Questions about these Terms can be sent to the shop via the "Contact us" '
                'option in the app.',
          ),
        ],
      ),
    );
  }
}

class _DisclaimerBanner extends StatelessWidget {
  const _DisclaimerBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.redSoft,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: const Text(
        'This is placeholder legal text for demonstration purposes. Please have a '
        'qualified lawyer review and finalize these Terms before relying on them.',
        style: TextStyle(fontSize: 12.5, color: AppColors.redDark, height: 1.4),
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
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 6),
          Text(body, style: const TextStyle(fontSize: 13.5, height: 1.5, color: AppColors.black)),
        ],
      ),
    );
  }
}
