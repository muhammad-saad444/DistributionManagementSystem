// Delivery / dispatch: the office groups a day's invoices into trips (a van, a delivery man),
// prints each trip's load sheet, sends it out, and settles it when the van is back: each invoice
// delivered, partly delivered (the rest is returned) or not delivered (all returned), and the
// cash collected at the door, which goes into the shop's khata.
//
//   dispatches/{id}: number, date, vehicle, driver, driverPhone, invoiceIds, status
//                    (loading | out | settled), notes, createdAt, outAt, settledAt
//   invoices: dispatchId, deliveryStatus (out | delivered | partial | returned), deliveredAt,
//             codCollected
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../account/account.dart';
import '../audit/audit.dart';
import '../inventory/packs.dart';
import '../returns/returns_data.dart';

enum TripStatus { loading, out, settled }

enum DeliveryOutcome { delivered, partial, returned }

extension DeliveryOutcomeX on DeliveryOutcome {
  String get label => switch (this) {
        DeliveryOutcome.delivered => 'Delivered',
        DeliveryOutcome.partial => 'Partly delivered',
        DeliveryOutcome.returned => 'Not delivered',
      };
}

double _n(dynamic v) => (num.tryParse('${v ?? 0}') ?? 0).toDouble();

/// An invoice as the deliveries page needs it.
class DeliveryInvoice {
  final String id;
  final String number;
  final String shop;
  final String area;
  final String bookerId;
  final String bookerEmail;
  final double amount; // what the shop owes on it now (grandTotal)
  final List<Map<String, dynamic>> items;
  final String? dispatchId;
  final String deliveryStatus; // '' = not dispatched yet
  final double codCollected;

  const DeliveryInvoice({
    required this.id,
    required this.number,
    required this.shop,
    required this.area,
    required this.bookerId,
    required this.bookerEmail,
    required this.amount,
    required this.items,
    this.dispatchId,
    this.deliveryStatus = '',
    this.codCollected = 0,
  });

  factory DeliveryInvoice.fromMap(String id, Map<String, dynamic> m) => DeliveryInvoice(
        id: id,
        number: (m['invoiceNumber'] ?? '').toString(),
        shop: (m['customer'] ?? '').toString(),
        area: (m['area'] ?? '').toString(),
        bookerId: (m['userId'] ?? '').toString(),
        bookerEmail: (m['userEmail'] ?? '').toString(),
        amount: _n(m['grandTotal'] ?? m['total']),
        items: [for (final it in (m['items'] as List? ?? const [])) if (it is Map) Map<String, dynamic>.from(it)],
        dispatchId: (m['dispatchId'] ?? '').toString().isEmpty ? null : m['dispatchId'].toString(),
        deliveryStatus: (m['deliveryStatus'] ?? '').toString(),
        codCollected: _n(m['codCollected']),
      );

  bool get dispatched => dispatchId != null;
}

/// One product line on a load sheet: units to load (sold − returned + free).
class LoadLine {
  final String product;
  final String size;
  double qty = 0;
  double free = 0;
  double value = 0;
  int perCarton = 0; // units in a carton, if it is sold by the carton
  LoadLine(this.product, this.size);
  double get units => qty + free;
}

/// What to load for these invoices, by product, biggest first.
List<LoadLine> loadSheet(Iterable<DeliveryInvoice> invoices) {
  final by = <String, LoadLine>{};
  for (final inv in invoices) {
    for (final it in inv.items) {
      final name = (it['Product Name'] ?? '').toString().trim();
      if (name.isEmpty) continue;
      final line = by.putIfAbsent(name.toLowerCase(), () => LoadLine(name, (it['Size'] ?? '').toString()));
      if (line.perCarton == 0) line.perCarton = perCartonOf(it);
      final qty = _n(it['QTY']) - _n(it['returnQty']);
      line.qty += qty;
      line.free += _n(it['BNS'] ?? it['FOC']);
      line.value += qty * _n(it['TP']);
    }
  }
  return by.values.where((l) => l.units > 0).toList()..sort((a, b) => b.units.compareTo(a.units));
}

