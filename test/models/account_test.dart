import 'package:fl_clash/models/account.dart';
import 'package:test/test.dart';

/// Разбор ответов нашего API. Он защитный НАМЕРЕННО: ответ приходит по сети, и приложение,
/// падающее на неожиданном поле, ломается в единственный момент, когда человек платит деньги.
/// Поэтому здесь проверяется не только «хорошие данные разобрались», но и что мусор не роняет
/// и не превращается в правдоподобную выдумку.
void main() {
  group('Plan', () {
    test('обычный тариф разбирается', () {
      final plan = Plan.fromJson({
        'code': '1m',
        'days': 30,
        'usd': 3.49,
        'title': '1 месяц',
      });
      expect(plan, isNotNull);
      expect(plan!.code, '1m');
      expect(plan.days, 30);
      expect(plan.usd, 3.49);
      expect(plan.title, '1 месяц');
    });

    test('без кода или без дней тариф не собирается', () {
      expect(Plan.fromJson({'days': 30}), isNull);
      expect(Plan.fromJson({'code': '1m'}), isNull);
      expect(Plan.fromJson('строка'), isNull);
      expect(Plan.fromJson(null), isNull);
    });

    test('цена целым числом не теряется', () {
      expect(Plan.fromJson({'code': '3m', 'days': 90, 'usd': 9})?.usd, 9.0);
    });

    test('без названия его заменяет код — пустой строки в списке не будет', () {
      expect(Plan.fromJson({'code': '12m', 'days': 365})?.title, '12m');
    });

    test('мусор внутри списка выбрасывается, остальное остаётся', () {
      final plans = Plan.listFrom([
        {'code': '1m', 'days': 30, 'usd': 3.49},
        'мусор',
        null,
        {'days': 90},
        {'code': '3m', 'days': 90, 'usd': 8.99},
      ]);
      expect(plans.map((plan) => plan.code), ['1m', '3m']);
    });

    test('список не списком даёт пусто, а не падение', () {
      expect(Plan.listFrom(null), isEmpty);
      expect(Plan.listFrom({'code': '1m'}), isEmpty);
    });
  });

  group('AccountStatus', () {
    test('оплаченный доступ разбирается целиком', () {
      final status = AccountStatus.fromJson({
        'key': '9ac0394dfc2f68b5',
        'active': true,
        'blocked': false,
        'expires_at': '2026-10-16T01:00:00+00:00',
        'days_left': 30,
        'used_gb': 1.25,
        'quota_gb': 200.0,
        'plans': [
          {'code': '1m', 'days': 30, 'usd': 3.49},
        ],
        'methods': {'usdt': true, 'card': false},
      });
      expect(status, isNotNull);
      expect(status!.active, isTrue);
      expect(status.key, '9ac0394dfc2f68b5');
      expect(status.expiresAt, DateTime.utc(2026, 10, 16, 1));
      expect(status.daysLeft, 30);
      expect(status.usedGb, 1.25);
      expect(status.quotaGb, 200.0);
      expect(status.plans, hasLength(1));
      expect(status.usdtEnabled, isTrue);
    });

    test('без ключа статуса нет: спрашивать сервер будет не о чем', () {
      expect(AccountStatus.fromJson({'active': true}), isNull);
      expect(AccountStatus.fromJson({'key': ''}), isNull);
    });

    test('неоплаченный аккаунт разбирается, а не считается поломкой', () {
      final status = AccountStatus.fromJson({
        'key': 'abc0394dfc2f68b5',
        'active': false,
        'expires_at': null,
        'days_left': null,
      });
      expect(status, isNotNull);
      expect(status!.active, isFalse);
      expect(status.expiresAt, isNull);
      expect(status.daysLeft, isNull);
      expect(status.plans, isEmpty);
    });

    test('негодная дата даёт null, а не выдуманный срок', () {
      final status = AccountStatus.fromJson({
        'key': 'abc0394dfc2f68b5',
        'expires_at': 'позавчера',
      });
      expect(status?.expiresAt, isNull);
    });

    test('способ оплаты выключен, пока сервер прямо не сказал «да»', () {
      for (final methods in <Object?>[
        null,
        <String, Object?>{},
        {'usdt': false},
        {'usdt': 'true'},
        'мусор',
      ]) {
        final status = AccountStatus.fromJson({
          'key': 'abc0394dfc2f68b5',
          'methods': methods,
        });
        expect(status?.usdtEnabled, isFalse, reason: 'methods = $methods');
      }
    });
  });

  group('NewAccount', () {
    test('созданный аккаунт несёт ключ, адрес подписки и ссылку входа', () {
      final account = NewAccount.fromJson({
        'key': '9ac0394dfc2f68b5',
        'sub_url': 'https://mgla.app/sub/9ac0394dfc2f68b5',
        'login_url': 'https://mgla.app/login/TOKEN',
      });
      expect(account, isNotNull);
      expect(account!.key, '9ac0394dfc2f68b5');
      expect(account.loginUrl, 'https://mgla.app/login/TOKEN');
    });

    test(
      'без ссылки входа аккаунт всё равно годен: ключа хватает на оплату',
      () {
        final account = NewAccount.fromJson({
          'key': '9ac0394dfc2f68b5',
          'sub_url': 'https://mgla.app/sub/9ac0394dfc2f68b5',
        });
        expect(account?.loginUrl, '');
      },
    );

    test('без ключа или адреса подписки аккаунта нет', () {
      expect(
        NewAccount.fromJson({'sub_url': 'https://mgla.app/sub/x'}),
        isNull,
      );
      expect(NewAccount.fromJson({'key': 'abc'}), isNull);
    });
  });

  group('UsdtInvoice', () {
    test('счёт разбирается целиком', () {
      final invoice = UsdtInvoice.fromJson({
        'address': 'THKn2uTUTjAnneWN9enoLFYtXVtjroadtr',
        'amount': '3.5367',
        'network': 'TRON (TRC-20)',
        'qr_payload': 'tron:THKn2uTUTjAnneWN9enoLFYtXVtjroadtr?amount=3.5367',
        'qr_svg': '<svg></svg>',
        'minutes_left': 59,
      });
      expect(invoice, isNotNull);
      expect(invoice!.amount, '3.5367');
      expect(invoice.minutesLeft, 59);
      expect(invoice.qrSvg, '<svg></svg>');
    });

    test('сумма остаётся СТРОКОЙ: по ней идёт сверка с блокчейном', () {
      final invoice = UsdtInvoice.fromJson({
        'address': 'THKn2uTUTjAnneWN9enoLFYtXVtjroadtr',
        'amount': '3.5000',
      });
      expect(invoice?.amount, isA<String>());
      expect(invoice?.amount, '3.5000');
    });

    test('пустой QR — рабочий случай, а не поломка счёта', () {
      final invoice = UsdtInvoice.fromJson({
        'address': 'THKn2uTUTjAnneWN9enoLFYtXVtjroadtr',
        'amount': '3.5367',
      });
      expect(invoice, isNotNull);
      expect(invoice!.qrSvg, '');
      expect(invoice.network, 'TRON (TRC-20)');
      expect(invoice.minutesLeft, 0);
    });

    test('без адреса или суммы счёта нет: платить было бы некуда', () {
      expect(UsdtInvoice.fromJson({'amount': '3.5'}), isNull);
      expect(UsdtInvoice.fromJson({'address': 'T...'}), isNull);
      expect(UsdtInvoice.fromJson({'address': '', 'amount': '3.5'}), isNull);
    });
  });
}
