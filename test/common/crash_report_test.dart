import 'dart:io';

import 'package:fl_clash/common/crash_report.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('mgla_crash_');
  });

  tearDown(() {
    if (directory.existsSync()) {
      directory.deleteSync(recursive: true);
    }
  });

  CrashReports reports({DateTime? startedAt}) {
    final instance = CrashReports(startedAt: startedAt);
    instance.useDirectory(directory);
    return instance;
  }

  test('keeps the error and the stack where a restart can read them', () {
    final instance = reports();
    instance.appVersion = '1.2.3';

    instance.record(
      StateError('boom'),
      StackTrace.fromString('frame one'),
      kind: 'flutter',
    );

    final text = instance.latest();
    expect(text, contains('boom'));
    expect(text, contains('frame one'));
    expect(text, contains('1.2.3'));
    expect(text, contains('kind: flutter'));
  });

  test('calls the version unknown instead of guessing it', () {
    final instance = reports();

    instance.record(StateError('boom'), null, kind: 'flutter');

    expect(instance.latest(), contains('unknown version'));
  });

  test('keeps only the last reports', () {
    final instance = reports();

    for (var i = 0; i < CrashReports.keepReports + 3; i++) {
      instance.record(StateError('boom $i'), null, kind: 'flutter');
    }

    expect(
      directory.listSync().whereType<File>().length,
      CrashReports.keepReports,
    );
    expect(instance.latest(), contains('boom 7'));
  });

  test('a report from this run is not a crash of the previous one', () {
    final instance = reports();

    expect(instance.recordedBeforeThisRun(), isFalse);

    instance.record(StateError('boom'), null, kind: 'flutter');

    expect(instance.recordedBeforeThisRun(), isFalse);
  });

  test('a report left by an earlier run is reported as one', () {
    reports(
      startedAt: DateTime.now().subtract(const Duration(minutes: 5)),
    ).record(StateError('boom'), null, kind: 'flutter');

    final current = reports(
      startedAt: DateTime.now().add(const Duration(minutes: 5)),
    );

    expect(current.recordedBeforeThisRun(), isTrue);
  });

  test('stays quiet when the directory was never resolved', () {
    final instance = CrashReports();

    expect(
      () => instance.record(StateError('boom'), null, kind: 'flutter'),
      returnsNormally,
    );
    expect(instance.latest(), isNull);
    expect(instance.recordedBeforeThisRun(), isFalse);
  });

  test('ignores files that are not reports', () {
    File(
      '${directory.path}${Platform.pathSeparator}notes.txt',
    ).writeAsStringSync('hello');
    final instance = reports();

    expect(instance.latest(), isNull);
    expect(instance.recordedBeforeThisRun(), isFalse);
  });

  group('scrubCrashText', () {
    const subId = '3f9a1c0be47d52a8c61e9b04';
    const uuid = 'b7e2c1d4-5a6f-4e3b-9c8d-1f2a3b4c5d6e';
    const wgKey = 'Y3Jhc2hmaXgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=';
    const loginToken = 'q3ZrV8sXk2mN4pL7tY9wB1cD5fG6hJ0e';
    const stack =
        '#0      ProfilesNotifier.update (package:fl_clash/providers/profiles.dart:142:7)\n'
        '#1      _SubscriptionView._refresh (package:fl_clash/pages/subscription/view2.dart:88:12)\n'
        '#2      _RootZone.runUnaryGuarded (dart:async/zone.dart:1594:10)\n'
        'PrivateKey = $wgKey\n'
        'url: https://mgla.app/sub/$subId?format=awg\n'
        'link vless://$uuid@171.22.30.253:8443?security=reality#Mgla\n'
        r'at C:\Users\IvanPetrov\AppData\Roaming\app.mgla\profiles\x.yaml'
        '\n'
        'at /home/ivan/.local/share/app.mgla/config.yaml\n'
        'server 2a01:4f8:c17:1234::1 port 443\n'
        'mail ivan.petrov@gmail.com\n'
        'login token=$loginToken\n';

    final clean = scrubCrashText(stack, limit: 16000);

    for (final secret in [
      subId,
      uuid,
      wgKey,
      loginToken,
      '171.22.30.253',
      '2a01:4f8:c17:1234::1',
      'ivan.petrov@gmail.com',
      'IvanPetrov',
      '/home/ivan/',
    ]) {
      test('removes $secret', () {
        expect(clean, isNot(contains(secret)));
      });
    }

    test('keeps what makes the report useful', () {
      expect(clean, contains('ProfilesNotifier.update'));
      expect(
        clean,
        contains('package:fl_clash/pages/subscription/view2.dart:88:12'),
      );
      expect(clean, contains('dart:async/zone.dart:1594:10'));
      expect(clean, contains('app.mgla'));
    });

    test('keeps our own host but not the path behind it', () {
      expect(clean, contains('<https://mgla.app/…>'));
      expect(clean, contains('<vless-url>'));
      expect(
        scrubCrashText('GET https://other-vpn.example/sub/abc', limit: 200),
        'GET <https-url>',
      );
    });

    test('a look-alike host or a user in the link does not pass as ours', () {
      final text = scrubCrashText(
        'https://mgla.app.evil.example/x https://user@mgla.app/x',
        limit: 200,
      );
      expect(text, isNot(contains('evil')));
      expect(text, isNot(contains('user')));
    });

    test('a clock time and a version are not addresses', () {
      expect(scrubCrashText('at 12:30:45', limit: 100), 'at 12:30:45');
      expect(scrubCrashText('Mgla 0.9.4', limit: 100), 'Mgla 0.9.4');
    });

    test('cuts to the limit', () {
      expect(scrubCrashText('x' * 5000, limit: 1000).length, 1000);
    });
  });

  group('upload', () {
    test('a written report parses back into the server fields', () {
      final instance = reports()..appVersion = '0.9.5';
      instance.record(
        StateError('Bad state: https://mgla.app/sub/3f9a1c0be47d52a8c61e9b04'),
        StackTrace.fromString('#0 Foo.bar (package:fl_clash/x.dart:1:2)'),
        kind: 'flutter',
      );

      final report = parseCrashReport(instance.latest()!)!;

      expect(report['kind'], 'flutter');
      expect(report['version'], '0.9.5');
      expect(report['platform'], Platform.operatingSystem);
      expect(report['error'], contains('Bad state'));
      expect(report['error'], isNot(contains('3f9a1c0be47d52a8c61e9b04')));
      expect(report['stack'], contains('Foo.bar'));
    });

    test('an early crash takes the running version instead of none', () {
      reports().record(StateError('boom'), null, kind: 'init');

      final report = parseCrashReport(
        reports().latest()!,
        fallbackVersion: '0.9.5',
      );

      expect(report!['version'], '0.9.5');
      expect(report['stack'], isEmpty);
    });

    test('not one of ours is not sent', () {
      expect(parseCrashReport('hello\nworld'), isNull);
    });

    test('each report is sent once', () async {
      final instance = reports()..appVersion = '0.9.5';
      instance.record(StateError('one'), null, kind: 'flutter');
      instance.record(StateError('two'), null, kind: 'flutter');
      final sent = <String>[];
      Future<CrashDelivery> send(Map<String, String> report) async {
        sent.add(report['error']!);
        return CrashDelivery.delivered;
      }

      expect(await instance.upload(send), 2);
      expect(await instance.upload(send), 0);
      expect(sent, ['Bad state: one', 'Bad state: two']);
    });

    test(
      'an unreachable server keeps the report for the next launch',
      () async {
        final instance = reports()..appVersion = '0.9.5';
        instance.record(StateError('one'), null, kind: 'flutter');
        instance.record(StateError('two'), null, kind: 'flutter');
        var calls = 0;

        final handled = await instance.upload((_) async {
          calls++;
          return CrashDelivery.retryLater;
        });

        expect(handled, 0);
        expect(calls, 1);
        expect(await instance.upload((_) async => CrashDelivery.delivered), 2);
      },
    );

    test('sends no more than the per-launch cap', () async {
      final extra = CrashReports.uploadPerLaunch + 2;
      for (var i = 1; i <= extra; i++) {
        File(
          '${directory.path}${Platform.pathSeparator}crash-$i.log',
        ).writeAsStringSync(
          'Mgla 0.9.5\nsystem: android 14\nkind: flutter\nerror: boom $i\n',
        );
      }
      final instance = reports();

      expect(
        await instance.upload((_) async => CrashDelivery.delivered),
        CrashReports.uploadPerLaunch,
      );
      expect(await instance.upload((_) async => CrashDelivery.delivered), 2);
    });

    test('an unparsable report counts as handled and is not retried', () async {
      File(
        '${directory.path}${Platform.pathSeparator}crash-1.log',
      ).writeAsStringSync('garbage');
      final instance = reports();
      var calls = 0;

      expect(
        await instance.upload((_) async {
          calls++;
          return CrashDelivery.delivered;
        }),
        1,
      );
      expect(calls, 0);
      expect(await instance.upload((_) async => CrashDelivery.delivered), 0);
    });

    test('the sent list forgets reports that rotated away', () async {
      final instance = reports()..appVersion = '0.9.5';
      instance.record(StateError('old'), null, kind: 'flutter');
      await instance.upload((_) async => CrashDelivery.delivered);
      for (var i = 0; i < CrashReports.keepReports; i++) {
        instance.record(StateError('new $i'), null, kind: 'flutter');
      }

      await instance.upload((_) async => CrashDelivery.delivered);

      final sent = File(
        '${directory.path}${Platform.pathSeparator}sent',
      ).readAsLinesSync();
      expect(sent.length, CrashReports.keepReports);
    });

    test('a native exit becomes a report of its own kind', () {
      final instance = reports()..appVersion = '0.9.5';

      instance.recordExit('anr', 'Input dispatching timed out');
      expect(parseCrashReport(instance.latest()!)!['kind'], 'anr');

      instance.recordExit('crashNative', null);
      final report = parseCrashReport(instance.latest()!)!;
      expect(report['kind'], 'native');
      expect(report['error'], 'crashNative');
    });
  });
}
