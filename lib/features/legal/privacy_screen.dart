import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'privacy_content.dart';

import '../../core/theme/app_theme.dart';

/// Privacy policy for the Marugen app and website.
class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.of(context).background,
      appBar: AppBar(title: const Text('Privacy Policy')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          const _PrivacyContact(),
          const SizedBox(height: AppSpacing.lg),
          for (final section in privacySections)
            _Section(title: section.title, body: section.body),
        ],
      ),
    );
  }
}

class _PrivacyContact extends StatelessWidget {
  const _PrivacyContact();

  Future<void> _open(BuildContext context, Uri uri) async {
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    } catch (_) {
      // The address stays selectable when no email/browser app is available.
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please email $privacyContactEmail to make your request.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Privacy contact',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const SelectableText(privacyContactEmail),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => _open(
                context,
                Uri(
                  scheme: 'mailto',
                  path: privacyContactEmail,
                  query: 'subject=Marugen%20data%20request',
                ),
              ),
              icon: const Icon(Icons.mail_outline),
              label: const Text('Email a privacy request'),
            ),
            TextButton.icon(
              onPressed: () => _open(context, Uri.parse(dataDeletionUrl)),
              icon: const Icon(Icons.open_in_new),
              label: const Text('Account & data deletion'),
            ),
          ],
        ),
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
