import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../features/auth/presentation/auth_providers.dart';
import '../models/support_contact.dart';
import '../providers/settings_providers.dart';

/// Choose a support colleague and an explicit contact channel.
///
/// A [message] about an order belongs to the account that opened the picker
/// and is withheld if the account changes. Pass [messageIsPersonal] false
/// for a message with nothing private in it (app feedback), which a guest
/// may send too.
Future<void> showSupportContactPicker(
  BuildContext context, {
  String? message,
  bool messageIsPersonal = true,
}) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(title: const Text('Contact Support')),
        body: SupportContactPicker(
          message: message,
          messageIsPersonal: messageIsPersonal,
        ),
      ),
    ),
  );
}

class SupportContactPicker extends ConsumerStatefulWidget {
  final String? message;
  final bool messageIsPersonal;
  const SupportContactPicker({
    super.key,
    this.message,
    this.messageIsPersonal = true,
  });

  @override
  ConsumerState<SupportContactPicker> createState() =>
      _SupportContactPickerState();
}

class _SupportContactPickerState extends ConsumerState<SupportContactPicker> {
  bool _opening = false;
  String? _messageAccountId;

  @override
  void initState() {
    super.initState();
    if (_guardsMessage) {
      _messageAccountId = ref.read(currentUserIdProvider);
    }
  }

  bool get _guardsMessage => widget.message != null && widget.messageIsPersonal;

  bool get _canShareMessage =>
      !_guardsMessage ||
      (_messageAccountId != null &&
          ref.read(currentUserIdProvider) == _messageAccountId);

  Future<void> _open(SupportContact contact, SupportChannel channel) async {
    // Check again at the external-app boundary, including a retained callback.
    if (!_canShareMessage || _opening) return;
    setState(() => _opening = true);
    var opened = false;
    try {
      opened = await launchUrl(
        contact.uri(channel, message: widget.message),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      // A missing external application is recoverable in this picker.
    }
    if (!mounted) return;
    setState(() => _opening = false);
    if (!opened) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not open this contact channel. Try another channel or try again.',
          ),
        ),
      );
    }
  }

  Widget _recovery(String message) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      Text(message),
      const SizedBox(height: 16),
      OutlinedButton(
        onPressed: () => ref.invalidate(shopSettingsProvider),
        style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
        child: const Text('Retry'),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    if (_guardsMessage) {
      ref.watch(currentUserIdProvider);
      if (!_canShareMessage) {
        return ListView(
          padding: const EdgeInsets.all(24),
          children: const [
            Text(
              'Account changed. Return to your order and open support again.',
            ),
          ],
        );
      }
    }
    final settings = ref.watch(shopSettingsProvider);
    return settings.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => _recovery(
        'Could not load support contacts. Check your connection and retry.',
      ),
      data: (data) {
        final List<SupportContact> contacts;
        try {
          contacts = supportDirectoryFromSettings(data);
        } on FormatException {
          return _recovery(
            'Support contact details are unavailable. Please retry later.',
          );
        }
        if (contacts.isEmpty) {
          return _recovery(
            'No support contacts are available yet. Please check back later.',
          );
        }
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text('Choose who to contact, then choose a channel.'),
            const SizedBox(height: 24),
            for (final contact in contacts) ...[
              Text(
                contact.name,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(contact.category),
              const SizedBox(height: 12),
              for (final channel in contact.channels)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: OutlinedButton.icon(
                    onPressed: _opening ? null : () => _open(contact, channel),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(48, 48),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                    ),
                    icon: Icon(switch (channel) {
                      SupportChannel.whatsapp => Icons.chat_bubble_outline,
                      SupportChannel.phone => Icons.phone_outlined,
                      SupportChannel.email => Icons.email_outlined,
                    }),
                    label: Text(switch (channel) {
                      SupportChannel.whatsapp => 'WhatsApp',
                      SupportChannel.phone => 'Phone',
                      SupportChannel.email => 'Email',
                    }),
                  ),
                ),
              const Divider(height: 32),
            ],
          ],
        );
      },
    );
  }
}
