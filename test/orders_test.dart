// Order arithmetic: numbering, totals, what an approved order's invoice looks like, reserved stock.
import 'package:an_agency/orders/orders_data.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, String> _item(String name, num tp, num qty, [num bns = 0]) =>
    {'Product Name': name, 'Size': 'Piece', 'TP': '$tp', 'QTY': '$qty', 'BNS': '$bns', 'Gross Total': '${tp * qty}'};

void main() {
  group('numbering', () {
    test('first number', () => expect(nextNumber('PO-', const []), 'PO-0001'));
    test('after the highest, ignoring other series and gaps', () {
      expect(nextNumber('SO-', ['SO-0001', 'SO-0007', 'PO-0099', '', 'SO-0003']), 'SO-0008');
    });
  });

  test('purchase order line: what is still to come', () {
    const l = PoLine(productId: 'p', productName: 'X', qty: 100, unitCost: 9, received: 40);
    expect(l.amount, 900);
    expect(l.remaining, 60);
    expect(l.withReceived(120).remaining, 0); // over-delivered never goes negative
  });

  group('sales order', () {
    final o = SalesOrder(
      id: 'so1',
      number: 'SO-0004',
      userId: 'booker1',
      userEmail: 'b@x.com',
      customer: 'Shop A',
      area: 'Model Town',
      salesDate: '05-11-2026',
      items: [_item('Tea', 50, 10), _item('Soap', 20, 5, 1)],
      discount: 10,
      warehouseId: 'w2',
    );

    test('totals with a percent discount', () {
      expect(o.total, 600);
      expect(o.grandTotal, 540);
    });

    test('amount discount', () {
      final a = SalesOrder(userId: 'b', customer: 'S', salesDate: '01-01-2026', items: [_item('Tea', 50, 10)],
          discountType: 'amount', discount: 25);
      expect(a.grandTotal, 475);
    });

    test('approved with changed lines: the invoice uses the new lines and keeps the booker', () {
      final f = o.invoiceFields('12', [_item('Tea', 50, 8)]);
      expect(f['invoiceNumber'], '12');
      expect(f['userId'], 'booker1');
      expect(f['customer'], 'Shop A');
      expect(f['warehouseId'], 'w2');
      expect(f['total'], 400);
      expect(f['grandTotal'], 360);
      expect(f['salesOrderNo'], 'SO-0004');
      expect((f['salesDateTs'] as Timestamp).toDate(), DateTime(2026, 11, 5));
    });

    test('stock promised to waiting orders (qty + bonus), not to decided ones', () {
      final waiting2 = SalesOrder(id: 'so2', userId: 'b', customer: 'B', salesDate: '05-11-2026', items: [_item('tea ', 50, 3)]);
      final done = SalesOrder(
          id: 'so3', status: 'invoiced', userId: 'b', customer: 'C', salesDate: '05-11-2026', items: [_item('Tea', 50, 99)]);
      final d = pendingDemand([o, waiting2, done]);
      expect(d['tea'], 13);
      expect(d['soap'], 6);
      expect(pendingDemand([o, waiting2, done], exceptId: 'so1')['tea'], 3);
    });
  });
}
