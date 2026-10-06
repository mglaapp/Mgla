/// «Российские сайты напрямую» (решение владельца 06-10-2026): российские домены и адреса идут
/// через обычный интернет человека, всё остальное — через узел.
///
/// ЗАЧЕМ. С апреля 2026 банки, Госуслуги и маркетплейсы не пускают с зарубежного адреса: с
/// включённым VPN человек выключает его, чтобы заплатить, и забывает включить обратно. Правило
/// закрывает проверку ПО АДРЕСУ; проверку по самому устройству (VPN-подключение в системе) оно
/// не закрывает — об этом честно говорит подпись переключателя.
///
/// ПОЧЕМУ ЭТИ ПРАВИЛА:
///  · GEOSITE,category-ru — список российских сервисов, включая их домены вне .ru (yandex.com,
///    vk.com, ok.ru и т.п.). Тег есть во встроенном assets/data/GEOSITE.dat (проверено 06-10),
///    поэтому базы НЕ качаются с GitHub при первом включении — из РФ он открывается не всегда;
///  · зоны .ru, .рф (xn--p1ai), .su — то, чего в списке нет, но что заведомо российское;
///  · GEOIP,RU,no-resolve — соединения прямо по адресу (банковские приложения ходят и так).
///    no-resolve обязателен: без него ядро для КАЖДОГО домена, не попавшего в списки выше,
///    делало бы DNS-запрос, чтобы узнать страну, — лишняя задержка и запросы к DNS мимо туннеля.
///
/// КУДА ВСТАЁТ: перед первым MATCH. Правила профиля и добавленные человеком стоят выше и
/// продолжают работать: если он сам отправил какой-то российский сайт через узел, переключатель
/// этого не отменяет. Нет MATCH — правила дописываются в конец.
const List<String> ruDirectRules = [
  'GEOSITE,category-ru,DIRECT',
  'DOMAIN-SUFFIX,ru,DIRECT',
  'DOMAIN-SUFFIX,xn--p1ai,DIRECT',
  'DOMAIN-SUFFIX,su,DIRECT',
  'GEOIP,RU,DIRECT,no-resolve',
];

/// Правила [ruDirectRules] перед первым MATCH. Повторный вызов ничего не дублирует.
List<String> withRuDirectRules(List<String> rules) {
  final present = rules.map(_normalize).toSet();
  final missing = ruDirectRules
      .where((rule) => !present.contains(_normalize(rule)))
      .toList();
  if (missing.isEmpty) return rules;
  final matchAt = rules.indexWhere(
    (rule) => _normalize(rule).startsWith('MATCH,'),
  );
  if (matchAt < 0) return [...rules, ...missing];
  return [...rules.sublist(0, matchAt), ...missing, ...rules.sublist(matchAt)];
}

String _normalize(String rule) =>
    rule.split(',').map((part) => part.trim()).join(',').toUpperCase();
