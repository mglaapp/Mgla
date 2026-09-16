import 'package:fl_clash/common/access_key.dart';
import 'package:fl_clash/common/constant.dart';
import 'package:test/test.dart';

void main() {
  test('a bare key becomes our subscription address', () {
    expect(
      subscriptionUrlOf('7f3c9a21b4e85d06'),
      '$subscriptionSite$subscriptionPath'
      '7f3c9a21b4e85d06',
    );
  });

  test('spaces around a pasted key do not break it', () {
    expect(
      subscriptionUrlOf('  7f3c9a21b4e85d06\n'),
      '$subscriptionSite$subscriptionPath'
      '7f3c9a21b4e85d06',
    );
  });

  test('a full subscription link is taken as it is', () {
    const url = 'https://171.22.30.253.sslip.io/sub/7f3c9a21b4e85d06';
    expect(subscriptionUrlOf(url), url);
  });

  test('an install deep link gives up the address inside it', () {
    expect(
      subscriptionUrlOf(
        'mgla://install-config?url=https%3A%2F%2Fmgla.app%2Fsub%2F7f3c9a21b4e85d06',
      ),
      'https://mgla.app/sub/7f3c9a21b4e85d06',
    );
  });

  test('deep links of the clients we came from still work', () {
    expect(
      subscriptionUrlOf(
        'clash://install-config?url=https%3A%2F%2Fmgla.app%2Fsub%2Fabc123abc123abc1',
      ),
      'https://mgla.app/sub/abc123abc123abc1',
    );
  });

  test('nothing usable returns null instead of a broken address', () {
    expect(subscriptionUrlOf(null), isNull);
    expect(subscriptionUrlOf(''), isNull);
    expect(subscriptionUrlOf('   '), isNull);
    expect(subscriptionUrlOf('мой ключ'), isNull);
    expect(
      subscriptionUrlOf('7f3c9a'),
      isNull,
      reason: 'too short to be a key',
    );
    expect(subscriptionUrlOf('mgla.app/sub/7f3c9a21b4e85d06'), isNull);
  });

  test('a link that is not http is refused, scheme and all', () {
    expect(subscriptionUrlOf('file:///etc/passwd'), isNull);
    expect(subscriptionUrlOf('javascript:alert(1)'), isNull);
    expect(
      subscriptionUrlOf('mgla://install-config?url=file%3A%2F%2F%2Fetc'),
      isNull,
    );
  });

  // ── accessKeyOf: обратная сторона, ею живёт экран подписки ──────────────────
  // Ключ нигде не хранится вторым местом: он вынимается из адреса профиля. Две копии одного
  // секрета расходятся молча, и расходятся ровно тогда, когда человек платит.

  test('the key comes back out of our own subscription address', () {
    expect(
      accessKeyOf(
        '$subscriptionSite$subscriptionPath'
        '7f3c9a21b4e85d06',
      ),
      '7f3c9a21b4e85d06',
    );
  });

  test('what subscriptionUrlOf built, accessKeyOf reads back', () {
    const key = '9ac0394dfc2f68b5846e7ac4';
    expect(accessKeyOf(subscriptionUrlOf(key)), key);
  });

  test('a foreign subscription address gives no key', () {
    // Про чужие ключи наш сервер ничего не знает, и спрашивать его о них значит отправлять
    // чужой секрет на наш сервер.
    expect(accessKeyOf('https://vpn.example/sub/7f3c9a21b4e85d06'), isNull);
    expect(
      accessKeyOf('https://171.22.30.253.sslip.io/sub/7f3c9a21b4e85d06'),
      isNull,
    );
  });

  test('our address with junk instead of a key gives no key', () {
    expect(accessKeyOf('$subscriptionSite$subscriptionPath'), isNull);
    expect(
      accessKeyOf(
        '$subscriptionSite$subscriptionPath'
        '7f3c9a',
      ),
      isNull,
    );
    expect(
      accessKeyOf(
        '$subscriptionSite$subscriptionPath'
        'ключ-по-русски',
      ),
      isNull,
    );
  });

  test('nothing at all gives no key', () {
    expect(accessKeyOf(null), isNull);
    expect(accessKeyOf(''), isNull);
    expect(accessKeyOf('   '), isNull);
  });

  test('spaces around a stored address do not hide the key', () {
    expect(
      accessKeyOf(
        '  $subscriptionSite$subscriptionPath'
        '7f3c9a21b4e85d06\n',
      ),
      '7f3c9a21b4e85d06',
    );
  });
}
