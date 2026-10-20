import 'dart:async';

import 'package:fl_clash/common/link.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late StreamController<Uri> links;
  late List<String> received;
  late List<String> tvCodes;

  setUp(() {
    links = StreamController<Uri>.broadcast();
    received = [];
    tvCodes = [];
    linkManager.uriLinkStream = () => links.stream;
  });

  tearDown(() async {
    linkManager.destroy();
    await links.close();
  });

  Future<void> listen() async {
    await linkManager.initAppLinksListen(received.add, onTvCode: tvCodes.add);
  }

  Future<void> emit(String uri) async {
    links.add(Uri.parse(uri));
    await Future<void>.delayed(Duration.zero);
  }

  test('LinkManager is a singleton', () {
    expect(LinkManager(), same(linkManager));
  });

  test('an install-config link reports its url', () async {
    await listen();

    await emit('flclash://install-config?url=https://example.com/a.yaml');

    expect(received, ['https://example.com/a.yaml']);
  });

  test('an install-config link without a url is ignored', () async {
    await listen();

    await emit('flclash://install-config');

    expect(received, isEmpty);
  });

  test(
    'an install-config link over plain http or with a password is ignored',
    () async {
      await listen();

      await emit('flclash://install-config?url=http://example.com/a.yaml');
      await emit(
        'mgla://install-config?url=https%3A%2F%2Fu%3Ap%40example.com%2Fa.yaml',
      );

      expect(received, isEmpty);
    },
  );

  test('a link for another host is ignored', () async {
    await listen();

    await emit('flclash://open-profile?url=https://example.com/a.yaml');

    expect(received, isEmpty);
  });

  test('a tv link hands its code over and installs nothing', () async {
    await listen();

    await emit('mgla://tv?c=ABC234');

    expect(tvCodes, ['ABC234']);
    expect(received, isEmpty);
  });

  test(
    'a tv link of an upstream scheme or without a code is ignored',
    () async {
      await listen();

      await emit('flclash://tv?c=ABC234');
      await emit('mgla://tv');

      expect(tvCodes, isEmpty);
    },
  );

  test('listening again replaces the previous subscription', () async {
    await listen();
    final first = linkManager.subscription;

    await listen();

    expect(linkManager.subscription, isNot(same(first)));

    await emit('flclash://install-config?url=https://example.com/a.yaml');

    expect(received, ['https://example.com/a.yaml']);
  });

  test(
    'a seeded launch argument is delivered once a listener attaches',
    () async {
      linkManager.seedInitialLink([
        '--verbose',
        'flclash://install-config?url=https://example.com/a.yaml',
      ]);

      expect(received, isEmpty);

      await listen();

      expect(received, ['https://example.com/a.yaml']);

      await listen();

      expect(received, ['https://example.com/a.yaml']);
    },
  );

  test('launch arguments without a known scheme are ignored', () async {
    linkManager.seedInitialLink(['https://example.com/a.yaml', 'not a uri']);

    await listen();

    expect(received, isEmpty);
  });

  test('destroy stops delivery and is safe to repeat', () async {
    await listen();

    linkManager.destroy();
    linkManager.destroy();
    await emit('flclash://install-config?url=https://example.com/a.yaml');

    expect(linkManager.subscription, isNull);
    expect(received, isEmpty);
  });
}
