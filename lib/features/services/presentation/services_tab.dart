import 'package:flutter/material.dart';

import '../../../shared/widgets/content_width.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/models/service.dart';
import '../../../shared/providers/settings_providers.dart';
import '../../../shared/utils/contact_launcher.dart';
import '../../../shared/utils/price_format.dart';
import '../../../shared/widgets/empty_state.dart';
import 'service_providers.dart';

/// Customer-facing "Services" tab (farm services like fish recovery /
/// quarantine or pond-renovation boarding) — informational cards with a
/// "Contact to book" action, no cart/checkout involved.
class ServicesTab extends ConsumerWidget {
  const ServicesTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final servicesAsync = ref.watch(servicesProvider);
    return ContentWidth(
      maxWidth: 760,
      child: servicesAsync.when(
        data: (services) {
          final active = services.where((s) => s.active).toList();
          if (active.isEmpty) {
            return const EmptyState(
              icon: Icons.room_service_outlined,
              title: 'No services listed yet',
              subtitle: 'Farm services (recovery care, pond boarding, etc.) will appear here.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.lg),
            itemCount: active.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
            itemBuilder: (context, i) => _ServiceCard(service: active[i]),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorState(
          subtitle: "We couldn't load farm services. Check your connection and retry.",
          onRetry: () => ref.invalidate(servicesProvider),
        ),
      ),
    );
  }
}

class _ServiceCard extends ConsumerWidget {
  final Service service;
  const _ServiceCard({required this.service});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      decoration: BoxDecoration(
        color: AppPalette.of(context).surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        boxShadow: AppShadows.card,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (service.imageUrls.isNotEmpty)
            SizedBox(
              height: 160,
              child: PageView(
                children: [
                  for (final url in service.imageUrls)
                    Image.network(
                      url,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      errorBuilder: (_, _, _) => ColoredBox(
                        color: AppPalette.of(context).background,
                        child: Center(
                          child: Icon(Icons.image_not_supported_outlined),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (service.category != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      service.category!.toUpperCase(),
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                        color: AppPalette.of(context).accent,
                      ),
                    ),
                  ),
                Text(
                  service.name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (service.description != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    service.description!,
                    style: TextStyle(color: AppPalette.of(context).textMuted),
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      service.showPrice && service.price != null
                          ? formatPrice(service.price!)
                          : 'Contact for price',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    ElevatedButton.icon(
                      onPressed: () async {
                        try {
                          final settings = await ref.read(
                            shopSettingsProvider.future,
                          );
                          if (!context.mounted) return;
                          final phone =
                              settings['shop_phone']?.toString() ?? '';
                          await contactShop(
                            context,
                            phone,
                            message:
                                'Hi, I\'d like to ask about "${service.name}".',
                          );
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
                      label: const Text('Contact to book'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
