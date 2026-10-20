import 'dart:async';

import 'package:fl_clash/core/desktop/model.dart';
import 'package:fl_clash/core/interface.dart';
import 'package:fl_clash/core/method.dart';
import 'package:test/test.dart';

/// Core that is not connected yet: every call fails in the transport, the way the 0.9.8 crash
/// report from Windows did ("transport_error, Unable to send stopLog to Core, Bad state: No
/// element", 20-10).
class _DisconnectedCore extends CoreHandlerInterface {
  final invoked = <CoreMethod>[];

  @override
  Future<T?> invokeMethod<T>({
    required CoreMethod method,
    Object? arguments,
    Duration? timeout,
  }) async {
    invoked.add(method);
    throw CoreMethodException(
      code: 'transport_error',
      message: 'Unable to send ${method.name} to Core',
      details: 'Bad state: No element',
    );
  }

  @override
  Future<CoreLifecycleResult> start() async => _unused;

  @override
  Future<CoreLifecycleResult> restart() async => _unused;

  @override
  Future<CoreLifecycleResult> stop() async => _unused;

  @override
  Future<CoreLifecycleResult> close() async => _unused;
}

const _unused = CoreLifecycleResult(
  revision: 0,
  outcome: CoreLifecycleOutcome.applied,
);

void main() {
  test(
    'log toggles and traffic reset never escape as unhandled errors',
    () async {
      final core = _DisconnectedCore();
      final escaped = <Object>[];
      await runZonedGuarded(() async {
        core.stopLog();
        core.startLog();
        core.resetTraffic();
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }, (error, _) => escaped.add(error));

      expect(core.invoked, [
        CoreMethod.stopLog,
        CoreMethod.startLog,
        CoreMethod.resetTraffic,
      ], reason: 'the calls are still made');
      expect(escaped, isEmpty, reason: 'nothing reaches the crash reporter');
    },
  );
}
