import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/promo_code.dart';
import '../data/promo_repository.dart';

final promoRepositoryProvider = Provider<PromoRepository>((ref) => PromoRepository());

final adminPromoCodesProvider = FutureProvider<List<PromoCode>>((ref) {
  return ref.watch(promoRepositoryProvider).fetchAll();
});
