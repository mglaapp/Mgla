import 'dart:convert' show LineSplitter;
import 'dart:ffi' show Abi;
import 'dart:io';

import 'constant.dart';
import 'our_hosts.dart';
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

enum LinuxInstall { appImage, deb, rpm }

/// How this Linux copy was installed; null when it cannot be told, and the release page opens.
LinuxInstall? linuxInstallKind({
  Map<String, String>? environment,
  String? executable,
  bool Function(String path)? exists,
}) {
  final env = environment ?? Platform.environment;
  final exe = executable ?? Platform.resolvedExecutable;
  final has = exists ?? (String path) => File(path).existsSync();
  if ((env['APPIMAGE'] ?? '').isNotEmpty) return LinuxInstall.appImage;
  if (!exe.startsWith('/usr/')) return null;
  if (has('/usr/bin/dpkg')) return LinuxInstall.deb;
  if (has('/usr/bin/rpm')) return LinuxInstall.rpm;
  return null;
}

/// The .app bundle around a macOS executable (`…/Mgla.app/Contents/MacOS/Mgla`).
String? macAppBundle(String executable) {
  final marker = executable.lastIndexOf('.app/Contents/MacOS/');
  return marker < 0 ? null : executable.substring(0, marker + 4);
}

String? updateAssetSuffix([Abi? abi, LinuxInstall? linux]) {
  final current = abi ?? Abi.current();
  final kind =
      linux ??
      (abi == null && (current == Abi.linuxX64 || current == Abi.linuxArm64)
          ? linuxInstallKind()
          : null);
  final linuxArch = current == Abi.linuxArm64 ? 'arm64' : 'amd64';
  return switch (current) {
    Abi.androidArm64 => '-android-arm64-v8a.apk',
    Abi.androidArm => '-android-armeabi-v7a.apk',
    Abi.androidX64 => '-android-x86_64.apk',
    Abi.windowsX64 => '-windows-amd64-setup.exe',
    Abi.windowsArm64 => '-windows-arm64-setup.exe',
    Abi.macosArm64 => '-macos-arm64.dmg',
    Abi.macosX64 => '-macos-amd64.dmg',
    Abi.linuxX64 || Abi.linuxArm64 => switch (kind) {
      LinuxInstall.appImage => '-linux-$linuxArch.AppImage',
      LinuxInstall.deb => '-linux-$linuxArch.deb',
      LinuxInstall.rpm => '-linux-$linuxArch.rpm',
      null => null,
    },
    _ => null,
  };
}

bool _plainFileName(String name) =>
    name.isNotEmpty &&
    name.length <= 200 &&
    !name.contains('/') &&
    !name.contains(r'\') &&
    !name.contains('..') &&
    !name.startsWith('.');

bool _trustedDownload(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.scheme != 'https' || uri.userInfo.isNotEmpty) {
    return false;
  }
  return strictTlsHost(uri.host);
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
    // The name becomes a file in our cache and the url is fetched before any checksum is
    // known: a plain file name only, https only, our hosts only (audit M5-7).
    if (!_plainFileName(name) || !_trustedDownload(url)) continue;
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

bool get canInstallUpdateInApp =>
    Platform.isAndroid ||
    Platform.isWindows ||
    (Platform.isMacOS && macAppBundle(Platform.resolvedExecutable) != null) ||
    (Platform.isLinux && linuxInstallKind() != null);

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
