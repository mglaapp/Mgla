import 'package:fl_clash/common/request.dart';
import 'package:intl/intl.dart';
import 'package:test/test.dart';

/// Валюта цен в запросах к серверу (решение владельца 14-10): приложение на русском просит рубли,
/// на любом другом языке — доллары. Язык берётся из Intl.defaultLocale, который ставит загрузка
/// перевода, — значит, смена языка в настройках меняет и валюту.
void main() {
  tearDown(() => Intl.defaultLocale = null);

  test('русский — рубли', () {
    Intl.defaultLocale = 'ru';
    expect(Request.currency(), 'rub');
  });

  test('русский с регионом — тоже рубли', () {
    Intl.defaultLocale = 'ru_RU';
    expect(Request.currency(), 'rub');
  });

  test('КОНТРОЛЬ: английский, японский, китайский — доллары', () {
    for (final locale in ['en', 'ja', 'zh_CN']) {
      Intl.defaultLocale = locale;
      expect(Request.currency(), 'usd', reason: locale);
    }
  });
}
