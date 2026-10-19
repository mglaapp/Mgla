import 'dart:convert';

import 'package:cryptography/cryptography.dart';

/// Public half of the Ed25519 key that signs SHA256SUMS of every stable release (audit M5-1,
/// 20-10). The private half lives only in the UPDATE_SIGN_KEY secret of the GitHub repository
/// and in the owner's key folder.
///
/// Why a signature on top of the checksums: SHA256SUMS comes from the same release (or the same
/// mgla.app mirror) as the file it describes, so whoever can replace the file there can replace
/// the sums too. A checksum only catches a broken download; the signature is what catches a
/// forged one, because a forger has the server but not this key.
const updateSigningPublicKey = 'CqzgbJpqpU02pe2USxHEOAbNWU5GFBCWeyG6K0c6x8o=';

/// The release asset with the base64 signature of SHA256SUMS (CI, step "Sign SHA256SUMS").
const updateSignatureAsset = 'SHA256SUMS.sig';

/// True only when [signatureText] is a valid Ed25519 signature of [sums] by [publicKey].
///
/// Everything else is false, never an exception: a missing, empty, truncated or garbled
/// signature must read as "do not install", the same as a wrong one.
Future<bool> verifySumsSignature(
  String sums,
  String? signatureText, {
  String publicKey = updateSigningPublicKey,
}) async {
  if (signatureText == null) return false;
  try {
    final signature = base64.decode(signatureText.trim());
    final key = base64.decode(publicKey);
    if (signature.length != 64 || key.length != 32) return false;
    return await Ed25519().verify(
      utf8.encode(sums),
      signature: Signature(
        signature,
        publicKey: SimplePublicKey(key, type: KeyPairType.ed25519),
      ),
    );
  } catch (_) {
    return false;
  }
}
