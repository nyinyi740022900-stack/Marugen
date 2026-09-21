import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../providers/settings_providers.dart';
import 'fullscreen_image_gallery.dart';

/// Promotional image popup shown once per device per day when a customer
/// opens the app — the photo and on/off toggle are admin-managed (Settings
/// → Promotion Banner), not hardcoded. Device-scoped (not per-account, per
/// the "one device one time per day" requirement), so a shared/guest
/// device sees it independent of who's logged in.
class PromoBannerDialog {
  static const _lastShownKey = 'promo_banner_last_shown_date_v1';

  static Future<void> maybeShow(BuildContext context, WidgetRef ref) async {
    try {
      final settings = await ref.read(shopSettingsProvider.future);
      final active = settings['promo_banner_active'] as bool? ?? false;
      final imageUrl = settings['promo_banner_image_url'] as String?;
      if (!active || imageUrl == null || imageUrl.isEmpty) return;

      final prefs = await SharedPreferences.getInstance();
      final today = DateTime.now().toIso8601String().substring(0, 10);
      if (prefs.getString(_lastShownKey) == today) return;
      await prefs.setString(_lastShownKey, today);

      if (!context.mounted) return;
      final linkUrl = settings['promo_banner_link_url'] as String?;
      await showDialog<void>(
        context: context,
        barrierDismissible: true,
        barrierColor: AppColors.black.withValues(alpha: 0.6),
        builder: (_) => _PromoBannerCard(imageUrl: imageUrl, linkUrl: linkUrl),
      );
    } catch (_) {
      // Non-fatal — a promo popup failing to load should never block the
      // shop itself from opening.
    }
  }
}

class _PromoBannerCard extends StatelessWidget {
  final String imageUrl;
  final String? linkUrl;
  const _PromoBannerCard({required this.imageUrl, this.linkUrl});

  Future<void> _openLink() async {
    final url = linkUrl;
    if (url == null || url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    // A fixed placeholder/error width (not just maxHeight) so the dialog
    // doesn't render as a tiny spinner-sized box on a slow connection and
    // then visibly jump to full width once the image loads.
    final size = MediaQuery.of(context).size;
    final maxHeight = size.height * 0.6;
    final placeholderWidth = size.width - AppSpacing.xl * 2;
    return Dialog(
      backgroundColor: Colors.transparent,
      // Explicit vertical inset (not just horizontal) so the card — and
      // the close button floating above it — stay clear of the status
      // bar/notch on shorter screens or tall banner images, instead of
      // falling back to 0 from an unspecified EdgeInsets.symmetric side.
      insetPadding: EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: MediaQuery.of(context).padding.top + AppSpacing.xl,
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            child: GestureDetector(
              onTap: linkUrl != null && linkUrl!.isNotEmpty ? _openLink : null,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxHeight),
                child: CachedNetworkImage(
                  imageUrl: imageUrl,
                  fit: BoxFit.contain,
                  placeholder: (_, _) => SizedBox(
                    height: 200,
                    width: placeholderWidth,
                    child: const Center(
                      child: CircularProgressIndicator(color: AppColors.red),
                    ),
                  ),
                  errorWidget: (_, _, _) => SizedBox(
                    height: 200,
                    width: placeholderWidth,
                    child: const Center(
                      child: Icon(
                        Icons.image_not_supported_outlined,
                        color: AppColors.greySoft,
                        size: 40,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: -14,
            right: -14,
            child: CircleIconButton(
              icon: Icons.close,
              tooltip: 'Close',
              backgroundColor: AppColors.black,
              onTap: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    );
  }
}
