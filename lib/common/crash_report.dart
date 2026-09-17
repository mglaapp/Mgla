import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/common/constant.dart';
import 'package:fl_clash/common/path.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';

enum CrashDelivery { delivered, retryLater }

/// A crash left on disk so it can still be read after the restart.
///
/// The in-memory log dies with the process, which is exactly when it matters. On the next
/// launch a report goes to our own server, scrubbed first; the server scrubs it again.
class CrashReports {
  CrashReports({DateTime? startedAt})
    : _startedAt = startedAt ?? DateTime.now();

  static const int keepReports = 5;
  static const int uploadPerLaunch = 5;
  static const String _prefix = 'crash-';
  static const String _suffix = '.log';
  static const String _sentName = 'sent';

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

  /// A crash only the system saw: a native crash or an ANR never reaches a Dart handler.
  void recordExit(String reason, String? description) {
    final kind = switch (reason) {
      'anr' => 'anr',
      'initializationFailure' => 'init',
      _ => 'native',
    };
    final detail = description == null || description.isEmpty
        ? ''
        : ': $description';
    record('$reason$detail', null, kind: kind);
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

  /// Sends reports not yet delivered. A report the server refused as malformed counts as
  /// handled: sending it again would fail the same way on every launch.
  Future<int> upload(
    Future<CrashDelivery> Function(Map<String, String> report) send, {
    String fallbackVersion = '',
  }) async {
    final directory = _directory;
    if (directory == null) {
      return 0;
    }
    final reports = _reports();
    final sent = _readSent(directory);
    var handled = 0;
    for (final file in reports) {
      final stamp = _stampOf(file)!;
      if (sent.contains(stamp)) {
        continue;
      }
      if (handled >= uploadPerLaunch) {
        break;
      }
      final String text;
      try {
        text = file.readAsStringSync();
      } catch (_) {
        continue;
      }
      final report = parseCrashReport(text, fallbackVersion: fallbackVersion);
      if (report != null) {
        if (await send(report) == CrashDelivery.retryLater) {
          break;
        }
      }
      sent.add(stamp);
      handled++;
    }
    final kept = reports.map(_stampOf).whereType<int>().toSet();
    _writeSent(directory, sent.intersection(kept));
    return handled;
  }

  Set<int> _readSent(Directory directory) {
    try {
      return File(
        join(directory.path, _sentName),
      ).readAsLinesSync().map(int.tryParse).whereType<int>().toSet();
    } catch (_) {
      return <int>{};
    }
  }

  void _writeSent(Directory directory, Set<int> stamps) {
    try {
      directory.createSync(recursive: true);
      File(
        join(directory.path, _sentName),
      ).writeAsStringSync(stamps.map((stamp) => '$stamp\n').join());
    } catch (_) {
      return;
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

Map<String, String>? parseCrashReport(
  String text, {
  String fallbackVersion = '',
}) {
  final lines = const LineSplitter().convert(text);
  if (lines.isEmpty || !lines.first.startsWith('$appName ')) {
    return null;
  }
  var version = lines.first.substring(appName.length + 1).trim();
  if (version == 'unknown version') {
    version = fallbackVersion;
  }
  String field(String name) {
    final line = lines.firstWhere(
      (line) => line.startsWith('$name: '),
      orElse: () => '',
    );
    return line.isEmpty ? '' : line.substring(name.length + 2);
  }

  final system = field('system');
  final platform = system.split(' ').first;
  final errorAt = lines.indexWhere((line) => line.startsWith('error: '));
  final stackAt = lines.indexOf('stack:');
  if (version.isEmpty || platform.isEmpty || errorAt < 0) {
    return null;
  }
  final errorEnd = stackAt > errorAt ? stackAt : lines.length;
  final error = [
    lines[errorAt].substring('error: '.length),
    ...lines.sublist(errorAt + 1, errorEnd),
  ].join('\n');
  final stack = stackAt > errorAt ? lines.sublist(stackAt + 1).join('\n') : '';
  return {
    'kind': field('kind'),
    'platform': platform,
    'version': version,
    'os': scrubCrashText(system, limit: 120),
    'error': scrubCrashText(error, limit: 1000),
    'stack': scrubCrashText(stack, limit: 16000),
  };
}

// Keep in step with scrub() in omnivpn/crash.py: the server repeats this for older builds.
const _publicHosts = {
  'mgla.app',
  'www.mgla.app',
  'github.com',
  'api.github.com',
  'objects.githubusercontent.com',
  'release-assets.githubusercontent.com',
  'api.trongrid.io',
  't.me',
  'api.telegram.org',
};

final _windowsUser = RegExp(
  r'\b([a-z]:[\\/]+(?:users|documents and settings)[\\/]+)[^\\/\s:]+',
  caseSensitive: false,
);
final _unixUser = RegExp(r'(/(?:home|Users)/)[^/\s:]+');
final _url = RegExp(
  r'''\b([a-zA-Z][a-zA-Z0-9+.\-]{1,20})://[^\s'"<>()\[\]{}]+''',
);
final _uuid = RegExp(
  r'\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b',
);
final _email = RegExp(r'\b[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}\b');
final _secretValue = RegExp(
  r'''\b(private[_ ]?key|public[_ ]?key|pre[_ ]?shared[_ ]?key|password|passwd|secret|token|authorization|api[_ ]?key|sub[_ ]?id|login[_ ]?token)("?\s*[:=]\s*"?)[^\s,;"'}]+''',
  caseSensitive: false,
);
final _ipv4 = RegExp(
  r'\b(?:25[0-5]|2[0-4]\d|1?\d?\d)(?:\.(?:25[0-5]|2[0-4]\d|1?\d?\d)){3}\b',
);
final _ipv6 = RegExp(
  r'(?<![0-9A-Za-z:])(?:(?:[0-9a-fA-F]{1,4}:){3,7}[0-9a-fA-F]{1,4}|(?:[0-9a-fA-F]{1,4}:){1,7}:(?:[0-9a-fA-F]{1,4}(?::[0-9a-fA-F]{1,4}){0,6})?)(?![0-9A-Za-z:])',
);
final _token = RegExp(
  r'(?<![A-Za-z0-9_\-+=])(?=[A-Za-z0-9_\-+=]*\d)(?=[A-Za-z0-9_\-+=]*[A-Za-z])[A-Za-z0-9_\-+=]{20,}(?![A-Za-z0-9_\-+=])',
);

String _urlMark(Match match) {
  final scheme = match[1]!.toLowerCase();
  if (scheme == 'file') {
    return '<file>';
  }
  final rest = match[0]!.substring(match[1]!.length + 3);
  final authority = rest.split('/').first;
  final host = authority.contains('@')
      ? ''
      : authority.split(RegExp('[:?#]')).first.toLowerCase();
  if ((scheme == 'http' || scheme == 'https') && _publicHosts.contains(host)) {
    return '<$scheme://$host/…>';
  }
  return '<$scheme-url>';
}

/// What must not leave the device in a VPN client's crash: links carry the subscription key,
/// a UUID is the VLESS credential, and a user name hides in home-directory paths.
String scrubCrashText(String text, {required int limit}) {
  final scrubbed = text
      .replaceAllMapped(_windowsUser, (m) => '${m[1]}<user>')
      .replaceAllMapped(_unixUser, (m) => '${m[1]}<user>')
      .replaceAllMapped(_url, _urlMark)
      .replaceAll(_uuid, '<uuid>')
      .replaceAll(_email, '<email>')
      .replaceAllMapped(_secretValue, (m) => '${m[1]}${m[2]}<secret>')
      .replaceAll(_ipv4, '<ip>')
      .replaceAll(_ipv6, '<ip>')
      .replaceAll(_token, '<token>');
  return scrubbed.length > limit ? scrubbed.substring(0, limit) : scrubbed;
}

final crashReports = CrashReports();
