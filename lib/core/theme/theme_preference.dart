import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final themePreferencesProvider = Provider<Future<SharedPreferences>>(
  (ref) => SharedPreferences.getInstance(),
);
final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);

class ThemeModeNotifier extends Notifier<ThemeMode> {
  int _revision = 0;
  bool _disposed = false;
  Future<void> _saves = Future.value();
  @override
  ThemeMode build() {
    ref.onDispose(() {
      _disposed = true;
    });
    unawaited(_restore());
    return ThemeMode.system;
  }

  Future<void> _restore() async {
    final revision = _revision;
    try {
      final prefs = await ref.read(themePreferencesProvider);
      if (_disposed || revision != _revision) return;
      final saved = prefs.getString('appearance_mode');
      state = switch (saved) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
    } catch (error) {
      debugPrint('Appearance preference could not be loaded: $error');
    }
  }

  Future<void> setMode(ThemeMode mode) {
    _revision++;
    state = mode;
    final preferences = ref.read(themePreferencesProvider);
    final nextSave = _saves.then((_) async {
      final prefs = await preferences;
      if (!await prefs.setString('appearance_mode', mode.name)) {
        throw StateError('Appearance preference could not be saved');
      }
    });
    _saves = nextSave.catchError((Object error) {
      debugPrint('Appearance save failed: $error');
    });
    return nextSave;
  }
}
