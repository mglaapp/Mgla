import 'dart:convert' show LineSplitter;
import 'dart:ffi' show Abi;
import 'dart:io';

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
