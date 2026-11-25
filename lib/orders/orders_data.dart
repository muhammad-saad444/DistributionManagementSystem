// Purchase orders (to suppliers, before goods arrive) and sales orders (from bookers, approved by
// the office before they become invoices).
//
// Neither touches stock or money by itself:
//   purchase order → goods received on a purchase bill → stock in, owed to the supplier
//   sales order    → approved → invoice → stock out, owed by the shop
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../account/account.dart';
import '../inventory/inventory_data.dart';
import '../invoices/company_profile.dart';

final _db = FirebaseFirestore.instance;
num _asNum(Object? v) => v is num ? v : num.tryParse('${v ?? ''}'.trim()) ?? 0;
DateTime? _asDate(Object? v) => v is Timestamp ? v.toDate() : (v is DateTime ? v : null);
String _s(Map m, String k) => (m[k] ?? '').toString().trim();
String _who() => FirebaseAuth.instance.currentUser?.email ?? '';

/// The next number in a series: PO-0001, SO-0001… from the highest one in use.
String nextNumber(String prefix, Iterable<String> used) {
  var max = 0;
  for (final u in used) {
    if (!u.startsWith(prefix)) continue;
    final n = int.tryParse(u.substring(prefix.length).replaceAll(RegExp(r'\D'), '')) ?? 0;
    if (n > max) max = n;
  }
  return '$prefix${(max + 1).toString().padLeft(4, '0')}';
}

// =============================================================================
// Purchase orders
// =============================================================================

class PoLine {
  final String productId;
  final String productName;
  final num qty;
  final num unitCost;
  final num received;
  const PoLine({required this.productId, required this.productName, required this.qty, required this.unitCost, this.received = 0});

  num get amount => qty * unitCost;
  num get remaining => qty - received > 0 ? qty - received : 0;

  Map<String, dynamic> toMap() =>
      {'productId': productId, 'productName': productName, 'qty': qty, 'unitCost': unitCost, 'received': received};

  factory PoLine.fromMap(Map m) => PoLine(
        productId: _s(m, 'productId'),
        productName: _s(m, 'productName'),
        qty: _asNum(m['qty']),
        unitCost: _asNum(m['unitCost']),
        received: _asNum(m['received']),
      );

  PoLine withReceived(num r) => PoLine(productId: productId, productName: productName, qty: qty, unitCost: unitCost, received: r);
}

const poStatuses = ['open', 'partial', 'received', 'cancelled'];

class PurchaseOrder {
  final String id;
  final String number;
  final String supplierId;
  final String supplierName;
  final DateTime date;
  final DateTime? expected;
  final String warehouseId;
  final List<PoLine> lines;
  final String note;
  final String status; // open | partial | received | cancelled
  final String quotationId;
  final List<String> purchaseIds; // bills that received goods against it

  const PurchaseOrder({
    this.id = '',
    required this.number,
    required this.supplierId,
    required this.supplierName,
    required this.date,
    this.expected,
    this.warehouseId = mainWarehouseId,
    required this.lines,
    this.note = '',
    this.status = 'open',
    this.quotationId = '',
    this.purchaseIds = const [],
  });

  num get total => lines.fold<num>(0, (s, l) => s + l.amount);
  bool get isOpen => status == 'open' || status == 'partial';
  bool get nothingReceived => lines.every((l) => l.received <= 0);
  bool get isLate {
    final e = expected;
    if (e == null || !isOpen) return false;
    final today = DateTime.now();
    return DateTime(e.year, e.month, e.day).isBefore(DateTime(today.year, today.month, today.day));
  }

  factory PurchaseOrder.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data() ?? const {};
    final lines = m['lines'];
    final ids = m['purchaseIds'];
    return PurchaseOrder(
      id: doc.id,
      number: _s(m, 'number'),
      supplierId: _s(m, 'supplierId'),
      supplierName: _s(m, 'supplierName'),
      date: _asDate(m['date']) ?? _asDate(m['createdAt']) ?? DateTime.now(),
      expected: _asDate(m['expected']),
      warehouseId: _s(m, 'warehouseId').isEmpty ? mainWarehouseId : _s(m, 'warehouseId'),
      lines: lines is List ? [for (final l in lines) if (l is Map) PoLine.fromMap(l)] : const [],
      note: _s(m, 'note'),
      status: poStatuses.contains(m['status']) ? m['status'] as String : 'open',
      quotationId: _s(m, 'quotationId'),
      purchaseIds: ids is List ? [for (final i in ids) i.toString()] : const [],
    );
  }
}

