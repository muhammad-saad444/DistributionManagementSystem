// Invoices close when payments cover them, oldest first.
import 'package:an_agency/khata.dart';
import 'package:flutter_test/flutter_test.dart';

KhataLine _inv(String id, int day, double amount) => KhataLine(
    id: id, kind: KhataKind.invoice, date: DateTime(2026, 11, day), createdAt: DateTime(2026, 11, day), amount: amount, title: id);
KhataLine _pay(int day, double amount) => KhataLine(
    id: 'p$day', kind: KhataKind.payment, date: DateTime(2026, 11, day), createdAt: DateTime(2026, 11, day), amount: amount, title: 'pay');

void main() {
  test('payment closes the oldest invoice first, the rest partly paid', () {
    final a = _inv('a', 1, 1000), b = _inv('b', 2, 500);
    settleOldestFirst([a, b, _pay(3, 1200)]);
    expect(a.isClosed, true);
    expect(a.closedOn, DateTime(2026, 11, 3));
    expect(b.isClosed, false);
    expect(b.isPartlyPaid, true);
    expect(b.due, 300);
  });

  test('no payment: open with the full amount due', () {
    final a = _inv('a', 1, 800);
    settleOldestFirst([a]);
    expect(a.isClosed, false);
    expect(a.isPartlyPaid, false);
    expect(a.due, 800);
  });

  test('several payments add up to close it', () {
    final a = _inv('a', 1, 1000);
    settleOldestFirst([a, _pay(2, 400), _pay(5, 600)]);
    expect(a.isClosed, true);
    expect(a.closedOn, DateTime(2026, 11, 5));
  });

  test('advance paid before the invoice closes it on its own date', () {
    final a = _inv('a', 4, 300), b = _inv('b', 6, 300);
    settleOldestFirst([_pay(1, 500), a, b]);
    expect(a.isClosed, true);
    expect(a.closedOn, DateTime(2026, 11, 4));
    expect(b.due, 100);
  });

  test('a few paisa short still counts as closed', () {
    final a = _inv('a', 1, 999.6);
    settleOldestFirst([a, _pay(2, 999.2)]);
    expect(a.isClosed, true);
  });

  test('payment lines carry no status', () {
    final p = _pay(1, 100);
    settleOldestFirst([p]);
    expect(p.isDebt, false);
    expect(p.isClosed, false);
  });
}
