import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/providers/app_version_provider.dart';
import '../../../shared/widgets/support_contact_picker.dart';

/// Help and legal rows of the Profile tab. Shown to guests as well: nobody
/// should have to create an account to read the terms or ask a question.
class ProfileHelpTiles extends ConsumerWidget {
  const ProfileHelpTiles({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watched so the version is ready by the time the row is tapped.
    final version = ref.watch(appVersionProvider).valueOrNull;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          leading: const Icon(Icons.help_outline),
          title: const Text('FAQ & Support'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/faq'),
        ),
        ListTile(
          leading: const Icon(Icons.rate_review_outlined),
          title: const Text('Send feedback'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => showSupportContactPicker(
            context,
            message: feedbackMessagePrefix(version),
            // Nothing account-specific in it, so guests can send it too.
            messageIsPersonal: false,
          ),
        ),
        ListTile(
          leading: const Icon(Icons.description_outlined),
          title: const Text('Terms of Service'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/terms'),
        ),
        ListTile(
          leading: const Icon(Icons.privacy_tip_outlined),
          title: const Text('Privacy Policy'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/privacy'),
        ),
      ],
    );
  }
}

/// "Version 1.0.27 (32)" at the bottom of Profile, so a tester can say
/// which build they are on. Takes no space until the platform answers.
class AppVersionFooter extends ConsumerWidget {
  const AppVersionFooter({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final version = ref.watch(appVersionProvider).valueOrNull;
    if (version == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.lg, bottom: AppSpacing.sm),
      child: Text(
        'Version ${version.label}',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 12.5,
          color: AppPalette.of(context).textMuted,
        ),
      ),
    );
  }
}
