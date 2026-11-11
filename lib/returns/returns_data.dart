// Market returns: goods a shop gives back on one of its invoices. One way to record them, used by
// the admin's Invoices page and the booker's invoice screen alike:
//   - the shop is refunded what it actually paid: the trade price less the invoice's discount
//   - good units go back into stock; damaged or expired ones don't (they're written off)
//   - every return is kept in `returns`: when, who, which goods, why, and the refund
//
// On the invoice each line keeps `returnQty` (all returned units), `returnAmount` (their value
// at trade price) and `damagedQty` (the part that was damaged or expired). Stock counts an
// invoice as QTY − (returnQty − damagedQty) + bonus: only good returns come back.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../account/account.dart';
import '../inventory/inventory_data.dart' show updateInvoiceWithStock;

enum ReturnCondition { good, damaged, expired }

extension ReturnConditionX on ReturnCondition {
  String get label => switch (this) {
        ReturnCondition.good => 'Good',
        ReturnCondition.damaged => 'Damaged',
        ReturnCondition.expired => 'Expired',
      };

  /// Good units can be sold again; damaged and expired ones are written off.
  bool get backToStock => this == ReturnCondition.good;
}

ReturnCondition conditionNamed(String? s) =>
    ReturnCondition.values.where((c) => c.name == s).firstOrNull ?? ReturnCondition.good;

double _n(dynamic v) => (num.tryParse('${v ?? 0}') ?? 0).toDouble();

/// How many more units of an invoice line can still be returned.
double returnableQty(Map item) => _n(item['QTY']) - _n(item['returnQty']);

/// One line of a return: [qty] units of the invoice's item at [index].
class ReturnLine {
  final int index;
  final double qty;
  final ReturnCondition condition;
  const ReturnLine(this.index, this.qty, [this.condition = ReturnCondition.good]);
}

/// What a return does to an invoice.
class ReturnOutcome {
  final List<Map<String, dynamic>> items; // the invoice's items after the return
  final double total; // before discount
  final double grandTotal; // what the shop owes now
  final double refund; // taken off what the shop owes
  final List<Map<String, dynamic>> lines; // for the returns record

  const ReturnOutcome(this.items, this.total, this.grandTotal, this.refund, this.lines);
}

/// The refund is the trade price less the invoice's discount: a shop that got 10% off pays back
/// 90% of the trade price, not all of it.
double invoiceDiscountFactor(Map<String, dynamic> invoice) {
  final total = _n(invoice['total']);
  final grand = _n(invoice['grandTotal']);
  if (total <= 0) return 1;
  return (grand / total).clamp(0.0, 1.0).toDouble();
}

/// Works out a return on [invoice] without saving anything. Throws [ArgumentError] when a line
/// returns more than is left to return, or nothing at all.
ReturnOutcome applyReturn(Map<String, dynamic> invoice, List<ReturnLine> lines) {
  final items = [for (final it in (invoice['items'] as List? ?? const [])) Map<String, dynamic>.from(it as Map)];
  final factor = invoiceDiscountFactor(invoice);
  var total = _n(invoice['total']);
  var grand = _n(invoice['grandTotal']);
  var refund = 0.0;
  final log = <Map<String, dynamic>>[];

  final wanted = lines.where((l) => l.qty > 0).toList();
  if (wanted.isEmpty) throw ArgumentError('Enter how many units came back');

  // Add up per item first, so two lines for one item can't together exceed what is left.
  final perItem = <int, double>{};
  for (final l in wanted) {
    if (l.index < 0 || l.index >= items.length) throw ArgumentError('No such item on the invoice');
    perItem[l.index] = (perItem[l.index] ?? 0) + l.qty;
  }
  for (final e in perItem.entries) {
    final left = returnableQty(items[e.key]);
    if (e.value > left + 1e-9) {
      throw ArgumentError('Only ${left.toStringAsFixed(0)} of ${items[e.key]['Product Name'] ?? 'this item'} can still be returned');
    }
  }

  for (final l in wanted) {
    final item = items[l.index];
    final tp = _n(item['TP']);
    final gross = l.qty * tp;
    final lineRefund = gross * factor;
    item['returnQty'] = _qty(_n(item['returnQty']) + l.qty);
    item['returnAmount'] = (_n(item['returnAmount']) + gross).toStringAsFixed(2);
    if (!l.condition.backToStock) item['damagedQty'] = _qty(_n(item['damagedQty']) + l.qty);
    total -= gross;
    grand -= lineRefund;
    refund += lineRefund;
    log.add({
      'product': (item['Product Name'] ?? '').toString(),
      'qty': l.qty,
      'condition': l.condition.name,
      'tp': tp,
      'amount': double.parse(lineRefund.toStringAsFixed(2)),
    });
  }
  return ReturnOutcome(items, total < 0 ? 0 : total, grand < 0 ? 0 : grand, refund, log);
}

