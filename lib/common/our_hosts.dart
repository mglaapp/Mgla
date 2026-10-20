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

bool strictTlsHost(String host) {
  final h = host.toLowerCase();
  return _strictTlsHosts.contains(h) || h.endsWith('.mgla.app');
}
