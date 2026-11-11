// Company-wide receivables: each unpaid rupee is aged by the invoice it belongs to.
import 'package:an_agency/khata.dart';
import 'package:an_agency/receivables/receivables_data.dart';
import 'package:flutter_test/flutter_test.dart';

ShopKhata _shop(String name, List<KhataLine> lines) {
  var bal = 0.0;
  for (final l in lines) {
    bal += l.signed;
    l.balanceAfter = bal;
  }
  settleOldestFirst(lines);
  return ShopKhata(name, lines);
}

KhataLine _inv(DateTime d, double a, {String area = 'Saddar'}) =>
    KhataLine(id: 'i$a', kind: KhataKind.invoice, date: d, createdAt: d, amount: a, title: 'Invoice', note: area);
KhataLine _pay(DateTime d, double a) =>
    KhataLine(id: 'p$a', kind: KhataKind.payment, date: d, createdAt: d, amount: a, title: 'pay');

void main() {
  final today = DateTime(2026, 11, 30);

  test('buckets by age, oldest paid first', () {
    // 100 days old 1000, 45 days old 2000, 5 days old 500; 1200 paid → the oldest 1000 and 200 of the next.
    final shop = _shop('A', [
      _inv(DateTime(2026, 8, 22), 1000),
      _inv(DateTime(2026, 10, 16), 2000),
      _pay(DateTime(2026, 11, 1), 1200),
      _inv(DateTime(2026, 11, 25), 500),
    ]);
    final rows = receivablesFrom({'u1': KhataBook([shop])}, {'u1': 'Ali'}, today);
    expect(rows, hasLength(1));
    final r = rows.single;
    expect(r.ageing.over90, 0);
    expect(r.ageing.d31to60, 1800);
    expect(r.ageing.d0to30, 500);
    expect(r.total, 2300);
    expect(r.oldestDays, 45);
    expect(r.openInvoices, 2);
    expect(r.bookerName, 'Ali');
    expect(r.area, 'Saddar');
    expect(r.lastPayment, DateTime(2026, 11, 1));
  });

  test('shops that owe nothing or are in advance are left out', () {
    final paid = _shop('Paid', [_inv(DateTime(2026, 11, 1), 1000), _pay(DateTime(2026, 11, 2), 1000)]);
    final advance = _shop('Advance', [_inv(DateTime(2026, 11, 1), 1000), _pay(DateTime(2026, 11, 2), 1500)]);
    expect(receivablesFrom({'u1': KhataBook([paid, advance])}, const {}, today), isEmpty);
  });

  test('groups by booker and area, and the office area wins over the invoice', () {
    final books = {
      'u1': KhataBook([_shop('A', [_inv(DateTime(2026, 7, 1), 300)])]),
      'u2': KhataBook([_shop('B', [_inv(DateTime(2026, 11, 20), 700)])]),
    };
    final rows = receivablesFrom(books, {'u1': 'Ali', 'u2': 'Babar'}, today,
        shopInfo: {'A': ('Clifton', 250)});
    expect(rows.first.shop, 'B');
    final a = rows.firstWhere((r) => r.shop == 'A');
    expect(a.area, 'Clifton');
    expect(a.overLimit, isTrue);
    expect(a.ageing.over90, 300);

    final byBooker = groupReceivables(rows, (r) => r.bookerName);
    expect(byBooker.map((g) => g.name), ['Babar', 'Ali']);
    final t = totalAgeing(rows);
    expect(t.total, 1000);
    expect(t.overdue, 300);
  });
}
