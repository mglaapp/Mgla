import 'dart:io';

import 'package:dio/dio.dart';
import 'package:fl_clash/common/constant.dart';

/// Our site under other names (17-11): the bridge in Moscow passes everything on to the same
/// server, with the person's own address. From Russia mgla.app can be cut while the bridge is
/// not, so the account, the subscription and updates ask there when mgla.app does not answer.
///
/// sslip.io and not *.mgla.app: a name of our brand would be blocked along with the brand.
const siteBackups = ['https://171.22.133.125.sslip.io'];

/// Every address of our site, mgla.app first.
const siteBases = [subscriptionSite, ...siteBackups];

/// True when [error] says the request never reached a server, so asking the same thing on
/// another address cannot do it twice.
///
/// Before anything is sent, dio fails with a connect timeout, a socket error while connecting
/// (io_adapter.dart catches those only around openUrl) or a TLS failure. A dropped connection
/// after the request went out reads differently, and a POST is not repeated then: an account
/// or an invoice must not be made twice. A GET is safe to repeat for any missing answer.
bool siteUnreached(Object error, {required bool repeatable}) {
  if (error is! DioException || error.response != null) return false;
  switch (error.type) {
    case DioExceptionType.cancel:
    case DioExceptionType.badResponse:
      return false;
    case DioExceptionType.connectionTimeout:
      return true;
    case DioExceptionType.connectionError:
      return repeatable || error.error is SocketException;
    case DioExceptionType.unknown:
      return repeatable || error.error is TlsException;
    case DioExceptionType.badCertificate:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
    case DioExceptionType.transformTimeout:
      return repeatable;
  }
}

/// Which address of our site to ask, and in what order.
class SiteRoute {
  SiteRoute({
    this.bases = siteBases,
    this.memory = const Duration(minutes: 10),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final List<String> bases;

  /// How long a backup that answered is asked first: without it every call would wait out
  /// mgla.app's timeout again before going where the answer is.
  final Duration memory;
  final DateTime Function() _clock;
  String? _good;
  DateTime? _goodUntil;

  /// The address of our site [url] is on, or null for any other URL.
  String? baseOf(String url) {
    for (final base in bases) {
      if (url == base || url.startsWith('$base/') || url.startsWith('$base?')) {
        return base;
      }
    }
    return null;
  }

  /// True for a host name of our site — mgla.app or a backup.
  bool isSiteHost(String host) {
    final h = host.toLowerCase();
    return bases.any((b) => Uri.parse(b).host == h);
  }

  List<String> _order() {
    final good = _good;
    final until = _goodUntil;
    if (good == null || until == null || !_clock().isBefore(until)) {
      return bases;
    }
    return [good, ...bases.where((b) => b != good)];
  }

  /// The same path on every address of our site, best first. A URL elsewhere goes alone.
  List<String> candidates(String url) {
    final base = baseOf(url);
    if (base == null) return [url];
    final rest = url.substring(base.length);
    return [for (final b in _order()) '$b$rest'];
  }

  /// Back to mgla.app first, as at start.
  void forget() {
    _good = null;
    _goodUntil = null;
  }

  /// [url] answered: remember a backup for a while, forget it once mgla.app answers.
  void answered(String url) {
    final base = baseOf(url);
    if (base == null) return;
    if (base == bases.first) {
      _good = null;
      _goodUntil = null;
    } else {
      _good = base;
      _goodUntil = _clock().add(memory);
    }
  }

  /// Asks [url] by [attempt], and the same path on the next address while [retry] says the
  /// request never got anywhere. The last failure is rethrown as it was.
  Future<T> run<T>(
    String url,
    Future<T> Function(String url) attempt, {
    required bool Function(Object error) retry,
  }) async {
    final list = candidates(url);
    for (var i = 0; ; i++) {
      try {
        final result = await attempt(list[i]);
        answered(list[i]);
        return result;
      } catch (e) {
        if (i == list.length - 1 || !retry(e)) rethrow;
      }
    }
  }

  /// Links of a release that came from [from] (a backup): its files are named on mgla.app by
  /// the server, and are fetched from where the release itself came.
  String moveTo(String url, String from) {
    final base = baseOf(url);
    final target = baseOf(from);
    if (base == null || target == null || base == target) return url;
    return '$target${url.substring(base.length)}';
  }
}

/// One for the whole app: the account, subscription and update requests share what they learnt.
final siteRoute = SiteRoute();