class Trip {
  final String id;
  final String number;
  final DateTime date;
  final String vehicle;
  final String driver;
  final String driverPhone;
  final List<String> invoiceIds;
  final TripStatus status;
  final String notes;

  const Trip({
    required this.id,
    required this.number,
    required this.date,
    required this.vehicle,
    required this.driver,
    required this.driverPhone,
    required this.invoiceIds,
    required this.status,
    this.notes = '',
  });

  factory Trip.fromMap(String id, Map<String, dynamic> m) => Trip(
        id: id,
        number: (m['number'] ?? '').toString(),
        date: m['date'] is Timestamp ? (m['date'] as Timestamp).toDate() : DateTime(2000),
        vehicle: (m['vehicle'] ?? '').toString(),
        driver: (m['driver'] ?? '').toString(),
        driverPhone: (m['driverPhone'] ?? '').toString(),
        invoiceIds: [for (final i in (m['invoiceIds'] as List? ?? const [])) i.toString()],
        status: TripStatus.values.where((s) => s.name == m['status']).firstOrNull ?? TripStatus.loading,
        notes: (m['notes'] ?? '').toString(),
      );

  String get statusLabel => switch (status) {
        TripStatus.loading => 'Loading',
        TripStatus.out => 'Out for delivery',
        TripStatus.settled => 'Settled',
      };
}

/// One invoice's result when a trip is settled.
class InvoiceSettlement {
  final DeliveryInvoice invoice;
  final DeliveryOutcome outcome;
  final double cashCollected;
  const InvoiceSettlement(this.invoice, this.outcome, this.cashCollected);
}

/// Totals for a settled (or settling) trip.
class TripSummary {
  final int delivered;
  final int partial;
  final int returned;
  final double cash;
  final double value;
  const TripSummary(this.delivered, this.partial, this.returned, this.cash, this.value);

