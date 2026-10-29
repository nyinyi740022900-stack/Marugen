import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/supabase/supabase_client.dart';
import '../../shared/models/app_user.dart';
import '../../shared/models/support_contact.dart';
import '../../shared/providers/settings_providers.dart';
import '../auth/presentation/auth_providers.dart';
import 'support_contact_form.dart';

/// This directory contains contact details, not application accounts or roles.
class SupportDirectorySettingsTile extends ConsumerWidget {
  const SupportDirectorySettingsTile({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(currentAppUserProvider).valueOrNull?.role != UserRole.owner) {
      return const SizedBox.shrink();
    }
    return ListTile(
      contentPadding: EdgeInsets.zero,
      minTileHeight: 64,
      leading: const Icon(Icons.support_agent),
      title: const Text('Support contacts'),
      subtitle: const Text(
        'Manage staff names, responsibilities and contact channels',
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const _SupportDirectorySettings(),
        ),
      ),
    );
  }
}

class _SupportDirectorySettings extends ConsumerStatefulWidget {
  const _SupportDirectorySettings();
  @override
  ConsumerState<_SupportDirectorySettings> createState() =>
      _SupportDirectorySettingsState();
}

class _SupportDirectorySettingsState
    extends ConsumerState<_SupportDirectorySettings> {
  List<SupportContact>? _contacts;
  String? _error;
  bool _saving = false;
  late final String? _accountId;

  bool get _sameOwner =>
      _accountId != null &&
      SupabaseService.client.auth.currentUser?.id == _accountId &&
      ref.read(currentAppUserProvider).valueOrNull?.id == _accountId &&
      ref.read(currentAppUserProvider).valueOrNull?.role == UserRole.owner;

  @override
  void initState() {
    super.initState();
    _accountId = SupabaseService.client.auth.currentUser?.id;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _contacts = null;
      _error = null;
    });
    try {
      final settings = await ref
          .read(settingsRepositoryProvider)
          .fetchSettings();
      if (!mounted || !_sameOwner) return;
      setState(
        () => _contacts = supportDirectoryFromSettings(
          settings,
          legacyFallback: false,
        ).toList(),
      );
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not load support contacts. Please retry.',
        );
      }
    }
  }

  Future<void> _edit([SupportContact? contact]) async {
    final result = await Navigator.of(context).push<SupportContact>(
      MaterialPageRoute(
        builder: (context) => SupportContactForm(
          contact: contact,
          onSaved: (value) => Navigator.of(context).pop(value),
        ),
      ),
    );
    if (!mounted || !_sameOwner || result == null) return;
    setState(() {
      final index = _contacts!.indexWhere((entry) => entry.id == result.id);
      if (index < 0) {
        _contacts!.add(result);
      } else {
        _contacts![index] = result;
      }
    });
    // Persist right away so leaving the screen cannot drop the contact.
    await _save();
  }

  Future<void> _remove(SupportContact contact) async {
    setState(() => _contacts!.remove(contact));
    await _save();
  }

  Future<void> _save() async {
    if (!_sameOwner || _saving || _contacts == null) return;
    final payload = _contacts!.map((c) => c.toMap()).toList();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      // Recheck server-derived role after an account or permission change.
      final user = await ref.refresh(currentAppUserProvider.future);
      if (!mounted || !_sameOwner || user?.role != UserRole.owner) return;
      await ref.read(settingsRepositoryProvider).updateSettings({
        'support_contacts': payload,
      });
      if (!mounted || !_sameOwner) return;
      ref.invalidate(shopSettingsProvider);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Support contacts saved')));
    } catch (_) {
      if (mounted && _sameOwner) {
        setState(
          () => _error = 'Could not save support contacts. Your changes are kept here. Please retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentAppUserProvider).valueOrNull;
    if (!_sameOwner || user?.role != UserRole.owner) {
      return Scaffold(
        appBar: AppBar(title: const Text('Support contacts')),
        body: const Padding(
          padding: EdgeInsets.all(24),
          child: Text('Sign in as the owner to manage support contacts.'),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Support contacts')),
      body: _contacts == null
          ? (_error == null
                ? const Center(child: CircularProgressIndicator())
                : Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_error!),
                          const SizedBox(height: 16),
                          OutlinedButton(
                            onPressed: _load,
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  ))
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const Text(
                  'Customers choose a person and a contact channel. These details are public. Changes are saved as soon as you add, edit or remove a contact.',
                ),
                const SizedBox(height: 16),
                if (_contacts!.isEmpty)
                  const Text(
                    'No staff contacts yet. Customers will use the shop phone number when available.',
                  ),
                for (final contact in _contacts!) ...[
                  Text(
                    contact.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(contact.category),
                  Wrap(
                    spacing: 8,
                    children: [
                      TextButton(
                        onPressed: _saving ? null : () => _edit(contact),
                        style: TextButton.styleFrom(
                          minimumSize: const Size(48, 48),
                        ),
                        child: const Text('Edit'),
                      ),
                      TextButton(
                        onPressed: _saving
                            ? null
                            : () => _remove(contact),
                        style: TextButton.styleFrom(
                          minimumSize: const Size(48, 48),
                        ),
                        child: const Text('Remove'),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                ],
                OutlinedButton.icon(
                  onPressed: _saving || _contacts!.length >= 30
                      ? null
                      : () => _edit(),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(48, 48),
                  ),
                  icon: const Icon(Icons.add),
                  label: const Text('Add support contact'),
                ),
                const SizedBox(height: 16),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (_saving)
                  const Center(child: CircularProgressIndicator())
                else if (_error != null)
                  FilledButton(
                    onPressed: _save,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(48, 48),
                    ),
                    child: const Text('Retry saving'),
                  ),
              ],
            ),
    );
  }
}
