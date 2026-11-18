import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fl_clash/common/crash_report.dart';
import 'package:fl_clash/common/request.dart';
import 'package:fl_clash/common/site_route.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(this._respond);

  final ResponseBody Function(RequestOptions options) _respond;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return _respond(options);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // globalState.packageInfo is set once per run: every test that needs it shares this one.
  var packageSet = false;
  void packaged() {
    if (packageSet) return;
    packageSet = true;
    globalState.packageInfo = PackageInfo(
      appName: 'Mgla',
      packageName: 'app.mgla',
      version: '0.9.5',
      buildNumber: '2026091701',
    );
  }

  test('getTextResponseForUrl propagates the typed DioException', () async {
    // flutter_test's mocked HttpClient answers every request with HTTP 400,
    // which Dio surfaces as a badResponse DioException.
    await expectLater(
      request.getTextResponseForUrl('http://127.0.0.1/anything'),
      throwsA(
        isA<DioException>().having(
          (e) => e.type,
          'type',
          DioExceptionType.badResponse,
        ),
      ),
    );
  });

  group('crash reports', () {
    late HttpClientAdapter original;

    setUp(() => original = request.dio.httpClientAdapter);
    tearDown(() => request.dio.httpClientAdapter = original);

    Future<CrashDelivery> sendWith(int status) {
      request.dio.httpClientAdapter = _ScriptedAdapter(
        (_) => ResponseBody.fromString('{}', status),
      );
      return request.sendCrashReport(const {'error': 'boom'});
    }

    test('a stored or refused report is not sent again', () async {
      expect(await sendWith(200), CrashDelivery.delivered);
      expect(await sendWith(202), CrashDelivery.delivered);
      expect(await sendWith(400), CrashDelivery.delivered);
      expect(await sendWith(413), CrashDelivery.delivered);
    });

    test('a busy or broken server gets the report later', () async {
      expect(await sendWith(429), CrashDelivery.retryLater);
      expect(await sendWith(503), CrashDelivery.retryLater);
    });

    test('an unreachable server gets the report later', () async {
      request.dio.httpClientAdapter = _ScriptedAdapter(
        (options) => throw DioException.connectionError(
          requestOptions: options,
          reason: 'offline',
        ),
      );

      expect(
        await request.sendCrashReport(const {'error': 'boom'}),
        CrashDelivery.retryLater,
      );
    });

    test('goes to our crash endpoint without an account key', () async {
      final adapter = _ScriptedAdapter(
        (_) => ResponseBody.fromString('{}', 200),
      );
      request.dio.httpClientAdapter = adapter;

      await request.sendCrashReport(const {'error': 'boom'});

      final sent = adapter.requests.single;
      expect(sent.uri.toString(), 'https://mgla.app/api/v1/crash');
      expect(sent.uri.queryParameters, isEmpty);
      expect(sent.data, isNot(contains('key')));
    });
  });

  test('the app header names the version and the platform', () {
    packaged();

    expect(
      Request.appHeader(),
      matches(
        RegExp(r'^0\.9\.5\+2026091701; (android|windows|macos|linux|ios)$'),
      ),
    );
  });

  group('backup address of the site (17-11)', () {
    const main = 'https://mgla.app';
    const backup = 'https://171.22.133.125.sslip.io';
    late HttpClientAdapter api, sub, upd;

    setUp(() {
      api = request.dio.httpClientAdapter;
      sub = request.subscriptionDio.httpClientAdapter;
      upd = request.updateDio.httpClientAdapter;
      siteRoute.forget();
      packaged();
    });
    tearDown(() {
      request.dio.httpClientAdapter = api;
      request.subscriptionDio.httpClientAdapter = sub;
      request.updateDio.httpClientAdapter = upd;
      siteRoute.forget();
    });

    /// mgla.app does not answer at all; the backup answers [body].
    _ScriptedAdapter mainDown(String body, {DioExceptionType? how}) =>
        _ScriptedAdapter((options) {
          if (options.uri.host == 'mgla.app') {
            throw DioException(
              requestOptions: options,
              type: how ?? DioExceptionType.connectionTimeout,
            );
          }
          return ResponseBody.fromString(
            body,
            200,
            headers: {
              Headers.contentTypeHeader: ['application/json'],
            },
          );
        });

    test(
      'account API: mgla.app down -> the answer comes from the backup',
      () async {
        final adapter = mainDown(
          '{"ok":true,"servers":[{"id":"de","cc":"de","group":"Mgla DE"}]}',
        );
        request.dio.httpClientAdapter = adapter;

        final res = await request.servers();

        expect(res.isSuccess, isTrue);
        expect(adapter.requests.map((r) => r.uri.toString()), [
          '$main/api/v1/servers',
          '$backup/api/v1/servers',
        ]);
        expect(adapter.requests.first.connectTimeout, isNotNull);
        // and the next call does not wait for mgla.app again
        await request.servers();
        expect(adapter.requests, hasLength(3));
        expect(adapter.requests.last.uri.host, '171.22.133.125.sslip.io');
      },
    );

    test('a POST that may have reached mgla.app is not made twice', () async {
      final adapter = mainDown(
        '{"ok":true,"granted":true}',
        how: DioExceptionType.receiveTimeout,
      );
      request.dio.httpClientAdapter = adapter;

      final res = await request.createTrialPayment('KEY');

      expect(res.isSuccess, isFalse);
      expect(adapter.requests, hasLength(1));
      // a POST still waits for the answer as long as the server needs
      expect(adapter.requests.single.receiveTimeout, isNull);
    });

    test('a POST that never left goes to the backup', () async {
      final adapter = mainDown('{"ok":true,"granted":true}');
      request.dio.httpClientAdapter = adapter;

      final res = await request.createTrialPayment('KEY');

      expect(res.isSuccess, isTrue);
      expect(adapter.requests.last.uri.toString(), '$backup/api/v1/pay/trial');
    });

    test('our subscription comes through the backup, no one else’s', () async {
      final adapter = mainDown('proxies: []');
      request.subscriptionDio.httpClientAdapter = adapter;

      final res = await request.getFileResponseForUrl('$main/sub/KEY');
      expect(String.fromCharCodes(res.data!), 'proxies: []');
      expect(adapter.requests.map((r) => r.uri.toString()), [
        '$main/sub/KEY',
        '$backup/sub/KEY',
      ]);

      final other = _ScriptedAdapter(
        (options) => throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionTimeout,
        ),
      );
      request.subscriptionDio.httpClientAdapter = other;
      await expectLater(
        request.getFileResponseForUrl('https://example.com/sub/x'),
        throwsA(isA<DioException>()),
      );
      expect(other.requests, hasLength(1));
    });

    test('an update found through the backup downloads from it', () async {
      final adapter = mainDown(
        '{"tag_name":"v0.9.20","assets":[{"name":"SHA256SUMS",'
        '"browser_download_url":"$main/download/v0.9.20/SHA256SUMS"}]}',
      );
      request.updateDio.httpClientAdapter = adapter;

      final release = await request.checkForUpdate();

      expect(release?['tag_name'], 'v0.9.20');
      final asset = (release!['assets'] as List).single as Map;
      expect(
        asset['browser_download_url'],
        '$backup/download/v0.9.20/SHA256SUMS',
      );
      expect(adapter.requests.first.uri.host, 'mgla.app');
    });
  });

  test('getFileResponseForUrl propagates the typed DioException', () async {
    await expectLater(
      request.getFileResponseForUrl('http://127.0.0.1/anything'),
      throwsA(
        isA<DioException>().having(
          (e) => e.type,
          'type',
          DioExceptionType.badResponse,
        ),
      ),
    );
  });
}