  factory TripSummary.of(Iterable<InvoiceSettlement> s) => TripSummary(
        s.where((x) => x.outcome == DeliveryOutcome.delivered).length,
        s.where((x) => x.outcome == DeliveryOutcome.partial).length,
        s.where((x) => x.outcome == DeliveryOutcome.returned).length,
        s.fold(0, (t, x) => t + x.cashCollected),
        s.fold(0, (t, x) => t + x.invoice.amount),
      );
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// The day's invoices (by Sales Date) and trips.
Future<(List<DeliveryInvoice>, List<Trip>)> loadDeliveryDay(DateTime day) async {
  final start = _day(day);
  final end = start.add(const Duration(days: 1));
  final results = await Future.wait([
    companyCol('invoices')
        .where('salesDateTs', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('salesDateTs', isLessThan: Timestamp.fromDate(end))
        .get(),
    companyCol('dispatches').where('date', isEqualTo: Timestamp.fromDate(start)).get(),
  ]);
  final invoices = [for (final d in results[0].docs) DeliveryInvoice.fromMap(d.id, d.data())]
    ..sort((a, b) => (int.tryParse(a.number) ?? 0).compareTo(int.tryParse(b.number) ?? 0));
  final trips = [for (final d in results[1].docs) Trip.fromMap(d.id, d.data())]..sort((a, b) => a.number.compareTo(b.number));
  return (invoices, trips);
}

/// Makes a trip from [invoiceIds] on [day]. Trip numbers run per day: 1, 2, 3...
Future<void> createTrip({
  required DateTime day,
  required List<String> invoiceIds,
  required String vehicle,
  required String driver,
  String driverPhone = '',
  String notes = '',
  required int number,
}) async {
  final db = FirebaseFirestore.instance;
  final batch = db.batch();
  final ref = companyCol('dispatches').doc();
  batch.set(ref, {
    'number': '$number',
    'date': Timestamp.fromDate(_day(day)),
    'vehicle': vehicle.trim(),
    'driver': driver.trim(),
    'driverPhone': driverPhone.trim(),
    'invoiceIds': invoiceIds,
    'status': TripStatus.loading.name,
    'notes': notes.trim(),
    'createdAt': FieldValue.serverTimestamp(),
    'createdBy': FirebaseAuth.instance.currentUser?.uid ?? '',
  });
  for (final id in invoiceIds) {
    batch.update(companyCol('invoices').doc(id), {'dispatchId': ref.id, 'deliveryStatus': ''});
  }
  await batch.commit();
}

/// Sends the trip out: its invoices show as "Out".
Future<void> markTripOut(Trip t) async {
  final batch = FirebaseFirestore.instance.batch();
  batch.update(companyCol('dispatches').doc(t.id), {'status': TripStatus.out.name, 'outAt': FieldValue.serverTimestamp()});
  for (final id in t.invoiceIds) {
    batch.update(companyCol('invoices').doc(id), {'deliveryStatus': 'out'});
  }
  await batch.commit();
}

/// Cancels a trip that hasn't gone out: its invoices can go on another trip.
Future<void> cancelTrip(Trip t) async {
  final batch = FirebaseFirestore.instance.batch();
  for (final id in t.invoiceIds) {
    batch.update(companyCol('invoices').doc(id), {'dispatchId': FieldValue.delete(), 'deliveryStatus': FieldValue.delete()});
  }
  batch.delete(companyCol('dispatches').doc(t.id));
  await batch.commit();
  await logAudit(
    area: AuditArea.trip,
    action: AuditAction.delete,
    refId: t.id,
    title: 'Trip ${t.number} cancelled${t.driver.isEmpty ? '' : ' · ${t.driver}'}',
    changes: [AuditChange('Invoices', '${t.invoiceIds.length}', '')],
  );
}

/// Settles a trip. "Not delivered" invoices are returned in full (good, back to stock); for
/// "partly delivered" the office records the returned goods with the return form before settling.
/// Cash collected goes into the shop's khata as a payment (method: Cash on delivery).
Future<void> settleTrip(Trip t, List<InvoiceSettlement> results) async {
  final day = _day(DateTime.now());
  for (final r in results) {
    if (r.outcome == DeliveryOutcome.returned) {
      final lines = <ReturnLine>[
        for (var i = 0; i < r.invoice.items.length; i++)
          if (returnableQty(r.invoice.items[i]) > 0) ReturnLine(i, returnableQty(r.invoice.items[i])),
      ];
      if (lines.isNotEmpty) await saveReturn(invoiceId: r.invoice.id, lines: lines, note: 'Not delivered (trip ${t.number})');
    }
  }
  final batch = FirebaseFirestore.instance.batch();
  for (final r in results) {
    batch.update(companyCol('invoices').doc(r.invoice.id), {
      'deliveryStatus': switch (r.outcome) {
        DeliveryOutcome.delivered => 'delivered',
        DeliveryOutcome.partial => 'partial',
        DeliveryOutcome.returned => 'returned',
      },
      'deliveredAt': FieldValue.serverTimestamp(),
      'codCollected': r.cashCollected,
    });
    if (r.cashCollected > 0) {
      batch.set(companyCol('khata_entries').doc(), {
        'userId': r.invoice.bookerId,
        'userEmail': r.invoice.bookerEmail,
        'customer': r.invoice.shop.trim(),
        'type': 'payment',
        'amount': r.cashCollected,
        'method': 'Cash on delivery',
        'note': 'Trip ${t.number}${t.driver.isEmpty ? '' : ' · ${t.driver}'} · Invoice #${r.invoice.number}',
        'date': Timestamp.fromDate(day),
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
  }
  batch.update(companyCol('dispatches').doc(t.id), {'status': TripStatus.settled.name, 'settledAt': FieldValue.serverTimestamp()});
  await batch.commit();
  final s = TripSummary.of(results);
  await logAudit(
    area: AuditArea.trip,
    action: AuditAction.close,
    refId: t.id,
    title: 'Trip ${t.number} settled${t.driver.isEmpty ? '' : ' · ${t.driver}'}',
    amount: s.cash,
    changes: [
      for (final r in results)
        AuditChange('Invoice #${r.invoice.number} · ${r.invoice.shop}', '', '${r.outcome.label}, cash ${auditValue(r.cashCollected)}'),
    ],
  );
}
