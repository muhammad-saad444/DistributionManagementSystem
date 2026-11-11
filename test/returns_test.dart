// Market returns: refund after the invoice discount, damaged goods kept out of stock.
import 'package:an_agency/inventory/inventory_data.dart';
import 'package:an_agency/returns/returns_data.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _invoice({num total = 2000, num grand = 1800}) => {
      'total': total,
      'grandTotal': grand, // 10% discount
      'items': [
        {'Product Name': 'Soap', 'QTY': '10', 'TP': '100', 'Gross Total': '1000'},
        {'Product Name': 'Oil', 'QTY': '5', 'TP': '200', 'Gross Total': '1000', 'BNS': '1'},
      ],
    };

void main() {
  test('the refund is the trade price less the invoice discount', () {
    final out = applyReturn(_invoice(), const [ReturnLine(0, 2)]);
    expect(out.refund, 180); // 2 × 100, less 10%
    expect(out.total, 1800);
    expect(out.grandTotal, 1620);
    expect(out.items[0]['returnQty'], '2');
    expect(out.items[0]['returnAmount'], '200.00');
    expect(out.items[0].containsKey('damagedQty'), isFalse);
  });

  test('damaged and expired units are marked so stock leaves them out', () {
    final out = applyReturn(_invoice(), const [
      ReturnLine(0, 1, ReturnCondition.damaged),
      ReturnLine(0, 1, ReturnCondition.expired),
      ReturnLine(0, 1),
    ]);
    expect(out.items[0]['returnQty'], '3');
    expect(out.items[0]['damagedQty'], '2');
    expect(out.lines.map((l) => l['condition']), ['damaged', 'expired', 'good']);

    final products = ProductIndex([
      StockProduct(id: 's', name: 'Soap', supplier: '', category: '', size: '', salePrice: 0, costPrice: 0, stock: 0, baseSize: 0),
      StockProduct(id: 'o', name: 'Oil', supplier: '', category: '', size: '', salePrice: 0, costPrice: 0, stock: 0, baseSize: 0),
    ]);
    // Soap: 10 sold, 1 good unit came back → 9 out of stock. Oil: 5 + 1 bonus.
    expect(invoiceUnits(out.items, products), {'s': 9, 'o': 6});
  });

  test('cannot return more than is left, or nothing', () {
    expect(() => applyReturn(_invoice(), const [ReturnLine(1, 6)]), throwsArgumentError);
    expect(() => applyReturn(_invoice(), const [ReturnLine(1, 3), ReturnLine(1, 3)]), throwsArgumentError);
    expect(() => applyReturn(_invoice(), const [ReturnLine(0, 0)]), throwsArgumentError);
    final once = applyReturn(_invoice(), const [ReturnLine(1, 5)]);
    expect(returnableQty(once.items[1]), 0);
  });

  test('an invoice without a discount refunds the full trade price', () {
    final out = applyReturn(_invoice(total: 2000, grand: 2000), const [ReturnLine(1, 2)]);
    expect(out.refund, 400);
    expect(out.grandTotal, 1600);
  });
}
