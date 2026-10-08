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
    return [for (final item in json) ?Plan.fromJson(item)];
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
  final bool usdtEnabled;

  /// Карта. Страница оплаты принадлежит платёжной системе и открывается у неё — в приложении
  /// помещается только кнопка. Показывается, лишь когда сервер подтвердил, что платёжка
  /// настроена: кнопка, ведущая в никуда, стоит дороже отсутствующей.
  final bool cardEnabled;

  /// Монеты напрямую (сервер с 05-10): весь счёт помещается в приложение, как USDT.
  final bool coinsEnabled;

  /// Скины из Steam через OmniSkin (сервер с 06-10): как карта — страница оплаты чужая
  /// (там вход через Steam и обмен с ботом), приложение её только открывает.
  final bool skinsEnabled;

  /// Каталог монет: монета -> сети. Пусто у старого сервера — тогда остаётся путь USDT.
  final List<CoinGroup> coins;

  final TrialOffer? trial;

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
    required this.cardEnabled,
    this.coinsEnabled = false,
    this.coins = const [],
    this.skinsEnabled = false,
    this.trial,
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
      cardEnabled: methods is Map && methods['card'] == true,
      coinsEnabled: methods is Map && methods['coins'] == true,
      skinsEnabled: methods is Map && methods['skins'] == true,
      coins: CoinGroup.listFrom(json['coins_catalog']),
      trial: TrialOffer.fromJson(json['trial_offer']),
    );
  }
}

/// Пробный, который сервер продаёт ЭТОМУ аккаунту: без телеграма — только после привязки.
@immutable
class TrialOffer {
  final String price;
  final int days;
  final String? promo;
  final bool needTelegram;

  const TrialOffer({
    required this.price,
    required this.days,
    this.promo,
    this.needTelegram = false,
  });

  static TrialOffer? fromJson(Object? json) {
    if (json is! Map) return null;
    final price = switch (json['rub']) {
      final String text when text.isNotEmpty => text,
      final num value when value > 0 =>
        value == value.roundToDouble() ? '${value.round()}' : '$value',
      _ => null,
    };
    final days = json['days'];
    if (price == null || days is! int || days <= 0) return null;
    final promo = json['promo'];
    return TrialOffer(
      price: price,
      days: days,
      promo: promo is String && promo.isNotEmpty ? promo : null,
      needTelegram: json['need_tg'] == true,
    );
  }
}

/// Сервер из GET /api/v1/servers; [available] = false — «Загружен», выбрать нельзя (08-10).
@immutable
class ServerInfo {
  final String id;
  final String cc;
  final Map<String, String> names;
  final bool available;

  const ServerInfo({
    required this.id,
    required this.cc,
    required this.names,
    required this.available,
  });

  String nameFor(String languageCode) =>
      names[languageCode] ?? names['en'] ?? cc.toUpperCase();

  static List<ServerInfo> listFrom(Object? json) {
    if (json is! List) return const [];
    final out = <ServerInfo>[];
    for (final item in json) {
      if (item is! Map) continue;
      final id = item['id'];
      final cc = item['cc'];
      if (id is! String || id.isEmpty || cc is! String || cc.length != 2) {
        continue;
      }
      final names = <String, String>{};
      final raw = item['name'];
      if (raw is Map) {
        for (final entry in raw.entries) {
          final value = entry.value;
          if (entry.key is String && value is String && value.isNotEmpty) {
            names[entry.key as String] = value;
          }
        }
      }
      out.add(
        ServerInfo(
          id: id,
          cc: cc.toLowerCase(),
          names: names,
          available: item['status'] == 'ok',
        ),
      );
    }
    return out;
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
      network: json['network'] is String
          ? json['network'] as String
          : 'TRON (TRC-20)',
      qrPayload: json['qr_payload'] is String
          ? json['qr_payload'] as String
          : '',
      qrSvg: json['qr_svg'] is String ? json['qr_svg'] as String : '',
      minutesLeft: json['minutes_left'] is int
          ? json['minutes_left'] as int
          : 0,
    );
  }
}

/// Сеть одной монеты: код счёта на сервере («usdt_trc20») и подпись («TRON (TRC-20)»).
@immutable
class CoinNet {
  final String code;
  final String network;

  /// Имя картинки СЕТИ из assets/coins. Картинки лежат в приложении: тянуть их с сервера там,
  /// где сеть режут, значит показать пустые квадраты.
  final String icon;

