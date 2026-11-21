import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// The installed app's version name and build number, e.g. 1.0.27 (32).
class AppVersion {
  final String version;
  final String build;
  const AppVersion({required this.version, required this.build});

  /// `1.0.27 (32)`, or just `1.0.27` when the platform reports no build.
  String get label => build.isEmpty ? version : '$version ($build)';
}

/// Read once from the platform. Tests override this provider; a platform
/// that cannot answer leaves it in error and callers simply omit the
/// version.
final appVersionProvider = FutureProvider<AppVersion>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return AppVersion(version: info.version, build: info.buildNumber);
});

/// Opening line for a feedback message, so the shop knows which build a
/// tester is describing.
String feedbackMessagePrefix(AppVersion? version) => version == null
    ? 'Feedback on Marugen app: '
    : 'Feedback on Marugen app ${version.label}: ';
