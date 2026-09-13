import 'dart:ffi' show Abi;

import 'package:fl_clash/common/app_update.dart';
import 'package:flutter_test/flutter_test.dart';

/// The asset list of a real release, trimmed to the fields the picker reads.
List<Map<String, Object>> _assets() => [
  for (final entry in const {
    'Mgla-0.9.1-android-arm64-v8a.apk': 55616532,
    'Mgla-0.9.1-android-armeabi-v7a.apk': 55700000,
    'Mgla-0.9.1-android-x86_64.apk': 58000000,
    'Mgla-0.9.1-linux-amd64.AppImage': 64200000,
    'Mgla-0.9.1-macos-arm64.dmg': 53700000,
    'Mgla-0.9.1-windows-amd64-setup.exe': 39000000,
    'Mgla-0.9.1-windows-amd64.zip': 62300000,
    'Mgla-0.9.1-windows-arm64-setup.exe': 36200000,
    'SHA256SUMS': 1400,
  }.entries)
    {
      'name': entry.key,
      'browser_download_url': 'https://example.test/${entry.key}',
      'size': entry.value,
    },
];

void main() {
  group('the file this machine installs', () {
    test('every architecture we ship maps onto a file the release has', () {
      final names = _assets().map((asset) => asset['name'] as String).toList();
      for (final abi in const [
        Abi.androidArm64,
        Abi.androidArm,
        Abi.androidX64,
        Abi.windowsX64,
        Abi.windowsArm64,
      ]) {
        final suffix = updateAssetSuffix(abi);
        expect(suffix, isNotNull, reason: '$abi has no asset suffix');
        expect(
          names.where((name) => name.endsWith(suffix!)),
          hasLength(1),
          reason: 'release has no single file ending with $suffix for $abi',
        );
      }
    });

    test('platforms we deliberately do not install in place answer null', () {
      // Not an omission: a .dmg is dragged by hand and .deb/.rpm need root, so those keep
      // opening the release page. If this ever starts returning a suffix, the flow would hand
      // a Linux package to a process that cannot install it.
      for (final abi in const [
        Abi.linuxX64,
        Abi.linuxArm64,
        Abi.macosX64,
        Abi.macosArm64,
        Abi.windowsIA32,
      ]) {
        expect(updateAssetSuffix(abi), isNull, reason: '$abi should be null');
      }
    });

    test('picking matches by suffix, so a new version still matches', () {
      final asset = pickUpdateAsset(_assets(), '-android-arm64-v8a.apk');
      expect(asset?.name, 'Mgla-0.9.1-android-arm64-v8a.apk');
      expect(
        asset?.url,
        'https://example.test/Mgla-0.9.1-android-arm64-v8a.apk',
      );
      expect(asset?.size, 55616532);
    });

    test('the installer is picked on Windows, never the portable zip', () {
      final asset = pickUpdateAsset(
        _assets(),
        updateAssetSuffix(Abi.windowsX64),
      );
      expect(asset?.name, 'Mgla-0.9.1-windows-amd64-setup.exe');
    });

    test('a release without our file yields null, not the wrong file', () {
      expect(pickUpdateAsset(_assets(), '-linux-amd64.deb'), isNull);
      expect(pickUpdateAsset(_assets(), null), isNull);
      expect(pickUpdateAsset(null, '-android-arm64-v8a.apk'), isNull);
    });
  });

  group('checksum published with the release', () {
    const sums =
        'f157da41228cf4320170f9bbfb4446a216567ca665fd9b7ecfddadb3afe3f190  '
        './Mgla-0.9.1-android-arm64-v8a.apk\n'
        'e5c9ca8f65ddfbe406f5443654799d805b2a5708ddc202f29f7de074cb513399  '
        './Mgla-0.9.1-windows-amd64-setup.exe\n';

    test('reads the sum of the named file', () {
      expect(
        sha256ForAsset(sums, 'Mgla-0.9.1-android-arm64-v8a.apk'),
        'f157da41228cf4320170f9bbfb4446a216567ca665fd9b7ecfddadb3afe3f190',
      );
      expect(
        sha256ForAsset(sums, 'Mgla-0.9.1-windows-amd64-setup.exe'),
        'e5c9ca8f65ddfbe406f5443654799d805b2a5708ddc202f29f7de074cb513399',
      );
    });

    test('a file that is not listed has no sum, so it is never installed', () {
      expect(sha256ForAsset(sums, 'Mgla-0.9.1-linux-amd64.deb'), isNull);
      expect(sha256ForAsset('', 'Mgla-0.9.1-android-arm64-v8a.apk'), isNull);
    });

    test('a name that merely ends with ours is not ours', () {
      const lookalike =
          'dead00000000000000000000000000000000000000000000000000000000beef  '
          './evil-Mgla-0.9.1-android-arm64-v8a.apk\n';
      expect(
        sha256ForAsset(lookalike, 'Mgla-0.9.1-android-arm64-v8a.apk'),
        isNull,
      );
    });

    test('survives CRLF and a plain name without the ./ prefix', () {
      const plain =
          'aa11bb22cc33dd44ee55ff66aa77bb88cc99dd00ee11ff22aa33bb44cc55dd66  '
          'Mgla-0.9.1-android-arm64-v8a.apk\r\n';
      expect(
        sha256ForAsset(plain, 'Mgla-0.9.1-android-arm64-v8a.apk'),
        'aa11bb22cc33dd44ee55ff66aa77bb88cc99dd00ee11ff22aa33bb44cc55dd66',
      );
    });
  });
}
