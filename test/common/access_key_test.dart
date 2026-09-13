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
}
