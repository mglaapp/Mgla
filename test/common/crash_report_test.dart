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
}
