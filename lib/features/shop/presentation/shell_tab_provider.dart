import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Lets other screens (e.g. Checkout after a successful payment) jump the
/// [CustomerShell] bottom nav to a specific tab before navigating home.
final customerTabIndexProvider = StateProvider<int>((ref) => 0);
