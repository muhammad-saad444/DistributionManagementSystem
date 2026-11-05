// Supplier quotations: price offers to compare before buying. They never touch stock or what is
// owed; only the purchase made from one does.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../account/account.dart';

num _asNum(Object? v) => v is num ? v : num.tryParse('${v ?? ''}'.trim()) ?? 0;
DateTime? _asDate(Object? v) => v is Timestamp ? v.toDate() : (v is DateTime ? v : null);

class QuoteLine {
  final String productId;
  final String productName;
  final num unitCost;
  final num minQty; // 0 = no minimum
  const QuoteLine({required this.productId, required this.productName, required this.unitCost, this.minQty = 0});

  Map<String, dynamic> toMap() =>
      {'productId': productId, 'productName': productName, 'unitCost': unitCost, 'minQty': minQty};

  factory QuoteLine.fromMap(Map m) => QuoteLine(
        productId: (m['productId'] ?? '').toString(),
        productName: (m['productName'] ?? '').toString(),
        unitCost: _asNum(m['unitCost']),
        minQty: _asNum(m['minQty']),
      );
}

class Quotation {
  final String id;
  final String supplierId;
  final String supplierName;
  final String ref; // the supplier's quotation number
  final DateTime date;
  final DateTime? validUntil; // null = no end date
  final List<QuoteLine> lines;
  final String note;
  final String purchaseId; // set once a purchase was made from it
  final DateTime? purchasedAt;

  const Quotation({
    this.id = '',
    required this.supplierId,
    required this.supplierName,
    this.ref = '',
    required this.date,
    this.validUntil,
    required this.lines,
    this.note = '',
    this.purchaseId = '',
    this.purchasedAt,
  });

  /// Past its valid-until day.
  bool get isExpired {
    final v = validUntil;
    if (v == null) return false;
    final today = DateTime.now();
    return DateTime(v.year, v.month, v.day).isBefore(DateTime(today.year, today.month, today.day));
  }

  bool get isUsed => purchaseId.isNotEmpty;

  factory Quotation.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data() ?? const {};
    return Quotation(
      id: doc.id,
      supplierId: (m['supplierId'] ?? '').toString(),
      supplierName: (m['supplierName'] ?? '').toString(),
      ref: (m['ref'] ?? '').toString(),
      date: _asDate(m['date']) ?? _asDate(m['createdAt']) ?? DateTime.now(),
      validUntil: _asDate(m['validUntil']),
      lines: [for (final l in (m['lines'] as List? ?? const [])) if (l is Map) QuoteLine.fromMap(l)],
      note: (m['note'] ?? '').toString(),
      purchaseId: (m['purchaseId'] ?? '').toString(),
      purchasedAt: _asDate(m['purchasedAt']),
    );
  }
}

/// Every quotation, newest first.
Future<List<Quotation>> loadQuotations() async {
  final snap = await companyCol('quotations').orderBy('date', descending: true).get();
  return snap.docs.map(Quotation.fromDoc).toList();
}

Future<void> saveQuotation(Quotation q) async {
  final data = {
    'supplierId': q.supplierId,
    'supplierName': q.supplierName,
    'ref': q.ref,
    'date': Timestamp.fromDate(q.date),
    'validUntil': q.validUntil == null ? null : Timestamp.fromDate(q.validUntil!),
    'lines': q.lines.map((l) => l.toMap()).toList(),
    'note': q.note,
  };
  final col = companyCol('quotations');
  if (q.id.isEmpty) {
    await col.add({
      ...data,
      'by': FirebaseAuth.instance.currentUser?.email ?? '',
      'createdAt': FieldValue.serverTimestamp(),
    });
  } else {
    await col.doc(q.id).update(data);
  }
}

Future<void> deleteQuotation(String id) => companyCol('quotations').doc(id).delete();

/// Records that a purchase was made from this quotation.
Future<void> markQuotationUsed(String id, String purchaseId) => companyCol('quotations')
    .doc(id)
    .update({'purchaseId': purchaseId, 'purchasedAt': FieldValue.serverTimestamp()});

/// One supplier's price for one product, for comparing.
class QuoteOffer {
  final Quotation quotation;
  final QuoteLine line;
  const QuoteOffer(this.quotation, this.line);
}

/// For each product, the offers from quotations that are still valid, cheapest first. A supplier
/// that quoted the same product more than once counts with its newest quotation only.
Map<String, List<QuoteOffer>> compareOffers(List<Quotation> quotations) {
  final out = <String, List<QuoteOffer>>{};
  final seen = <String>{}; // productId|supplierId
  for (final q in quotations) {
    // newest first, so the first one seen per supplier is the latest
    if (q.isExpired) continue;
    for (final l in q.lines) {
      if (l.unitCost <= 0 || !seen.add('${l.productId}|${q.supplierId}')) continue;
      out.putIfAbsent(l.productId, () => []).add(QuoteOffer(q, l));
    }
  }
  for (final list in out.values) {
    list.sort((a, b) => a.line.unitCost.compareTo(b.line.unitCost));
  }
  return out;
}
