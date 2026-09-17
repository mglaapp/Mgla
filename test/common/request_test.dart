import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fl_clash/common/crash_report.dart';
import 'package:fl_clash/common/request.dart';
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
    globalState.packageInfo = PackageInfo(
      appName: 'Mgla',
      packageName: 'app.mgla',
      version: '0.9.5',
      buildNumber: '2026091701',
    );

    expect(
      Request.appHeader(),
      matches(
        RegExp(r'^0\.9\.5\+2026091701; (android|windows|macos|linux|ios)$'),
      ),
    );
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
