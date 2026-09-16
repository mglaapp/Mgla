import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/subscription.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/test_app.dart';
import '../helpers/test_profiles.dart';

/// Экран подписки и экран возврата доступа.
///
/// ЧТО ЗДЕСЬ ВАЖНО ПРОВЕРИТЬ, А ЧТО НЕТ. Разбор ответов сервера проверяется отдельно
/// (test/models/account_test.dart) и без сети. Здесь — ровно те решения владельца, которые
/// живут в разметке и иначе проверяются только глазами: порядок способов возврата доступа и
/// таймер на кнопке подтверждения.
ProviderContainer _containerFor(
  WidgetTester tester, {
  List<Profile> profiles = const [],
  Size size = const Size(1000, 1400),
}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final container = ProviderContainer(
    overrides: [profilesProvider.overrideWith(() => TestProfiles(profiles))],
  );
  addTearDown(container.dispose);
  globalState.container = container;
  return container;
}

Future<void> _pump(WidgetTester tester, Widget child) async {
  final container = _containerFor(tester);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: TestApp(child: child),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('без профиля экран предлагает завести аккаунт, а не только ключ', (
    tester,
  ) async {
    await _pump(tester, const SubscriptionView());

    final context = tester.element(find.byType(SubscriptionView));
    final l = context.appLocalizations;

    // Человек, поставивший приложение до покупки, обязан видеть выход отсюда: до 16-09 он
    // упирался в поле, которое просит то, чего у него нет.
    expect(find.text(l.createAccount), findsOneWidget);
    expect(find.text(l.accessKey), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('возврат доступа: почта, телеграм, и только потом ссылка входа', (
    tester,
  ) async {
    await _pump(
      tester,
      const RecoveryView(
        accessKey: '9ac0394dfc2f68b5846e7ac4',
        loginUrl: 'https://mgla.app/login/TOKEN',
      ),
    );

    final context = tester.element(find.byType(RecoveryView));
    final l = context.appLocalizations;

    // Порядок — решение владельца, а не оформление: пока ссылка стояла первой, она читалась
    // как основной способ, а она равна паролю и теряется вместе с устройством.
    final email = tester.getTopLeft(find.text(l.bindEmail).first).dy;
    final telegram = tester.getTopLeft(find.text(l.bindTelegram).first).dy;
    final link = tester.getTopLeft(find.text(l.loginLinkTitle).first).dy;
    expect(email, lessThan(telegram));
    expect(telegram, lessThan(link));

    // Предупреждение стоит ДО того, как ссылку показали.
    expect(find.text(l.loginLinkWarning), findsOneWidget);
    expect(find.text('https://mgla.app/login/TOKEN'), findsNothing);
  });

  testWidgets('кнопка «я сохранил» недоступна, пока идёт отсчёт', (
    tester,
  ) async {
    await _pump(
      tester,
      const RecoveryView(
        accessKey: '9ac0394dfc2f68b5846e7ac4',
        loginUrl: 'https://mgla.app/login/TOKEN',
      ),
    );

    final context = tester.element(find.byType(RecoveryView));
    final l = context.appLocalizations;

    await tester.tap(find.widgetWithText(TextButton, l.showLink));
    await tester.pump();

    expect(find.text('https://mgla.app/login/TOKEN'), findsOneWidget);

    // Кнопка, доступная сразу, нажимается ДО чтения: человек подтверждает, что понял про
    // пароль, не прочитав про пароль. Поэтому здесь проверяется именно НЕДОСТУПНОСТЬ.
    // .first намеренно: textContaining находит и Text, и его RichText, поэтому кнопка
    // приезжает в списке дважды. Это одна и та же кнопка, а не две разные.
    FilledButton confirm() => tester.widget<FilledButton>(
      find
          .ancestor(
            of: find.textContaining(l.savedIt),
            matching: find.byType(FilledButton),
          )
          .first,
    );
    expect(confirm().onPressed, isNull, reason: 'отсчёт ещё идёт');

    await tester.pump(const Duration(seconds: 2));
    expect(confirm().onPressed, isNull, reason: 'двух секунд мало');

    await tester.pump(const Duration(seconds: 3));
    expect(confirm().onPressed, isNotNull, reason: 'отсчёт кончился');
    expect(tester.takeException(), isNull);
  });

  testWidgets('без ссылки входа раздела ссылки нет вовсе', (tester) async {
    // Сервер отдаёт ссылку только при создании аккаунта. На этот экран, открытый позже, её
    // нет — и показывать пустой раздел честнее не было бы.
    await _pump(
      tester,
      const RecoveryView(accessKey: '9ac0394dfc2f68b5846e7ac4'),
    );

    final context = tester.element(find.byType(RecoveryView));
    final l = context.appLocalizations;

    expect(find.text(l.bindEmail), findsWidgets);
    expect(find.text(l.loginLinkTitle), findsNothing);
    expect(find.text(l.showLink), findsNothing);
  });
}
