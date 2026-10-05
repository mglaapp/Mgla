import 'dart:convert' show LineSplitter;
import 'dart:ffi' show Abi;
import 'dart:io';

import 'constant.dart';
import 'package.dart';

class UpdateAsset {
  const UpdateAsset({
    required this.name,
    required this.url,
    required this.size,
  });

  final String name;
  final String url;
  final int size;
}

/// Null on macOS and Linux, which keep opening the release page instead.
String? updateAssetSuffix([Abi? abi]) {
  return switch (abi ?? Abi.current()) {
    Abi.androidArm64 => '-android-arm64-v8a.apk',
    Abi.androidArm => '-android-armeabi-v7a.apk',
    Abi.androidX64 => '-android-x86_64.apk',
    Abi.windowsX64 => '-windows-amd64-setup.exe',
    Abi.windowsArm64 => '-windows-arm64-setup.exe',
    _ => null,
  };
}

UpdateAsset? pickUpdateAsset(List<dynamic>? assets, String? suffix) {
  if (assets == null || suffix == null) {
    return null;
  }
  for (final asset in assets) {
    if (asset is! Map) continue;
    final name = asset['name'];
    final url = asset['browser_download_url'];
    if (name is! String || url is! String || !name.endsWith(suffix)) continue;
    final size = asset['size'];
    return UpdateAsset(name: name, url: url, size: size is int ? size : 0);
  }
  return null;
}

/// Null when SHA256SUMS does not list the name, and the caller must then refuse to install.
String? sha256ForAsset(String sums, String assetName) {
  for (final line in const LineSplitter().convert(sums)) {
    final parts = line.trim().split(RegExp(r'\s+'));
    if (parts.length < 2) continue;
    final name = parts.last.replaceFirst(RegExp(r'^\./'), '');
    if (name == assetName) {
      return parts.first.toLowerCase();
    }
  }
  return null;
}

bool get canInstallUpdateInApp => Platform.isAndroid || Platform.isWindows;

/// Where to ask about a newer version, in order: our own mirror first, then GitHub.
///
/// The mirror (mgla.app/api/v1/app/release, since 05-10) answers in GitHub's own release shape,
/// with file links on mgla.app: from Russia GitHub opens slowly or not at all, and our name is
/// the one the person already reaches. GitHub stays second, so a mirror that is down or behind
/// never leaves anyone without an update — see [isNewerRelease] in Request.checkForUpdate.
List<String> updateSources() => [
  '$subscriptionSite/api/v1/app/release',
  'https://api.github.com/repos/$repository/releases/latest',
];

/// The download page on our site: every build, picked for the device that opens it.
const updatePageUrl = '$subscriptionSite/download';

/// True when [release] (a GitHub-shaped release) is newer than [currentVersion].
///
/// False, not an exception, for anything unreadable: a tag like `v0.9.5-pre.1` or a missing
/// tag must read as "no update here", so the caller moves on to the next source.
bool isNewerRelease(Map<String, dynamic>? release, String currentVersion) {
  final tag = release?['tag_name'];
  if (tag is! String || tag.isEmpty) return false;
  try {
    return compareVersions(tag.replaceFirst('v', ''), currentVersion) > 0;
  } catch (_) {
    return false;
  }
}
