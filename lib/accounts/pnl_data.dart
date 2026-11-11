// Profit & loss: sales, less the cost of the goods sold (each product's latest purchase cost, the
// same figures as Purchases → Profit), gives gross profit; less expenses gives net profit.
import 'package:cloud_firestore/cloud_firestore.dart';

import '../account/account.dart';
import '../expenses/expenses_data.dart';
import '../inventory/inventory_data.dart';

class ProfitAndLoss {
  final DateTime start; // first day
  final DateTime end; // the day after the last
  final double sales; // net of returns and invoice discounts
  final double cost; // cost of the goods sold
  final ExpenseSummary expenses;
  final int invoices;
  final int productsWithoutCost; // sold but never purchased here, so their cost counts as 0

  const ProfitAndLoss({
    required this.start,
    required this.end,
    required this.sales,
    required this.cost,
    required this.expenses,
    this.invoices = 0,
    this.productsWithoutCost = 0,
  });

  double get gross => sales - cost;
  double get net => gross - expenses.total;

  /// [v] as a percentage of sales (null when there were no sales).
  double? marginOf(double v) => sales > 0.5 ? v / sales * 100 : null;
}

ProfitAndLoss pnlFrom(ProfitReport r, Iterable<Expense> expenses, DateTime start, DateTime end) => ProfitAndLoss(
      start: start,
      end: end,
      sales: r.sales.toDouble(),
      cost: r.cost.toDouble(),
      expenses: ExpenseSummary.of(expenses.where((e) => !e.date.isBefore(start) && e.date.isBefore(end))),
      invoices: r.invoices,
      productsWithoutCost: r.productsWithoutCost,
    );

/// The chosen period, and the last six months one by one.
class PnlData {
  final ProfitAndLoss period;
  final List<ProfitAndLoss> months; // oldest first
  const PnlData(this.period, this.months);
}

DateTime? _salesDay(Map<String, dynamic> m) {
  final ts = m['salesDateTs'];
  return ts is Timestamp ? ts.toDate() : null;
}

/// Profit & loss for [start] up to (not including) [end], plus the last six months, from one read.
Future<PnlData> loadPnl(DateTime start, DateTime end, {DateTime? now}) async {
  final today = now ?? DateTime.now();
  final firstMonth = DateTime(today.year, today.month - 5);
  final afterThisMonth = DateTime(today.year, today.month + 1);
  final from = start.isBefore(firstMonth) ? start : firstMonth;
  final to = end.isAfter(afterThisMonth) ? end : afterThisMonth;

  final results = await Future.wait<Object>([
    loadProductIndex(fresh: true),
    companyCol('invoices')
        .where('salesDateTs', isGreaterThanOrEqualTo: Timestamp.fromDate(from))
        .where('salesDateTs', isLessThan: Timestamp.fromDate(to))
        .get(),
    loadPayables(),
    loadExpenses(from, to),
  ]);
  final products = results[0] as ProductIndex;
  final invoices = (results[1] as QuerySnapshot<Map<String, dynamic>>).docs.map((d) => d.data()).toList();
  final payables = results[2] as PayablesBook;
  final expenses = results[3] as List<Expense>;

  ProfitAndLoss between(DateTime s, DateTime e) {
    final inRange = invoices.where((m) {
      final d = _salesDay(m);
      return d != null && !d.isBefore(s) && d.isBefore(e);
    }).toList();
    return pnlFrom(profitFromInvoices(inRange, products, payables, s, e), expenses, s, e);
  }

  return PnlData(
    between(start, end),
    [for (var i = 0; i < 6; i++) between(DateTime(firstMonth.year, firstMonth.month + i), DateTime(firstMonth.year, firstMonth.month + i + 1))],
  );
}
