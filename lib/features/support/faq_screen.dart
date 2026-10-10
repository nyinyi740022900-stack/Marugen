import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/providers/settings_providers.dart';
import '../../shared/utils/contact_launcher.dart';

class _Faq {
  final String question;
  final String answer;
  const _Faq(this.question, this.answer);
}

const _faqs = [
  _Faq(
    'Where do you deliver?',
    'We currently deliver island-wide across Singapore via our courier partner. '
        'Delivery timelines may vary slightly for live fish due to weather and '
        'health/quarantine considerations.',
  ),
  _Faq(
    'Do you guarantee live fish on arrival?',
    'Yes — we package every koi and arowana carefully for transit. If a fish arrives '
        'unwell, please contact us with photos/video within 24 hours of delivery so we '
        'can help make it right.',
  ),
  _Faq(
    'What payment methods do you accept?',
    'We accept credit/debit cards and other methods supported by Stripe (e.g. Apple '
        'Pay, Google Pay, PayNow, depending on availability) directly at checkout in the '
        'app.',
  ),
  _Faq(
    'A product says "Contact us for price" — how do I order it?',
    'Tap "Contact Us for Price" on the product page to message us on WhatsApp with the '
        'product pre-filled. We\'ll confirm price and availability with you directly.',
  ),
  _Faq(
    'Can I cancel my order?',
    'Yes, as long as it hasn\'t been packed yet. Open the order from your Order History '
        'and tap "Cancel Order". Once an order is packing/shipped, please contact us '
        'directly.',
  ),
  _Faq(
    'How do I track my order?',
    'Once your order ships, a tracking number will appear on the order detail screen. '
        'You\'ll also get a notification as your order moves through each stage.',
  ),
  _Faq(
    'Do you offer promo codes?',
    'From time to time — enter any active promo code at checkout in the "Promo Code" '
        'field to apply a discount before you pay.',
  ),
  _Faq(
    'How do I leave a review?',
    'After you\'ve received a product, visit its product page and tap "Write a Review" '
        'to leave a star rating and comment.',
  ),
];

/// Simple expandable FAQ list — reachable from [ProfileScreen] and
/// alongside the app-wide "contact shop" affordance.
class FaqScreen extends ConsumerWidget {
  const FaqScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppPalette.of(context).background,
      appBar: AppBar(title: const Text('FAQ & Support')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          for (final faq in _faqs)
            Container(
              margin: const EdgeInsets.only(bottom: AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppPalette.of(context).surface,
                borderRadius: BorderRadius.circular(AppRadius.md),
                boxShadow: AppShadows.card,
              ),
              clipBehavior: Clip.antiAlias,
              child: Theme(
                data: Theme.of(context)
                    .copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  title: Text(
                    faq.question,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13.5,
                    ),
                  ),
                  childrenPadding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    0,
                    AppSpacing.lg,
                    AppSpacing.lg,
                  ),
                  expandedCrossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      faq.answer,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.5,
                        color: AppPalette.of(context).textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: AppSpacing.lg),
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: AppPalette.of(context).surface,
              borderRadius: BorderRadius.circular(AppRadius.md),
              boxShadow: AppShadows.card,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Still need help? Message the shop directly.',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: AppSpacing.md),
                ElevatedButton.icon(
                  onPressed: () async {
                    try {
                      final settings = await ref.read(
                        shopSettingsProvider.future,
                      );
                      if (!context.mounted) return;
                      final phone = settings['shop_phone'] as String? ?? '';
                      await contactShop(context, phone);
                    } catch (_) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Could not load shop contact. Check your connection and try again.',
                            ),
                          ),
                        );
                      }
                    }
                  },
                  icon: const Icon(Icons.chat_bubble_outline, size: 16),
                  label: const Text('Contact Us'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