String _qty(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

/// Saves a return on an invoice: updates the invoice and stock, and keeps a record. Returns the
/// refund (what the shop owes less).
Future<double> saveReturn({required String invoiceId, required List<ReturnLine> lines, String note = ''}) async {
  final ref = companyCol('invoices').doc(invoiceId);
  final invoice = (await ref.get()).data();
  if (invoice == null) throw StateError('This invoice no longer exists');
  final out = applyReturn(invoice, lines);
  await updateInvoiceWithStock(invoiceId, {
    'items': out.items,
    'total': out.total.round(),
    'grandTotal': out.grandTotal.round(),
    'isReturnProcessed': true,
    'updatedAt': FieldValue.serverTimestamp(),
  });
  await companyCol('returns').add({
    'invoiceId': invoiceId,
    'invoiceNumber': (invoice['invoiceNumber'] ?? '').toString(),
    'customer': (invoice['customer'] ?? '').toString(),
    'area': (invoice['area'] ?? '').toString(),
    'userId': (invoice['userId'] ?? '').toString(), // the invoice's booker
    'salesDate': (invoice['salesDate'] ?? '').toString(),
    'lines': out.lines,
    'refund': double.parse(out.refund.toStringAsFixed(2)),
    'note': note.trim(),
    'date': Timestamp.now(),
    'byUid': FirebaseAuth.instance.currentUser?.uid ?? '',
    'byName': Account.user?.display ?? '',
    'createdAt': FieldValue.serverTimestamp(),
  });
  return out.refund;
}

/// A saved return.
class ReturnRecord {
  final String id;
  final DateTime date;
  final String invoiceNumber;
  final String customer;
  final String area;
  final String userId;
  final List<Map<String, dynamic>> lines;
  final double refund;
  final String note;
  final String byName;

  const ReturnRecord({
    required this.id,
    required this.date,
    required this.invoiceNumber,
    required this.customer,
    required this.area,
    required this.userId,
    required this.lines,
    required this.refund,
    required this.note,
    required this.byName,
  });

  factory ReturnRecord.fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data();
    return ReturnRecord(
      id: d.id,
      date: m['date'] is Timestamp ? (m['date'] as Timestamp).toDate() : DateTime(2000),
      invoiceNumber: (m['invoiceNumber'] ?? '').toString(),
      customer: (m['customer'] ?? '').toString(),
      area: (m['area'] ?? '').toString(),
      userId: (m['userId'] ?? '').toString(),
      lines: [for (final l in (m['lines'] as List? ?? const [])) if (l is Map) Map<String, dynamic>.from(l)],
      refund: _n(m['refund']),
      note: (m['note'] ?? '').toString(),
      byName: (m['byName'] ?? '').toString(),
    );
  }

  double qtyWhere(bool Function(ReturnCondition c) test) =>
      lines.where((l) => test(conditionNamed(l['condition']?.toString()))).fold(0.0, (s, l) => s + _n(l['qty']));
  double amountWhere(bool Function(ReturnCondition c) test) =>
      lines.where((l) => test(conditionNamed(l['condition']?.toString()))).fold(0.0, (s, l) => s + _n(l['amount']));
}

/// Returns from [from] on, newest first.
Future<List<ReturnRecord>> loadReturns(DateTime from) async {
  final snap = await companyCol('returns').where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(from)).get();
  return snap.docs.map(ReturnRecord.fromDoc).toList()..sort((a, b) => b.date.compareTo(a.date));
}
