import 'package:flutter/widgets.dart';

/// Adds the space taken at the bottom of the screen — the home indicator
/// and, on iOS, the translucent tab bar that content scrolls under — to a
/// scroll view's own padding, so the last row can still scroll clear of it.
///
/// Scroll views only apply this automatically when they have no padding of
/// their own; every list with explicit padding needs it added by hand.
extension BottomInset on EdgeInsets {
  EdgeInsets plusBottomInset(BuildContext context) =>
      copyWith(bottom: bottom + MediaQuery.paddingOf(context).bottom);
}
