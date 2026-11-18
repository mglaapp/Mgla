import 'package:fl_clash/common/link_check.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/manager/link_manager.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

Proxy _p(String name) => Proxy(name: name, type: 'Vless');

Group _g(
  String name,
  GroupType type,
  List<String> all, {
  String? now,
  bool? hidden,
}) => Group(
  name: name,
  type: type,
  all: [for (final n in all) _p(n)],
  now: now,
  hidden: hidden,
);

/// The groups the core lists for the live subscription since 17-11.
List<Group> _bridged({
  String autoNow = 'Auto direct',
  String deNow = 'DE Reality',
}) => [
  _g('Mgla', GroupType.Selector, ['Auto', 'Mgla DE'], now: 'Mgla DE'),
  _g('Auto', GroupType.Fallback, [
    'Auto direct',
    'DE Reality via RU',
  ], now: autoNow),
  _g(
    'Auto direct',
    GroupType.URLTest,
    ['DE Reality'],
    now: 'DE Reality',
    hidden: true,
  ),
  _g('Mgla DE', GroupType.Fallback, [
    'DE Reality',
    'DE Reality via RU',
  ], now: deNow),
];

void main() {
  test('the check sees url-test and fallback groups, hidden ones too', () {
    final groups = linkGroups(_bridged());
    expect(groups.keys, unorderedEquals(['Auto', 'Auto direct', 'Mgla DE']));
    expect(groups['Auto']!.pick, LinkPick.fallback);
    expect(groups['Auto']!.members, ['Auto direct', 'DE Reality via RU']);
    expect(groups['Auto direct']!.pick, LinkPick.urlTest);
    expect(groups['Mgla DE']!.members, ['DE Reality', 'DE Reality via RU']);
  });

  test('the main selector is the select group that offers Auto', () {
    expect(linkMainGroup(_bridged())?.name, 'Mgla');
    expect(
      linkMainGroup([
        _g('Other', GroupType.Selector, ['X']),
      ]),
      isNull,
    );
  });

  test('«via Russia» is read from where the picks really end', () {
    const chose = {'Mgla': 'Mgla DE'};
    expect(linkGoesViaBridge(_bridged(), 'Mgla', chose), isFalse);
    expect(
      linkGoesViaBridge(_bridged(deNow: 'DE Reality via RU'), 'Mgla', chose),
      isTrue,
    );
    const auto = {'Mgla': 'Auto'};
    expect(linkGoesViaBridge(_bridged(), 'Mgla', auto), isFalse);
    expect(
      linkGoesViaBridge(_bridged(autoNow: 'DE Reality via RU'), 'Mgla', auto),
      isTrue,
    );
  });
}