  /// BNB: бесплатного списка входящих переводов нет — человек вставляет хеш транзакции сам.
  final bool byHash;

  const CoinNet({
    required this.code,
    required this.network,
    required this.icon,
    required this.byHash,
  });

  static CoinNet? fromJson(Object? json) {
    if (json is! Map) return null;
    final code = json['code'];
    if (code is! String || code.isEmpty) return null;
    final net = json['net'];
    final icon = json['icon'];
    return CoinNet(
      code: code,
      network: net is String && net.isNotEmpty ? net : code,
      icon: icon is String ? icon : '',
      byHash: json['by_hash'] == true,
    );
  }
}

/// Монета в каталоге: одна строка, сети внутри (USDT в шести сетях — это «USDT», а не шесть
/// кнопок). Порядок и названия задаёт сервер — те же, что на сайте.
@immutable
class CoinGroup {
  final String sym;
  final String name;
  final String icon;

  /// Популярные показываются сразу, остальные — под «Ещё».
  final bool popular;
  final List<CoinNet> nets;

  const CoinGroup({
    required this.sym,
    required this.name,
    required this.icon,
    required this.popular,
    required this.nets,
  });

  static CoinGroup? fromJson(Object? json) {
    if (json is! Map) return null;
    final sym = json['sym'];
    if (sym is! String || sym.isEmpty) return null;
    final raw = json['nets'];
    final nets = raw is List
        ? [for (final item in raw) ?CoinNet.fromJson(item)]
        : <CoinNet>[];
    // Монета без единой сети — это кнопка, ведущая в никуда.
    if (nets.isEmpty) return null;
    final name = json['name'];
    final icon = json['icon'];
    return CoinGroup(
      sym: sym,
      name: name is String && name.isNotEmpty ? name : sym,
      icon: icon is String ? icon : '',
      popular: json['popular'] == true,
      nets: nets,
    );
  }

  static List<CoinGroup> listFrom(Object? json) {
    if (json is! List) return const [];
    return [for (final item in json) ?CoinGroup.fromJson(item)];
  }
}

/// Счёт на оплату монетой: то же, что страница счёта на сайте.
@immutable
class CryptoInvoice {
  final int id;
  final String coin;
  final String sym;
  final String network;
  final String coinIcon;
  final String netIcon;
  final String address;

  /// Сумма СТРОКОЙ и уже подрезанная: по ней идёт сверка с блокчейном до последнего знака.
  final String amount;
  final bool byHash;
  final bool paid;
  final String qrSvg;
  final int minutesLeft;

  const CryptoInvoice({
    required this.id,
    required this.coin,
    required this.sym,
    required this.network,
    required this.coinIcon,
    required this.netIcon,
    required this.address,
    required this.amount,
    required this.byHash,
    required this.paid,
    required this.qrSvg,
    required this.minutesLeft,
  });

  static CryptoInvoice? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final address = json['address'];
    final amount = json['amount'];
    final coin = json['coin'];
    if (id is! int ||
        coin is! String ||
        address is! String ||
        address.isEmpty ||
        amount is! String ||
        amount.isEmpty) {
      return null;
    }
    String text(String field) =>
        json[field] is String ? json[field] as String : '';
    return CryptoInvoice(
      id: id,
      coin: coin,
      sym: text('sym').isEmpty ? coin.toUpperCase() : text('sym'),
      network: text('network'),
      coinIcon: text('coin_icon'),
      netIcon: text('net_icon'),
      address: address,
      amount: amount,
      byHash: json['by_hash'] == true,
      paid: json['status'] == 'paid',
      qrSvg: text('qr_svg'),
      minutesLeft: json['minutes_left'] is int
          ? json['minutes_left'] as int
          : 0,
    );
  }
}

/// Ответ «я оплатил» по монете: зачтён ли СЧЁТ и что теперь с доступом.
@immutable
class CryptoCheck {
  final bool paid;
  final AccountStatus? status;

  /// Почему хеш не зачтён (BNB): код, а не текст — языков в приложении четыре.
  final String? reason;

  const CryptoCheck({required this.paid, required this.status, this.reason});

  static CryptoCheck? fromJson(Object? json) {
    if (json is! Map) return null;
    final reason = json['reason'];
    return CryptoCheck(
      paid: json['paid'] == true,
      status: AccountStatus.fromJson(json),
      reason: reason is String && reason.isNotEmpty ? reason : null,
    );
  }
}
