// Trade schemes: buy X get Y free, by date and kind of shop.
import 'package:an_agency/inventory/schemes.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('free goods for every full lot', () {
    const s = TradeScheme(buy: 12, free: 1);
    expect(s.freeFor(11), 0);
    expect(s.freeFor(12), 1);
    expect(s.freeFor(30), 2);
    expect(s.freeFor(0), 0);
    expect(s.label, '12 + 1');
    expect(const TradeScheme(buy: 10, free: 2).freeFor(25), 4);
  });

  test('runs between its dates, both days included', () {
    final s = TradeScheme(buy: 6, free: 1, from: DateTime(2026, 11, 1), to: DateTime(2026, 11, 30));
    expect(s.appliesTo('b2r', DateTime(2026, 10, 31, 23)), isFalse);
    expect(s.appliesTo('b2r', DateTime(2026, 11, 1, 9)), isTrue);
    expect(s.appliesTo('b2r', DateTime(2026, 11, 30, 20)), isTrue);
    expect(s.appliesTo('b2r', DateTime(2026, 12, 1)), isFalse);
    expect(s.isCurrent(DateTime(2026, 12, 1)), isFalse);
  });

  test('only for the kinds of shop chosen; none chosen means all', () {
    const some = TradeScheme(buy: 6, free: 1, tiers: {'b2b'});
    expect(some.appliesTo('b2b', DateTime(2026, 11, 5)), isTrue);
    expect(some.appliesTo('b2r', DateTime(2026, 11, 5)), isFalse);
    expect(const TradeScheme(buy: 6, free: 1).appliesTo('b2c', DateTime(2026, 11, 5)), isTrue);
  });

  test('read from and saved on the product', () {
    expect(TradeScheme.of({'schemeBuy': 12, 'schemeFree': 0}), isNull);
    expect(TradeScheme.of(null), isNull);
    final s = TradeScheme.of({
      'schemeBuy': '12',
      'schemeFree': 1,
      'schemeTo': Timestamp.fromDate(DateTime(2026, 12, 31)),
      'schemeTiers': ['b2r'],
    })!;
    expect(s.buy, 12);
    expect(s.to, DateTime(2026, 12, 31));
    expect(s.tiers, {'b2r'});
    final f = TradeScheme.fields(s);
    expect(f['schemeBuy'], 12);
    expect(f['schemeFrom'], isNull);
    expect(TradeScheme.fields(null)['schemeBuy'], 0);
  });
}
