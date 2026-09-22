import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'easyparcel_repository.dart';

final easyParcelRepositoryProvider = Provider<EasyParcelRepository>(
  (ref) => EasyParcelRepository(),
);

/// Whether the shop's EasyParcel account is connected — watched by the
/// Delivery pane so each _FulfillmentCard knows whether to offer "Ship
/// with EasyParcel" as the primary action or fall back to manual tracking
/// entry. Refetch after Settings' "Connect EasyParcel" flow by invalidating
/// this provider (there's no push signal for "the admin finished the
/// browser OAuth flow", so callers re-check on demand instead).
final easyParcelConnectedProvider = FutureProvider<bool>((ref) async {
  try {
    final status = await ref.watch(easyParcelRepositoryProvider).connectionStatus();
    return status.connected;
  } catch (_) {
    return false;
  }
});
