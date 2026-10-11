import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'theme_preference.dart';

class AppearanceTile extends ConsumerWidget {
  const AppearanceTile({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    return ListTile(
      leading: const Icon(Icons.brightness_6_outlined),
      title: const Text('Appearance'),
      subtitle: Text(
        mode == ThemeMode.system
            ? 'System — follows your device'
            : _label(mode),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showAppearancePicker(context, ref),
    );
  }
}

/// The shop shortcut uses the same saved preference and picker as Profile.
class AppearanceButton extends ConsumerWidget {
  const AppearanceButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return IconButton(
      tooltip: 'Appearance',
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      icon: Icon(isDark ? Icons.dark_mode_outlined : Icons.light_mode_outlined),
      onPressed: () => _showAppearancePicker(context, ref),
    );
  }
}

String _label(ThemeMode mode) => switch (mode) {
  ThemeMode.light => 'Light',
  ThemeMode.dark => 'Dark',
  ThemeMode.system => 'System',
};

Future<void> _showAppearancePicker(BuildContext context, WidgetRef ref) async {
  final mode = ref.read(themeModeProvider);

  final selected = await showModalBottomSheet<ThemeMode>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
              child: Text(
                'Appearance',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            for (final choice in ThemeMode.values)
              ListTile(
                leading: Icon(switch (choice) {
                  ThemeMode.light => Icons.light_mode_outlined,
                  ThemeMode.dark => Icons.dark_mode_outlined,
                  ThemeMode.system => Icons.settings_brightness_outlined,
                }),
                title: Text(_label(choice)),
                subtitle: choice == ThemeMode.system
                    ? const Text('Use your device appearance')
                    : null,
                trailing: mode == choice ? const Icon(Icons.check) : null,
                selected: mode == choice,
                onTap: () => Navigator.pop(context, choice),
              ),
          ],
        ),
      ),
    ),
  );
  if (selected == null || !context.mounted) return;
  try {
    await ref.read(themeModeProvider.notifier).setMode(selected);
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Appearance changed for now, but could not be saved. Please try again.',
        ),
      ),
    );
  }
}
