// A shop's credit limit and credit days stop a new invoice.
import 'package:an_agency/credit_limits.dart';
import 'package:an_agency/khata.dart';
import 'package:flutter_test/flutter_test.dart';

ShopKhata _shop(List<KhataLine> lines) {
  var bal = 0.0;
  for (final l in lines) {
    bal += l.signed;
    l.balanceAfter = bal;
  }
  settleOldestFirst(lines);
  return ShopKhata('Shop A', lines);
}

KhataLine _inv(DateTime d, double a) =>
    KhataLine(id: 'i', kind: KhataKind.invoice, date: d, createdAt: d, amount: a, title: 'Invoice #7');
KhataLine _pay(DateTime d, double a) =>
    KhataLine(id: 'p', kind: KhataKind.payment, date: d, createdAt: d, amount: a, title: 'pay');

void main() {
  final today = DateTime(2026, 11, 20);

  test('no terms: always fine', () {
    expect(creditProblem(const CreditTerms(), _shop([_inv(DateTime(2026, 1, 1), 99999)]), 5000, today), isNull);
  });

  test('within the limit is fine, over it is stopped', () {
    final shop = _shop([_inv(DateTime(2026, 11, 18), 8000)]);
    const terms = CreditTerms(limit: 10000);
    expect(creditProblem(terms, shop, 2000, today), isNull);
    final why = creditProblem(terms, shop, 2500, today);
    expect(why, contains('owes Rs 8,000'));
    expect(why, contains('Only Rs 2,000 more'));
  });

  test('a new shop with no history uses the whole limit', () {
    expect(creditProblem(const CreditTerms(limit: 5000), null, 5000, today), isNull);
    expect(creditProblem(const CreditTerms(limit: 5000), null, 6000, today), isNotNull);
  });

  test('an invoice unpaid past the credit days stops new ones', () {
    const terms = CreditTerms(days: 15);
    expect(creditProblem(terms, _shop([_inv(DateTime(2026, 11, 10), 1000)]), 500, today), isNull);
    final why = creditProblem(terms, _shop([_inv(DateTime(2026, 11, 1), 1000)]), 500, today);
    expect(why, contains('unpaid for 19 days'));
  });

  test('a paid old invoice does not count', () {
    final shop = _shop([_inv(DateTime(2026, 10, 1), 1000), _pay(DateTime(2026, 10, 5), 1000)]);
    expect(creditProblem(const CreditTerms(days: 15), shop, 500, today), isNull);
  });
}
