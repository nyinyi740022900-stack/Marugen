import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Privacy-friendly display name for a reviewer — full first name plus a
/// masked/initialed rest, the same convention Amazon ("John S."), Shopee
/// and Lazada ("n****i") use so a review carries a real identity (for
/// buyer trust) without publishing someone's full legal name. Falls back
/// to "Customer" when no name is on file (e.g. an OAuth sign-in that
/// never set `full_name`).
String maskedReviewerName(String? fullName) {
  final name = fullName?.trim();
  if (name == null || name.isEmpty) return 'Customer';

  final words = name.split(RegExp(r'\s+'));
  if (words.length > 1) {
    // "Nyi Nyi" -> "Nyi N." — first word in full, rest reduced to initials.
    final initials = words.skip(1).map((w) => '${w[0].toUpperCase()}.').join(' ');
    return '${words.first} $initials';
  }

  // Single word: keep the first and last character, mask the middle —
  // "Nyi" -> "N*i", "Al" -> "A." for anything too short to mask.
  final w = words.first;
  if (w.length <= 2) return '${w[0].toUpperCase()}.';
  return '${w[0]}${'*' * (w.length - 2)}${w[w.length - 1]}';
}

/// Avatar for a reviewer — shows their real uploaded photo when they have
/// one (see 0032_profile_avatar.sql / AuthRepository.uploadAvatar),
/// otherwise falls back to a colored initials circle (same fallback
/// Shopee/Lazada/Google reviews show for a buyer with no photo) as the
/// trust signal instead of a blank/anonymous-looking review row.
class ReviewerAvatar extends StatefulWidget {
  final String? fullName;
  final String? avatarUrl;
  final double radius;
  const ReviewerAvatar({super.key, this.fullName, this.avatarUrl, this.radius = 16});

  static const _palette = [
    AppColors.red,
    Color(0xFF3F6B8A),
    Color(0xFF6B8A3F),
    Color(0xFFB8860B),
    Color(0xFF8A3F6B),
  ];

  @override
  State<ReviewerAvatar> createState() => _ReviewerAvatarState();
}

class _ReviewerAvatarState extends State<ReviewerAvatar> {
  // CircleAvatar's backgroundImage has no built-in error fallback — a
  // stale/broken avatar_url (deleted storage object, bad URL) used to
  // render the framework's default red-and-white error box instead of
  // falling back to the initials circle every other reviewer without a
  // photo gets.
  bool _imageFailed = false;

  @override
  void didUpdateWidget(covariant ReviewerAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.avatarUrl != widget.avatarUrl) _imageFailed = false;
  }

  @override
  Widget build(BuildContext context) {
    final avatarUrl = widget.avatarUrl;
    if (avatarUrl != null && avatarUrl.isNotEmpty && !_imageFailed) {
      return CircleAvatar(
        radius: widget.radius,
        backgroundImage: NetworkImage(avatarUrl),
        onBackgroundImageError: (_, _) {
          if (mounted) setState(() => _imageFailed = true);
        },
      );
    }
    final name = widget.fullName?.trim();
    final letter = (name != null && name.isNotEmpty) ? name[0].toUpperCase() : '?';
    // Deterministic so the same reviewer always gets the same color,
    // rather than a random one that would visually change on rebuild.
    final color =
        ReviewerAvatar._palette[letter.codeUnitAt(0) % ReviewerAvatar._palette.length];
    return CircleAvatar(
      radius: widget.radius,
      backgroundColor: color.withValues(alpha: 0.15),
      child: Text(
        letter,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: widget.radius * 0.85,
        ),
      ),
    );
  }
}