Future<List<PurchaseOrder>> loadPurchaseOrders() async {
  final snap = await companyCol('purchase_orders').orderBy('date', descending: true).get();
  return snap.docs.map(PurchaseOrder.fromDoc).toList();
}

/// Adds or updates a purchase order. A new one gets the next PO number. Returns its id.
Future<String> savePurchaseOrder(PurchaseOrder po) async {
  final data = {
    'supplierId': po.supplierId,
    'supplierName': po.supplierName,
    'date': Timestamp.fromDate(po.date),
    'expected': po.expected == null ? null : Timestamp.fromDate(po.expected!),
    'warehouseId': po.warehouseId,
    'lines': po.lines.map((l) => l.toMap()).toList(),
    'total': po.total,
    'note': po.note,
  };
  final col = companyCol('purchase_orders');
  if (po.id.isNotEmpty) {
    await col.doc(po.id).update(data);
    return po.id;
  }
  final last = await col.orderBy('createdAt', descending: true).limit(20).get();
  final number = nextNumber('PO-', last.docs.map((d) => _s(d.data(), 'number')));
  final ref = await col.add({
    ...data,
    'number': number,
    'status': 'open',
    'quotationId': po.quotationId,
    'purchaseIds': <String>[],
    'by': _who(),
    'createdAt': FieldValue.serverTimestamp(),
  });
  return ref.id;
}

Future<void> cancelPurchaseOrder(String id) =>
    companyCol('purchase_orders').doc(id).update({'status': 'cancelled', 'cancelledBy': _who()});

Future<void> deletePurchaseOrder(String id) => companyCol('purchase_orders').doc(id).delete();

/// Records goods received on bill [purchaseId] against the order: received quantities go up and
/// the status follows (partial / received).
Future<void> receiveAgainstOrder(PurchaseOrder po, List<PurchaseLine> received, String purchaseId) async {
  final ref = companyCol('purchase_orders').doc(po.id);
  await _db.runTransaction((t) async {
    final fresh = PurchaseOrder.fromDoc(await t.get(ref));
    final got = <String, num>{};
    for (final l in received) {
      got[l.productId] = (got[l.productId] ?? 0) + l.qty;
    }
    final lines = [
      for (final l in fresh.lines)
        () {
          final add = got.remove(l.productId) ?? 0;
          return l.withReceived(l.received + add);
        }(),
    ];
    final allIn = lines.every((l) => l.received >= l.qty);
    t.update(ref, {
      'lines': lines.map((l) => l.toMap()).toList(),
      'status': allIn ? 'received' : 'partial',
      'purchaseIds': FieldValue.arrayUnion([purchaseId]),
      'lastReceivedAt': FieldValue.serverTimestamp(),
    });
  });
  await companyCol('purchases').doc(purchaseId).update({'purchaseOrderId': po.id, 'purchaseOrderNo': po.number});
}

// =============================================================================
// Sales orders
// =============================================================================

/// Whether bookers' orders wait for the office's approval before becoming invoices.
DocumentReference<Map<String, dynamic>> get _ordersSettings => companyCol('settings').doc('orders');

Future<bool> ordersNeedApproval() async => (await _ordersSettings.get()).data()?['requireApproval'] == true;
Future<void> setOrdersNeedApproval(bool on) =>
    _ordersSettings.set({'requireApproval': on, 'by': _who(), 'at': FieldValue.serverTimestamp()}, SetOptions(merge: true));

const soStatuses = ['pending', 'invoiced', 'rejected', 'cancelled'];

