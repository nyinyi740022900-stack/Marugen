import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// The small uppercase heading over a section of a screen ("RECENT ORDERS",
/// "TRANSACTIONS"): [AppTextStyles.sectionLabel] in the muted text colour.
///
/// Pass the text already in capitals; it is shown as given.
class SectionLabel extends StatelessWidget {
  final String text;
  const SectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: AppTextStyles.sectionLabel.copyWith(
      color: AppPalette.of(context).textMuted,
    ),
  );
}
