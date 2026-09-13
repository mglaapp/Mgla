import 'package:fl_clash/common/constant.dart';

final _keyPattern = RegExp(r'^[0-9a-fA-F]{16,64}$');
final _installLink = RegExp(
  r'^(?:mgla|clash|clashmeta|flclash)://install-config\?(.*)$',
  caseSensitive: false,
);

/// Turns what a person pasted into a subscription address, or null when it is not one.
///
/// Three shapes are accepted because all three end up in the clipboard: the bare key from the
/// account page, the full subscription link, and the install-config deep link a person may copy
/// out of a message instead of tapping it.
String? subscriptionUrlOf(String? input) {
  final value = input?.trim() ?? '';
  if (value.isEmpty) {
    return null;
  }
  if (_keyPattern.hasMatch(value)) {
    return '$subscriptionSite$subscriptionPath$value';
  }
  final deepLink = _installLink.firstMatch(value);
  if (deepLink != null) {
    final url = Uri.splitQueryString(deepLink.group(1) ?? '')['url'];
    return _httpUrl(url);
  }
  return _httpUrl(value);
}

String? _httpUrl(String? value) {
  if (value == null || value.isEmpty) {
    return null;
  }
  final uri = Uri.tryParse(value);
  if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
    return null;
  }
  if (uri.scheme != 'http' && uri.scheme != 'https') {
    return null;
  }
  return uri.toString();
}
