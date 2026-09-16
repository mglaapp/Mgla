import 'package:flutter/foundation.dart';

/// Ответы нашего API (`mgla.app/api/v1`): подписка, тарифы, счёт на оплату.
///
/// Без freezed намеренно. Кодогенерация на четырёх простых классах не экономит ничего, а диф
/// против живого апстрима держим узким — это главное правило форка.
///
/// Разбор везде ЗАЩИТНЫЙ: `null` вместо исключения. Ответ приходит по сети, и приложение,
/// падающее на неожиданном поле, ломается в единственный момент, когда человек платит деньги.
@immutable
class Plan {
  final String code;
  final int days;
  final double usd;
  final String title;

  const Plan({
    required this.code,
    required this.days,
    required this.usd,
    required this.title,
  });

  static Plan? fromJson(Object? json) {
    if (json is! Map) return null;
    final code = json['code'];
    final days = json['days'];
    if (code is! String || days is! int) return null;
    return Plan(
      code: code,
      days: days,
      usd: (json['usd'] as num?)?.toDouble() ?? 0,
      title: json['title'] is String ? json['title'] as String : code,
    );
  }

  static List<Plan> listFrom(Object? json) {
    if (json is! List) return const [];
    return [
      for (final item in json) ?Plan.fromJson(item),
    ];
  }
}

/// Состояние доступа: ровно то, что человек и так видит в подписке.
@immutable
class AccountStatus {
  final String key;
  final bool active;
  final bool blocked;
  final DateTime? expiresAt;
  final int? daysLeft;
  final double? usedGb;
  final double? quotaGb;
  final List<Plan> plans;

  /// Способ, который целиком помещается в приложение: платим напрямую, посредника нет.
  /// Карта и крипто-шлюз всегда уводят на страницу платёжной системы, поэтому здесь их нет.
  final bool usdtEnabled;

  const AccountStatus({
    required this.key,
    required this.active,
    required this.blocked,
    required this.expiresAt,
    required this.daysLeft,
    required this.usedGb,
    required this.quotaGb,
    required this.plans,
    required this.usdtEnabled,
  });

  static AccountStatus? fromJson(Object? json) {
    if (json is! Map) return null;
    final key = json['key'];
    if (key is! String || key.isEmpty) return null;
    final methods = json['methods'];
    final expire = json['expires_at'];
    return AccountStatus(
      key: key,
      active: json['active'] == true,
      blocked: json['blocked'] == true,
      expiresAt: expire is String ? DateTime.tryParse(expire) : null,
      daysLeft: json['days_left'] is int ? json['days_left'] as int : null,
      usedGb: (json['used_gb'] as num?)?.toDouble(),
      quotaGb: (json['quota_gb'] as num?)?.toDouble(),
      plans: Plan.listFrom(json['plans']),
      usdtEnabled: methods is Map && methods['usdt'] == true,
    );
  }
}

/// Только что заведённый аккаунт.
@immutable
class NewAccount {
  final String key;
  final String subUrl;

  /// Ссылка входа на сайт. Приходит ОДИН раз, при создании, и нигде не сохраняется: она равна
  /// паролю. Показать её человеку обязаны сразу — иначе он не узнает о ней никогда, а без неё
  /// на сайт с другого устройства уже не войти.
  final String loginUrl;

  const NewAccount({
    required this.key,
    required this.subUrl,
    required this.loginUrl,
  });

  static NewAccount? fromJson(Object? json) {
    if (json is! Map) return null;
    final key = json['key'];
    final subUrl = json['sub_url'];
    if (key is! String || key.isEmpty || subUrl is! String) return null;
    return NewAccount(
      key: key,
      subUrl: subUrl,
      loginUrl: json['login_url'] is String ? json['login_url'] as String : '',
    );
  }
}

/// Счёт на оплату USDT.
@immutable
class UsdtInvoice {
  final String address;

  /// Сумма СТРОКОЙ и уже подрезанная: по ней идёт сверка с блокчейном. Округление на нашей
  /// стороне означало бы «перевёл не столько — доступ не включился».
  final String amount;
  final String network;
  final String qrPayload;

  /// Картинка QR, собранная СЕРВЕРОМ. Пусто — библиотеки на ноде нет; тогда экран показывает
  /// адрес и сумму, и это рабочий путь, а не поломка.
  final String qrSvg;
  final int minutesLeft;

  const UsdtInvoice({
    required this.address,
    required this.amount,
    required this.network,
    required this.qrPayload,
    required this.qrSvg,
    required this.minutesLeft,
  });

  static UsdtInvoice? fromJson(Object? json) {
    if (json is! Map) return null;
    final address = json['address'];
    final amount = json['amount'];
    if (address is! String || address.isEmpty || amount is! String) return null;
    return UsdtInvoice(
      address: address,
      amount: amount,
      network: json['network'] is String ? json['network'] as String : 'TRON (TRC-20)',
      qrPayload: json['qr_payload'] is String ? json['qr_payload'] as String : '',
      qrSvg: json['qr_svg'] is String ? json['qr_svg'] as String : '',
      minutesLeft: json['minutes_left'] is int ? json['minutes_left'] as int : 0,
    );
  }
}
