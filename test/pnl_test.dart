// Profit & loss: sales − cost of goods = gross profit; − expenses = net profit.
import 'package:an_agency/accounts/pnl_data.dart';
import 'package:an_agency/expenses/expenses_data.dart';
import 'package:an_agency/inventory/inventory_data.dart';
import 'package:flutter_test/flutter_test.dart';

StockProduct _p(String name, num cost) => StockProduct(
    id: name, name: name, supplier: '', category: '', size: '', salePrice: 0, costPrice: cost, stock: 0, baseSize: 0);

void main() {
  final start = DateTime(2026, 11);
  final end = DateTime(2026, 12);
  final products = ProductIndex([_p('Soap', 80), _p('Oil', 400)]);
  final payables = PayablesBook(const [], const [], const []);

  test('gross and net profit, with the invoice discount shared across lines', () {
    final invoices = [
      {
        'grandTotal': 1800, // 10% discount on 2000
        'items': [
          {'Product Name': 'Soap', 'QTY': 10, 'Gross Total': 1000},
          {'Product Name': 'Oil', 'QTY': 2, 'Gross Total': 1000},
        ],
      },
    ];
    final r = profitFromInvoices(invoices, products, payables, start, end);
    final pnl = pnlFrom(r, [
      Expense(date: DateTime(2026, 11, 3), category: 'Fuel', amount: 300),
      Expense(date: DateTime(2026, 10, 30), category: 'Rent', amount: 9999), // last month: not counted
    ], start, end);
    expect(pnl.sales, 1800);
    expect(pnl.cost, 10 * 80 + 2 * 400);
    expect(pnl.gross, 200);
    expect(pnl.expenses.total, 300);
    expect(pnl.net, -100);
    expect(pnl.marginOf(pnl.gross), closeTo(11.1, 0.1));
  });

  test('returns and bonus units: returns cut sales and cost, bonus units add cost', () {
    final invoices = [
      {
        'grandTotal': 900,
        'items': [
          {'Product Name': 'Soap', 'QTY': 10, 'BNS': 1, 'returnQty': 1, 'Gross Total': 1000, 'returnAmount': 100},
        ],
      },
    ];
    final pnl = pnlFrom(profitFromInvoices(invoices, products, payables, start, end), const [], start, end);
    expect(pnl.sales, 900);
    expect(pnl.cost, 10 * 80); // 10 sold + 1 free − 1 returned
    expect(pnl.net, 100);
  });

  test('products never purchased are counted and their cost is 0', () {
    final invoices = [
      {
        'grandTotal': 500,
        'items': [
          {'Product Name': 'Tea', 'QTY': 5, 'Gross Total': 500},
        ],
      },
    ];
    final pnl = pnlFrom(profitFromInvoices(invoices, products, payables, start, end), const [], start, end);
    expect(pnl.productsWithoutCost, 1);
    expect(pnl.cost, 0);
    expect(pnl.marginOf(0), 0);
    expect(ProfitAndLoss(start: start, end: end, sales: 0, cost: 0, expenses: ExpenseSummary.of(const [])).marginOf(5), isNull);
  });
}
