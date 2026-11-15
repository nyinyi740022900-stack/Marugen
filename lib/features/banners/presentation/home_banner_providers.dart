import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/home_banner.dart';
import '../data/home_banner_repository.dart';

final homeBannerRepositoryProvider = Provider<HomeBannerRepository>(
  (ref) => HomeBannerRepository(),
);

/// Live slides for the Shop tab. Fails soft: the carousel hides itself on
/// error so a banner outage never blocks the shop.
final liveHomeBannersProvider = FutureProvider<List<HomeBanner>>((ref) {
  return ref.watch(homeBannerRepositoryProvider).fetchLiveBanners();
});

/// Every slide for the admin manager (RLS widens the same query for admins).
final adminHomeBannersProvider = FutureProvider<List<HomeBanner>>((ref) {
  return ref.watch(homeBannerRepositoryProvider).fetchAllBanners();
});
