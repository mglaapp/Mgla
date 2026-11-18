import 'dart:io';

import 'package:dio/dio.dart';
import 'package:fl_clash/common/app_update.dart';
import 'package:fl_clash/common/our_hosts.dart';
import 'package:fl_clash/common/site_route.dart';
import 'package:flutter_test/flutter_test.dart';

const _main = 'https://mgla.app';
const _backup = 'https://171.22.133.125.sslip.io';

DioException _err(
  DioExceptionType type, {
  Object? error,
  bool withResponse = false,
}) {
  final options = RequestOptions(path: '$_main/api/v1/x');
  return DioException(
    requestOptions: options,
    type: type,
    error: error,
    response: withResponse
        ? Response<Object>(requestOptions: options, statusCode: 502)
        : null,
  );
}

void main() {
  test(
    'the backup is the bridge in Moscow, under a name without our brand',
    () {
      expect(siteBases.first, _main);
      expect(siteBackups, [_backup]);
      expect(siteBackups.every((b) => !b.contains('mgla')), isTrue);
    },
  );

  test('our URLs move between the addresses with path and query', () {
    final route = SiteRoute();
    expect(route.candidates('$_main/api/v1/account?cur=rub'), [
      '$_main/api/v1/account?cur=rub',
      '$_backup/api/v1/account?cur=rub',
    ]);
    expect(route.candidates('$_main/sub/KEY'), [
      '$_main/sub/KEY',
      '$_backup/sub/KEY',
    ]);
    // anyone else's and look-alikes stay alone
    expect(route.candidates('https://example.com/sub/x'), [
      'https://example.com/sub/x',
    ]);
    expect(route.candidates('https://mgla.app.evil.io/sub/x'), [
      'https://mgla.app.evil.io/sub/x',
    ]);
    expect(route.baseOf('https://mgla.apple.com/x'), isNull);
    expect(route.isSiteHost('171.22.133.125.sslip.io'), isTrue);
    expect(route.isSiteHost('MGLA.APP'), isTrue);
    expect(route.isSiteHost('github.com'), isFalse);
  });

  test(
    'a backup that answered is asked first for a while, then mgla.app again',
    () {
      var now = DateTime(2026, 11, 18);
      final route = SiteRoute(clock: () => now);
      route.answered('$_backup/api/v1/status');
      expect(route.candidates('$_main/sub/K').first, '$_backup/sub/K');
      now = now.add(const Duration(minutes: 9));
      expect(route.candidates('$_main/sub/K').first, '$_backup/sub/K');
      now = now.add(const Duration(minutes: 2));
      expect(route.candidates('$_main/sub/K').first, '$_main/sub/K');

      route.answered('$_backup/api/v1/status');
      route.answered('$_main/api/v1/status');
      expect(route.candidates('$_main/sub/K').first, '$_main/sub/K');

      route.answered('$_backup/api/v1/status');
      route.forget();
      expect(route.candidates('$_main/sub/K').first, '$_main/sub/K');
    },
  );

  group('run', () {
    test('mgla.app not reached -> the same request on the backup', () async {
      final route = SiteRoute();
      final asked = <String>[];
      final got = await route.run('$_main/api/v1/servers', (url) async {
        asked.add(url);
        if (url.startsWith(_main)) {
          throw _err(DioExceptionType.connectionTimeout);
        }
        return 'ok';
      }, retry: (e) => siteUnreached(e, repeatable: true));
      expect(got, 'ok');
      expect(asked, ['$_main/api/v1/servers', '$_backup/api/v1/servers']);
      // the next call goes where the answer was
      expect(route.candidates('$_main/x').first, '$_backup/x');
    });

    test(
      'a request that may have reached the server is not repeated',
      () async {
        final route = SiteRoute();
        final asked = <String>[];
        await expectLater(
          route.run('$_main/api/v1/account', (url) async {
            asked.add(url);
            throw _err(DioExceptionType.receiveTimeout);
          }, retry: (e) => siteUnreached(e, repeatable: false)),
          throwsA(isA<DioException>()),
        );
        expect(asked, ['$_main/api/v1/account']);
      },
    );

    test('every address down -> the last failure as it was', () async {
      final route = SiteRoute();
      final asked = <String>[];
      await expectLater(
        route.run('$_main/sub/K', (url) async {
          asked.add(url);
          throw _err(
            DioExceptionType.connectionError,
            error: const SocketException('x'),
          );
        }, retry: (e) => siteUnreached(e, repeatable: true)),
        throwsA(
          isA<DioException>().having(
            (e) => e.type,
            'type',
            DioExceptionType.connectionError,
          ),
        ),
      );
      expect(asked, hasLength(2));
      expect(route.candidates('$_main/x').first, '$_main/x');
    });
  });

  test('what counts as «never reached the server»', () {
    bool post(DioException e) => siteUnreached(e, repeatable: false);
    bool get(DioException e) => siteUnreached(e, repeatable: true);

    final connectTimeout = _err(DioExceptionType.connectionTimeout);
    final refused = _err(
      DioExceptionType.connectionError,
      error: const SocketException('refused'),
    );
    final tls = _err(
      DioExceptionType.unknown,
      error: const HandshakeException('reset'),
    );
    final closedAfterSend = _err(
      DioExceptionType.connectionError,
      error: const HttpException(
        'Connection closed before full header was received',
      ),
    );
    final resetAfterSend = _err(
      DioExceptionType.unknown,
      error: const SocketException('reset'),
    );
    final frozen = _err(DioExceptionType.receiveTimeout);

    for (final e in [connectTimeout, refused, tls]) {
      expect(post(e), isTrue, reason: '$e');
      expect(get(e), isTrue, reason: '$e');
    }
    for (final e in [closedAfterSend, resetAfterSend, frozen]) {
      expect(post(e), isFalse, reason: '$e');
      expect(get(e), isTrue, reason: '$e');
    }
    // an answer is an answer, a cancel is the person's
    expect(
      get(_err(DioExceptionType.badResponse, withResponse: true)),
      isFalse,
    );
    expect(get(_err(DioExceptionType.unknown, withResponse: true)), isFalse);
    expect(get(_err(DioExceptionType.cancel)), isFalse);
    expect(
      siteUnreached(const FormatException('x'), repeatable: true),
      isFalse,
    );
  });

  group('updates through the backup', () {
    final release = {
      'tag_name': 'v0.9.20',
      'assets': [
        {
          'name': 'Mgla-0.9.20-windows-amd64-setup.exe',
          'browser_download_url':
              '$_main/download/v0.9.20/Mgla-0.9.20-windows-amd64-setup.exe',
        },
        {
          'name': 'SHA256SUMS',
          'browser_download_url': '$_main/download/v0.9.20/SHA256SUMS',
        },
        {
          'name': 'notes.txt',
          'browser_download_url': 'https://github.com/mglaapp/Mgla/notes.txt',
        },
      ],
    };

    List<String> links(Map<String, dynamic> r) => [
      for (final a in r['assets'] as List)
        (a as Map)['browser_download_url'] as String,
    ];

    test('a release from the backup fetches its files there too', () {
      final moved = releaseServedFrom(
        release,
        '$_backup/api/v1/app/release',
        route: SiteRoute(),
      );
      expect(links(moved), [
        '$_backup/download/v0.9.20/Mgla-0.9.20-windows-amd64-setup.exe',
        '$_backup/download/v0.9.20/SHA256SUMS',
        'https://github.com/mglaapp/Mgla/notes.txt',
      ]);
      expect(moved['tag_name'], 'v0.9.20');
      // the file passes the «our hosts only» rule of the installer (audit M5-7)
      final asset = pickUpdateAsset(
        moved['assets'] as List,
        '-windows-amd64-setup.exe',
      );
      expect(asset?.url, startsWith(_backup));
    });

    test('a release from mgla.app or GitHub is left as it came', () {
      expect(
        links(
          releaseServedFrom(
            release,
            '$_main/api/v1/app/release',
            route: SiteRoute(),
          ),
        ),
        links(release),
      );
      expect(
        links(
          releaseServedFrom(
            release,
            'https://api.github.com/repos/mglaapp/Mgla/releases/latest',
            route: SiteRoute(),
          ),
        ),
        links(release),
      );
    });

    test('the backup never takes a bad certificate', () {
      expect(strictTlsHost('171.22.133.125.sslip.io'), isTrue);
      expect(strictTlsHost('evil.sslip.io'), isFalse);
    });
  });
}