/// A booker's order, in the same shape as an invoice so approving it just makes the invoice.
class SalesOrder {
  final String id;
  final String number;
  final String status; // pending | invoiced | rejected | cancelled
  final String userId; // the booker
  final String userEmail;
  final String bookerName;
  final String customer;
  final String area;
  final String salesDate; // dd-MM-yyyy, as on invoices
  final List<Map<String, String>> items; // Product Name, Size, TP, QTY, BNS, Gross Total
  final String discountType; // percent | amount
  final num discount;
  final String warehouseId;
  final String note;
  final String invoiceId;
  final String invoiceNumber;
  final String decisionNote;
  final DateTime? createdAt;
  // The booker chose sales tax on (true) or off (false); null on orders from before the choice.
  final bool? salesTax;

  const SalesOrder({
    this.id = '',
    this.number = '',
    this.status = 'pending',
    required this.userId,
    this.userEmail = '',
    this.bookerName = '',
    required this.customer,
    this.area = '',
    required this.salesDate,
    required this.items,
    this.discountType = 'percent',
    this.discount = 0,
    this.warehouseId = mainWarehouseId,
    this.note = '',
    this.invoiceId = '',
    this.invoiceNumber = '',
    this.decisionNote = '',
    this.createdAt,
    this.salesTax,
  });

  static num lineTotal(Map<String, String> r) => _asNum(r['TP']) * _asNum(r['QTY']);
  num get total => items.fold<num>(0, (s, r) => s + lineTotal(r));
  num get grandTotal => discountType == 'percent' ? total - total * discount / 100 : total - discount;

  factory SalesOrder.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data() ?? const {};
    final items = m['items'];
    return SalesOrder(
      id: doc.id,
      number: _s(m, 'number'),
      status: soStatuses.contains(m['status']) ? m['status'] as String : 'pending',
      userId: _s(m, 'userId'),
      userEmail: _s(m, 'userEmail'),
      bookerName: _s(m, 'bookerName'),
      customer: _s(m, 'customer'),
      area: _s(m, 'area'),
      salesDate: _s(m, 'salesDate'),
      items: items is List
          ? [
              for (final i in items)
                if (i is Map) {for (final e in i.entries) e.key.toString(): '${e.value ?? ''}'},
            ]
          : const [],
      discountType: _s(m, 'discountType') == 'amount' ? 'amount' : 'percent',
      discount: _asNum(m['discountValue'] ?? m['discountPercent']),
      warehouseId: _s(m, 'warehouseId').isEmpty ? mainWarehouseId : _s(m, 'warehouseId'),
      note: _s(m, 'note'),
      invoiceId: _s(m, 'invoiceId'),
      invoiceNumber: _s(m, 'invoiceNumber'),
      decisionNote: _s(m, 'decisionNote'),
      createdAt: _asDate(m['createdAt']),
      salesTax: m['salesTax'] is bool ? m['salesTax'] as bool : null,
    );
  }

  /// The fields an invoice is saved with (see the booker's Book Order screen).
  Map<String, dynamic> invoiceFields(String invoiceNumber, List<Map<String, String>> lines) {
    final t = lines.fold<num>(0, (s, r) => s + lineTotal(r));
    final g = discountType == 'percent' ? t - t * discount / 100 : t - discount;
    final p = salesDate.split('-');
    final day = p.length == 3 ? DateTime(int.parse(p[2]), int.parse(p[1]), int.parse(p[0])) : DateTime.now();
    return {
      'invoiceNumber': invoiceNumber,
      'salesDate': salesDate,
      'salesDateTs': Timestamp.fromDate(day),
      'customer': customer,
      'area': area,
      'items': lines,
      'discountPercent': '${discount == discount.roundToDouble() ? discount.toInt() : discount}',
      'discountType': discountType,
      'discountValue': '${discount == discount.roundToDouble() ? discount.toInt() : discount}',
      'total': t.toDouble(),
      'grandTotal': g.toDouble(),
      'createdAt': DateTime.now(),
      'userId': userId,
      'userEmail': userEmail,
      'warehouseId': warehouseId,
      'salesOrderId': id,
      'salesOrderNo': number,
    };
  }
}

/// A booker sends an order (instead of an invoice) for the office to approve. Returns its number.
Future<String> placeSalesOrder(Map<String, dynamic> invoiceShapedData, {String bookerName = ''}) async {
  final col = companyCol('sales_orders');
  final last = await col.orderBy('createdAt', descending: true).limit(20).get();
  final number = nextNumber('SO-', last.docs.map((d) => _s(d.data(), 'number')));
  final data = {...invoiceShapedData}..remove('invoiceNumber');
  await col.add({
    ...data,
    'number': number,
    'status': 'pending',
    'bookerName': bookerName,
    'createdAt': FieldValue.serverTimestamp(),
  });
  return number;
}

