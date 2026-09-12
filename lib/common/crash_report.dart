import 'dart:io';

import 'package:fl_clash/common/constant.dart';
import 'package:fl_clash/common/path.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';

/// A crash left on disk so it can still be read after the restart.
///
/// The in-memory log dies with the process, which is exactly when it matters. Nothing here
/// leaves the device on its own: the report travels with the log the user exports by hand.
class CrashReports {
  CrashReports({DateTime? startedAt})
    : _startedAt = startedAt ?? DateTime.now();

  static const int keepReports = 5;
  static const String _prefix = 'crash-';
  static const String _suffix = '.log';

  final DateTime _startedAt;
  Directory? _directory;

  /// Set once the package info is read; an early crash happens before that and must not guess.
  String appVersion = '';

  Future<void> init() async {
    useDirectory(Directory(join(await appPath.homeDirPath, 'crash')));
  }

  @visibleForTesting
  void useDirectory(Directory directory) {
    _directory = directory;
  }

  /// Written synchronously on purpose: the process may not outlive an async write.
  void record(Object error, StackTrace? stack, {required String kind}) {
    final directory = _directory;
    if (directory == null) {
      return;
    }
    try {
      directory.createSync(recursive: true);
      final at = DateTime.now();
      var stamp = at.microsecondsSinceEpoch;
      var file = File(join(directory.path, '$_prefix$stamp$_suffix'));
      while (file.existsSync()) {
        stamp += 1;
        file = File(join(directory.path, '$_prefix$stamp$_suffix'));
      }
      file.writeAsStringSync(_describe(at, kind, error, stack));
      _rotate(directory);
    } catch (_) {
      // A failed report must never replace the failure it describes.
    }
  }

  /// Whether a report is left over from an earlier run of the app.
  bool recordedBeforeThisRun() {
    final startedAt = _startedAt.microsecondsSinceEpoch;
    return _reports().any((file) => (_stampOf(file) ?? startedAt) < startedAt);
  }

  String? latest() {
    final reports = _reports();
    if (reports.isEmpty) {
      return null;
    }
    try {
      return reports.last.readAsStringSync();
    } catch (_) {
      return null;
    }
  }

  List<File> _reports() {
    final directory = _directory;
    if (directory == null || !directory.existsSync()) {
      return const [];
    }
    try {
      final files = directory
          .listSync()
          .whereType<File>()
          .where((file) => _stampOf(file) != null)
          .toList();
      files.sort((a, b) => _stampOf(a)!.compareTo(_stampOf(b)!));
      return files;
    } catch (_) {
      return const [];
    }
  }

  int? _stampOf(File file) {
    final name = basename(file.path);
    if (!name.startsWith(_prefix) || !name.endsWith(_suffix)) {
      return null;
    }
    return int.tryParse(
      name.substring(_prefix.length, name.length - _suffix.length),
    );
  }

  void _rotate(Directory directory) {
    final reports = _reports();
    for (final file in reports.take(
      reports.length - keepReports < 0 ? 0 : reports.length - keepReports,
    )) {
      try {
        file.deleteSync();
      } catch (_) {
        continue;
      }
    }
  }

  String _describe(DateTime at, String kind, Object error, StackTrace? stack) {
    final buffer = StringBuffer()
      ..writeln(
        '$appName ${appVersion.isEmpty ? 'unknown version' : appVersion}',
      )
      ..writeln('when: ${at.toIso8601String()}')
      ..writeln(
        'system: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
      )
      ..writeln('kind: $kind')
      ..writeln('error: $error');
    if (stack != null) {
      buffer
        ..writeln('stack:')
        ..writeln(stack);
    }
    return buffer.toString();
  }
}

final crashReports = CrashReports();
