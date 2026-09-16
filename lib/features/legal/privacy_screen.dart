import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Static Privacy Policy. Placeholder legal text — reasonable generic
/// boilerplate for a Singapore koi/arowana e-commerce shop, but the shop
/// owner should have an actual lawyer review it before relying on it.
class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.offWhite,
      appBar: AppBar(title: const Text('Privacy Policy')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: const [
          _DisclaimerBanner(),
          SizedBox(height: AppSpacing.lg),
          _Section(
            title: '1. Overview',
            body: 'This Privacy Policy explains what personal data Marugen Koi Farm '
                'collects through this app, how it\'s used, and the choices you have. We '
                'aim to comply with Singapore\'s Personal Data Protection Act (PDPA).',
          ),
          _Section(
            title: '2. Information We Collect',
            body: 'Account details (name, email, phone), delivery addresses, order and '
                'payment history (payments themselves are processed by Stripe — we do not '
                'store your card numbers), wishlist and review activity, and device push '
                'notification tokens used to send you order updates.',
          ),
          _Section(
            title: '3. How We Use Your Information',
            body: 'To process and deliver orders, provide customer support, send order '
                'status notifications, show your order history and reviews, and improve the '
                'app and our catalog.',
          ),
          _Section(
            title: '4. Sharing of Information',
            body: 'We share the minimum necessary data with service providers to run the '
                'shop: Stripe for payment processing, our courier partner for delivery, and '
                'Supabase/Firebase for app infrastructure and notifications. We do not sell '
                'your personal data.',
          ),
          _Section(
            title: '5. Data Retention',
            body: 'We retain order and account data for as long as your account is active '
                'and as needed to comply with accounting and tax obligations.',
          ),
          _Section(
            title: '6. Your Rights',
            body: 'You may request access to, correction of, or deletion of your personal '
                'data by contacting the shop. You can also update your profile and '
                'addresses directly in the app, and delete individual reviews at any time.',
          ),
          _Section(
            title: '7. Security',
            body: 'We use industry-standard measures (encrypted connections, row-level '
                'access controls on our database, and PCI-compliant payment processing via '
                'Stripe) to protect your data.',
          ),
          _Section(
            title: '8. Changes to This Policy',
            body: 'We may update this Privacy Policy from time to time. Continued use of '
                'the app after changes take effect constitutes acceptance of the revised '
                'policy.',
          ),
          _Section(
            title: '9. Contact',
            body: 'Questions about this Privacy Policy or your data can be sent to the shop '
                'via the "Contact us" option in the app.',
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
        'qualified lawyer review and finalize this policy before relying on it.',
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
