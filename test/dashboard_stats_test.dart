// The admin dashboard's figures, from a small made-up day of business.
import 'package:an_agency/Admin/dashboard_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 11, 10, 15, 0);
  DateTime day(int d, [int m = 11]) => DateTime(2026, m, d);

  final invoices = [
    DashInvoice(id: 'a', date: day(10), amount: 1000, customer: 'Shop A', userId: 'b1', area: 'pechs', items: [
      {'Product Name': 'Tea', 'QTY': '10', 'TP': '100'},
    ]),
    DashInvoice(id: 'b', date: day(10), amount: 500, customer: 'Shop B', userId: 'b2', area: 'gulshan', items: [
      {'Product Name': 'Soap', 'QTY': '5', 'TP': '100'},
    ]),
    DashInvoice(id: 'c', date: day(9), amount: 750, customer: 'Shop A', userId: 'b1', area: 'pechs'),
    DashInvoice(id: 'd', date: day(1), amount: 2000, customer: 'Shop C', userId: 'b1'), // this month, paid
    DashInvoice(id: 'e', date: day(1, 10), amount: 900, customer: 'Shop D', userId: 'b2'), // 40 days old, unpaid
    DashInvoice(id: 'f', date: day(5, 10), amount: 300, customer: 'Shop C', userId: 'b1'), // last month, same span
  ];
  final entries = [
    DashEntry(date: day(10), amount: 400, customer: 'Shop A', userId: 'b1'),
    DashEntry(date: day(3), amount: 2300, customer: 'Shop C', userId: 'b1'),
  ];

  final s = DashboardStats.compute(
    now: now,
    invoices: invoices,
    entries: entries,
    bookerNames: {'b1': 'Ali', 'b2': 'Sara', 'b3': 'Idle'},
    customers: 4,
    pendingOrders: 2,
    pendingOrdersValue: 1200,
  );

  test('today and yesterday', () {
    expect(s.todaySales, 1500);
    expect(s.todayInvoices, 2);
    expect(s.yesterdaySales, 750);
    expect(s.todayRecovered, 400);
  });

  test('month to date vs the same days of last month', () {
    expect(s.monthSales, 1000 + 500 + 750 + 2000);
    expect(s.lastMonthSales, 300 + 900);
    expect(s.monthRecovered, 2700);
  });

  test('what shops owe, invoices paid oldest first', () {
    // Shop A: 750 + 1000 - 400; Shop B: 500; Shop C: 300 + 2000 - 2300 = 0; Shop D: 900
    expect(s.outstanding, 1350 + 500 + 900);
    expect(s.shopsOwing, 3);
    expect(s.openInvoices, 4); // A's two, B, D
    expect(s.overdueInvoices, 1);
    expect(s.overdueAmount, 900);
    expect(s.topDues.first.customer, 'Shop A');
    expect(s.topDues.first.oldestOpenDays, 1);
  });

  test('bookers: who booked today, best first; idle ones listed too', () {
    expect(s.activeBookersToday, 2);
    expect(s.bookers.map((b) => b.name).toList(), ['Ali', 'Sara', 'Idle']);
    expect(s.bookers.first.recovered, 400);
    expect(s.bookers.first.outstanding, 1350);
  });

  test('30-day chart ends today', () {
    expect(s.dailySales.length, 30);
    expect(s.dailySales.last, 1500);
    expect(s.dailyRecovered.last, 400);
  });

  test('products and areas this month', () {
    expect(s.topProducts.first.key, 'Tea');
    expect(s.areaSales.first.key, 'No area'); // the 2000 invoice had no area
    expect(s.monthRecoveryRate, closeTo(2700 / 4250, 1e-9));
  });
}
