import 'package:fl_clash/common/app_update.dart';
import 'package:fl_clash/common/update_signing.dart';
import 'package:flutter_test/flutter_test.dart';

/// SHA256SUMS in the exact shape CI writes (`sha256sum ./* > SHA256SUMS`).
const _sums =
    '3f0c2a6b9d1e4f5a7b8c9d0e1f2a3b4c5d6e7f8091a2b3c4d5e6f708192a3b4c  ./Mgla-0.9.9-android-arm64-v8a.apk\n'
    '0a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f9  ./Mgla-0.9.9-windows-amd64-setup.exe\n';

/// Signature of [_sums] made with the real release key by the same command CI runs:
/// `openssl pkeyutl -sign -inkey <key> -rawin -in SHA256SUMS | base64 -w0`.
const _sig =
    '0zdT2WNw7OYnUMjMMINQK6qnmtsz/7MwPQH3pmSQzkYo3mk8+rVAcwxbWAwU5k8BtMe/RhrvZixaJtjn3DDODw==';

void main() {
  group('signed SHA256SUMS', () {
    test('a signature by the release key is accepted', () async {
      expect(await verifySumsSignature(_sums, _sig), isTrue);
      expect(
        await verifySumsSignature(_sums, '$_sig\n'),
        isTrue,
        reason: 'a trailing newline in the .sig file is not a forgery',
      );
    });

    test('sums changed after signing are refused', () async {
      final forged = _sums.replaceFirst('3f0c', '3f0d');
      expect(await verifySumsSignature(forged, _sig), isFalse);
      expect(await verifySumsSignature('$_sums\n', _sig), isFalse);
    });

    test('the same signature under another key is refused', () async {
      expect(
        await verifySumsSignature(
          _sums,
          _sig,
          publicKey: 'O2onvM62pC1io6jQKm8Nc2UyFXcd4kOmOsBIoYtZ2ik=',
        ),
        isFalse,
      );
    });

    test('missing, empty or garbled signatures never pass', () async {
      for (final bad in [
        null,
        '',
        'not base64!',
        'AAAA',
        _sig.substring(0, 40),
      ]) {
        expect(await verifySumsSignature(_sums, bad), isFalse, reason: '$bad');
      }
    });
  });

  group('the signature asset in a release', () {
    final assets = [
      for (final name in const [
        'Mgla-0.9.9-android-arm64-v8a.apk',
        'SHA256SUMS',
        'SHA256SUMS.sig',
      ])
        {
          'name': name,
          'browser_download_url': 'https://example.test/$name',
          'size': 1,
        },
    ];

    test('sums and signature are picked as two different files', () {
      expect(pickUpdateAsset(assets, 'SHA256SUMS')?.name, 'SHA256SUMS');
      expect(
        pickUpdateAsset(assets, updateSignatureAsset)?.name,
        'SHA256SUMS.sig',
      );
    });

    test('a release without a signature has nothing to pick', () {
      final unsigned = assets
          .where((a) => a['name'] != 'SHA256SUMS.sig')
          .toList();
      expect(pickUpdateAsset(unsigned, updateSignatureAsset), isNull);
    });
  });
}
