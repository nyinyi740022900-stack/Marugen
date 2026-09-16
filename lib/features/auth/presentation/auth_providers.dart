import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/notifications/push_notification_service.dart';
import '../../../shared/models/app_user.dart';
import '../data/auth_repository.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) => AuthRepository());

/// Emits whenever Supabase's auth state changes (sign in / sign out /
/// token refresh) so downstream providers can react.
final authStateProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges;
});

/// The current app user, including their role (customer/staff/owner).
/// Re-fetches whenever [authStateProvider] emits.
final currentAppUserProvider = FutureProvider<AppUser?>((ref) async {
  ref.watch(authStateProvider);
  final repo = ref.watch(authRepositoryProvider);
  if (repo.currentUser == null) return null;
  // Register/refresh this device's push token now that we know who's
  // logged in. Fire-and-forget — no-op if Firebase isn't configured.
  unawaited(PushNotificationService.registerTokenForCurrentUser());
  return repo.fetchCurrentAppUser();
});

final isLoggedInProvider = Provider<bool>((ref) {
  return ref.watch(authStateProvider).valueOrNull?.session != null;
});
