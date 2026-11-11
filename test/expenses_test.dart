// Expense totals by category and by how they were paid.
import 'package:an_agency/expenses/expenses_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('totals by category (biggest first) and by method', () {
    final d = DateTime(2026, 11, 5);
    final s = ExpenseSummary.of([
      Expense(date: d, category: 'Fuel', amount: 3000),
      Expense(date: d, category: 'Rent', amount: 40000, method: 'Bank'),
      Expense(date: d, category: 'Fuel', amount: 2500),
    ]);
    expect(s.total, 45500);
    expect(s.count, 3);
    expect(s.byCategory.first.key, 'Rent');
    expect(s.byCategory.last, isA<MapEntry<String, double>>().having((e) => e.value, 'fuel', 5500));
    expect(s.byMethod, {'Cash': 5500, 'Bank': 40000});
  });

  test('a blank category is saved as Other, dated at midday', () {
    final m = Expense(date: DateTime(2026, 11, 5, 23, 59), category: '  ', amount: 10).toMap();
    expect(m['category'], 'Other');
    expect((m['date'] as dynamic).toDate(), DateTime(2026, 11, 5, 12));
  });

  test('month helpers', () {
    expect(monthStart(DateTime(2026, 11, 20)), DateTime(2026, 11));
    expect(nextMonth(DateTime(2026, 12, 3)), DateTime(2027, 1));
  });
}