Future<List<SalesOrder>> loadSalesOrders() async {
  final snap = await companyCol('sales_orders').orderBy('createdAt', descending: true).limit(300).get();
  return snap.docs.map(SalesOrder.fromDoc).toList();
}

/// The signed-in booker's orders, newest first.
Future<List<SalesOrder>> loadMySalesOrders() async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return const [];
  final snap = await companyCol('sales_orders').where('userId', isEqualTo: uid).get();
  return snap.docs.map(SalesOrder.fromDoc).toList()
    ..sort((a, b) => (b.createdAt ?? DateTime(2000)).compareTo(a.createdAt ?? DateTime(2000)));
}

/// Units each pending order asks for, per product name (lower case): stock that's spoken for.
Map<String, num> pendingDemand(List<SalesOrder> orders, {String? exceptId}) {
  final out = <String, num>{};
  for (final o in orders) {
    if (o.status != 'pending' || o.id == exceptId) continue;
    for (final r in o.items) {
      final k = (r['Product Name'] ?? '').trim().toLowerCase();
      out[k] = (out[k] ?? 0) + _asNum(r['QTY']) + _asNum(r['BNS']);
    }
  }
  return out;
}

/// The booker's next invoice number (their invoices are numbered per booker).
Future<String> _nextInvoiceNumberFor(String userId) async {
  final snap = await companyCol('invoices')
      .where('userId', isEqualTo: userId)
      .orderBy('createdAt', descending: true)
      .limit(1)
      .get();
  final last = snap.docs.isEmpty ? 0 : int.tryParse('${snap.docs.first.data()['invoiceNumber'] ?? 0}') ?? 0;
  return '${last + 1}';
}

/// Approves an order with the (possibly changed) [lines]: the invoice is made in the booker's
/// name, stock comes out of their warehouse, and the order points at the invoice. Returns the
/// invoice number.
Future<String> approveSalesOrder(SalesOrder o, List<Map<String, String>> lines, {String note = ''}) async {
  final number = await _nextInvoiceNumberFor(o.userId);
  final invoice = companyCol('invoices').doc();
  final fields = o.invoiceFields(number, lines);
  // sales tax at today's settings, kept on the invoice (sets grandTotal too)
  final profile = await loadCompanyProfile();
  final withTax = profile.taxEnabled && (o.salesTax ?? true); // the booker's choice on the order
  final data = {
    ...fields,
    if (withTax) ...profile.taxFieldsFor(lines, (fields['grandTotal'] as num).toDouble()),
  };
  final batch = _db.batch();
  final stock = await addInvoiceStockMoves(
    batch,
    afterItems: lines,
    deleting: false,
    invoiceId: invoice.id,
    invoiceNo: number,
    shop: o.customer,
    warehouseId: o.warehouseId,
  );
  batch.set(invoice, {...data, ...?stock?.fields, 'approvedBy': _who()});
  batch.update(companyCol('sales_orders').doc(o.id), {
    'status': 'invoiced',
    'invoiceId': invoice.id,
    'invoiceNumber': number,
    'approvedItems': lines,
    'decisionNote': note,
    'decidedBy': _who(),
    'decidedAt': FieldValue.serverTimestamp(),
  });
  await batch.commit();
  return number;
}

Future<void> rejectSalesOrder(SalesOrder o, String reason) => companyCol('sales_orders').doc(o.id).update({
      'status': 'rejected',
      'decisionNote': reason,
      'decidedBy': _who(),
      'decidedAt': FieldValue.serverTimestamp(),
    });

/// A booker withdraws their own order while it's still pending.
Future<void> cancelMySalesOrder(SalesOrder o) => companyCol('sales_orders').doc(o.id).update({'status': 'cancelled'});

/// Who placed each order, for labels: booker uid → name.
Future<Map<String, String>> bookerNames() async {
  final users = await loadCompanyUsers();
  return {for (final u in users) u.uid: u.name.isEmpty ? u.email : u.name};
}
