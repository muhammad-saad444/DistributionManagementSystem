// Audit log: what changed, and which invoices are locked.
import 'package:an_agency/audit/audit.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('values read the same whether stored as text or numbers', () {
    expect(auditValue('12'), '12');
    expect(auditValue(12.0), '12');
    expect(auditValue(12.5), '12.50');
    expect(auditValue(null), '');
    expect(auditValue(Timestamp.fromDate(DateTime(2026, 11, 5))), '5 Nov 2026');
  });

  test('field changes list only what really changed', () {
    final before = {'customer': 'Shop A', 'grandTotal': '1000', 'discountValue': 0, 'area': 'Gulshan'};
    final after = {'customer': 'Shop A', 'grandTotal': 900, 'discountValue': 100, 'note': 'x'};
    expect(fieldChanges(before, after, const {'customer': 'Shop', 'grandTotal': 'Bill', 'discountValue': 'Discount', 'area': 'Area'}), [
      const AuditChange('Bill', '1000', '900'),
      const AuditChange('Discount', '0', '100'),
    ]); // area wasn't sent, so it isn't a change
  });

  test('invoice lines: quantity, price, free goods, added and removed', () {
    final before = [
      {'Product Name': 'Soap', 'QTY': '10', 'TP': '50', 'BNS': '0'},
      {'Product Name': 'Oil', 'QTY': '2', 'TP': '250'},
    ];
    final after = [
      {'Product Name': 'soap', 'QTY': '12', 'TP': '50', 'BNS': '1'},
      {'Product Name': 'Tea', 'QTY': '3', 'TP': '90'},
    ];
    expect(itemChanges(before, after).map((c) => c.toString()), [
      'soap qty: 10 → 12',
      'soap free: 0 → 1',
      'Oil: removed, was qty 2',
      'Tea: added, qty 3',
    ]);
    expect(itemChanges(before, before), isEmpty);
  });

  test('closed books include the whole closing day', () {
    final until = DateTime(2026, 10, 31, 23, 59, 59);
    expect(isClosedPeriod(DateTime(2026, 10, 31), until), isTrue);
    expect(isClosedPeriod(DateTime(2026, 10, 31, 18), until), isTrue);
    expect(isClosedPeriod(DateTime(2026, 11, 1), until), isFalse);
    expect(isClosedPeriod(DateTime(2026, 10, 1), null), isFalse);
    expect(isClosedPeriod(null, until), isFalse);
  });

  test('which invoices are locked, and why', () {
    final oct = {'salesDateTs': Timestamp.fromDate(DateTime(2026, 10, 20)), 'grandTotal': '500'};
    final nov = {'salesDateTs': Timestamp.fromDate(DateTime(2026, 11, 5)), 'grandTotal': '500'};
    final until = DateTime(2026, 10, 31, 23, 59, 59);
    expect(invoiceLock(oct, paid: true, closedUntil: until), InvoiceLock.closedPeriod);
    expect(invoiceLock(nov, closedUntil: until), InvoiceLock.none);
    expect(invoiceLock(nov, paid: true), InvoiceLock.paid);
    expect(invoiceLock({...nov, 'grandTotal': '0'}, paid: true), InvoiceLock.none); // nothing to pay
    expect(invoiceLock({...nov, 'deliveryStatus': 'delivered'}), InvoiceLock.delivered);
    expect(invoiceLock({...nov, 'deliveryStatus': 'out'}), InvoiceLock.none);
  });

  test('an entry reads back from the log', () {
    final e = AuditEntry.fromMap('l1', {
      'at': Timestamp.fromDate(DateTime(2026, 11, 12, 15, 40)),
      'byName': 'admin',
      'area': 'invoice',
      'action': 'edit',
      'title': 'Invoice #4 · test 2',
      'amount': 8910,
      'changes': [
        {'field': 'Bill', 'from': '9000', 'to': '8910'},
      ],
      'reason': 'Shop asked for discount',
    });
    expect(e.area, AuditArea.invoice);
    expect(e.amount, 8910);
    expect(e.changes.single.toString(), 'Bill: 9000 → 8910');
    expect(AuditAction.label(e.action), 'Changed');
  });
}
