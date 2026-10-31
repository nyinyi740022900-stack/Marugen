import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/utils/error_message.dart';
import '../../../shared/utils/password_validator.dart';
import 'auth_providers.dart';

/// Profile → "Edit name" and, for email/password accounts, "Change
/// password". Without these a customer could only fix a typo in their name
/// by contacting the shop, and change a password through the forgot-password
/// email.
class AccountDetailsTiles extends ConsumerWidget {
  final String? fullName;
  final bool usesPassword;
  const AccountDetailsTiles({
    super.key,
    this.fullName,
    this.usesPassword = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.badge_outlined),
          title: const Text('Edit name'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _editName(context, ref),
        ),
        if (usesPassword)
          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: const Text('Change password'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _changePassword(context, ref),
          ),
      ],
    );
  }

  Future<void> _editName(BuildContext context, WidgetRef ref) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _NameDialog(initial: fullName ?? ''),
    );
    if (name == null || !context.mounted) return;
    await _save(
      context,
      () => ref.read(authRepositoryProvider).updateFullName(name),
      done: 'Name updated.',
      onDone: () => ref.invalidate(currentAppUserProvider),
    );
  }

  Future<void> _changePassword(BuildContext context, WidgetRef ref) async {
    final password = await showDialog<String>(
      context: context,
      builder: (_) => const _PasswordDialog(),
    );
    if (password == null || !context.mounted) return;
    await _save(
      context,
      () => ref.read(authRepositoryProvider).updatePassword(password),
      done: 'Password changed.',
    );
  }

  Future<void> _save(
    BuildContext context,
    Future<void> Function() action, {
    required String done,
    VoidCallback? onDone,
  }) async {
    final messenger = ScaffoldMessenger.of(context)..clearSnackBars();
    try {
      await action();
      onDone?.call();
      messenger.showSnackBar(SnackBar(content: Text(done)));
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            friendlyErrorMessage(
              e,
              fallback: "Couldn't save that change. Please try again.",
              context: 'profile.account',
            ),
          ),
        ),
      );
    }
  }
}

class _NameDialog extends StatefulWidget {
  final String initial;
  const _NameDialog({required this.initial});

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      Navigator.pop(context, _controller.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit name'),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          autofillHints: const [AutofillHints.name],
          maxLength: 80,
          decoration: const InputDecoration(labelText: 'Full name'),
          validator: (v) =>
              (v == null || v.trim().isEmpty) ? 'Enter your name' : null,
          onFieldSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog();

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      Navigator.pop(context, _password.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Change password'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _password,
              obscureText: true,
              autofocus: true,
              autofillHints: const [AutofillHints.newPassword],
              decoration: const InputDecoration(labelText: 'New password'),
              validator: validateNewPassword,
            ),
            TextFormField(
              controller: _confirm,
              obscureText: true,
              autofillHints: const [AutofillHints.newPassword],
              decoration: const InputDecoration(
                labelText: 'Confirm new password',
              ),
              validator: (v) =>
                  v == _password.text ? null : 'Passwords do not match',
              onFieldSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(onPressed: _submit, child: const Text('Change')),
      ],
    );
  }
}
