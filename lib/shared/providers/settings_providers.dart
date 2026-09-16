import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/admin/settings/settings_repository.dart';

/// Shared read access to the single-row `settings` table (readable by
/// anon per RLS) — used by customer-side screens (contact-for-price,
/// checkout GST) as well as the admin settings screen.
final settingsRepositoryProvider = Provider<SettingsRepository>((ref) => SettingsRepository());

final shopSettingsProvider = FutureProvider<Map<String, dynamic>>((ref) {
  return ref.watch(settingsRepositoryProvider).fetchSettings();
});
