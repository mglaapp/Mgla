import 'package:fl_clash/common/site_route.dart' show siteBackups;

/// Hosts that carry our account API, subscription and app updates.
///
/// A bad certificate there is never accepted, whatever the "check TLS" switch says (audit
/// M5-2, see http.dart), and an update file is only fetched from them (audit M5-7, see
/// app_update.dart).
const _strictTlsHosts = {
  'mgla.app',
  'api.github.com',
  'github.com',
  'objects.githubusercontent.com',
  'release-assets.githubusercontent.com',
};

/// The backup addresses of our site (17-11) carry the same account and updates.
final _backupHosts = {for (final b in siteBackups) Uri.parse(b).host};

bool strictTlsHost(String host) {
  final h = host.toLowerCase();
  return _strictTlsHosts.contains(h) ||
      h.endsWith('.mgla.app') ||
      _backupHosts.contains(h);
}
