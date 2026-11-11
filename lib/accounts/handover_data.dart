// Booker cash handover: cash a booker collects from shops (a khata payment in cash) stays with the
// booker until they hand it to the office, which the office records in `cash_handovers`
// (admins only). Holding = collected − handed over. Handovers clear the oldest collections first,
// so "oldest" says how long the earliest unhanded cash has been out.
//
// Not counted as held by a booker: payments by bank, online, cheque or wallet (they don't pass
// through the booker's hands) and office recoveries (the office received those itself).
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../account/account.dart';
import 'cashbook_data.dart';

/// Whether a khata entry is cash a booker collected in the field (and so must hand over).
bool isBookerCash(Map<String, dynamic> m) {
  if (m['type'] != 'payment') return false;
  final method = (m['method'] ?? '').toString();
  if (method == 'Office recovery') return false;
  return accountForMethod(method) == MoneyAccount.cash;
}

class Handover {
  final String? id;
  final String bookerUid;
  final String bookerName;
  final double amount;
  final DateTime date;
  final MoneyAccount into; // where the office put it: cash in hand or straight into the bank
  final String note;
  final String receivedBy;

  const Handover({
    this.id,
    required this.bookerUid,
    required this.bookerName,
    required this.amount,
    required this.date,
    this.into = MoneyAccount.cash,
    this.note = '',
    this.receivedBy = '',
  });

  factory Handover.fromMap(String id, Map<String, dynamic> m) => Handover(
        id: id,
        bookerUid: (m['userId'] ?? '').toString(),
        bookerName: (m['bookerName'] ?? '').toString(),
        amount: (num.tryParse('${m['amount'] ?? 0}') ?? 0).toDouble(),
        date: m['date'] is Timestamp ? (m['date'] as Timestamp).toDate() : DateTime(2000),
        into: MoneyAccount.values.where((a) => a.name == m['into']).firstOrNull ?? MoneyAccount.cash,
        note: (m['note'] ?? '').toString(),
        receivedBy: (m['receivedByName'] ?? '').toString(),
      );

  /// The handover as a line in the cash book: money arriving in the office.
  CashLine get cashLine => CashLine(
        date: date,
        account: into,
        amount: amount,
        source: CashSource.handover,
        title: 'Cash handed over by ${bookerName.isEmpty ? 'booker' : bookerName}',
        note: note,
      );
}

/// One booker's cash.
class BookerCash {
  final String uid;
  String name;
  double collected = 0; // all cash ever collected
  double handedOver = 0; // all ever handed over
  double collectedInPeriod = 0;
  double handedInPeriod = 0;
  DateTime? lastHandover;
  DateTime? oldestUnhanded; // date of the earliest collection not yet covered by handovers
  int collections = 0;

  BookerCash(this.uid, this.name);

  double get holding => collected - handedOver;
}

DateTime? _ts(dynamic v) => v is Timestamp ? v.toDate() : (v is DateTime ? v : null);

/// Each booker's cash, most held first. [payments]: khata entries (any; only booker cash counts).
/// The period ([start]..[end)) only affects the "in period" figures; holding is all-time.
List<BookerCash> bookerCash(
  List<Map<String, dynamic>> payments,
  List<Handover> handovers,
  Map<String, String> names, {
  DateTime? start,
  DateTime? end,
}) {
  bool inPeriod(DateTime d) => (start == null || !d.isBefore(start)) && (end == null || d.isBefore(end));
  final byUid = <String, BookerCash>{};
  BookerCash of(String uid) => byUid.putIfAbsent(uid, () => BookerCash(uid, names[uid] ?? 'Booker'));
  final collections = <String, List<(DateTime, double)>>{};

  for (final m in payments) {
    if (!isBookerCash(m)) continue;
    final uid = (m['userId'] ?? '').toString();
    final amount = (num.tryParse('${m['amount'] ?? 0}') ?? 0).toDouble();
    final date = _ts(m['date']) ?? _ts(m['createdAt']);
    if (uid.isEmpty || amount <= 0 || date == null) continue;
    final b = of(uid);
    b.collected += amount;
    b.collections++;
    if (inPeriod(date)) b.collectedInPeriod += amount;
    collections.putIfAbsent(uid, () => []).add((date, amount));
  }
  for (final h in handovers) {
    if (h.bookerUid.isEmpty || h.amount <= 0) continue;
    final b = of(h.bookerUid);
    if (h.bookerName.isNotEmpty && b.name == 'Booker') b.name = h.bookerName; // no login copy any more
    b.handedOver += h.amount;
    if (inPeriod(h.date)) b.handedInPeriod += h.amount;
    if (b.lastHandover == null || h.date.isAfter(b.lastHandover!)) b.lastHandover = h.date;
  }
  // Handovers clear the oldest collections first.
  for (final b in byUid.values) {
    final list = (collections[b.uid] ?? [])..sort((x, y) => x.$1.compareTo(y.$1));
    var paid = b.handedOver;
    for (final (date, amount) in list) {
      if (paid >= amount - 0.5) {
        paid -= amount;
        continue;
      }
      b.oldestUnhanded = date;
      break;
    }
  }
  return byUid.values.toList()..sort((a, b) => b.holding.compareTo(a.holding));
}

/// Reads payments, handovers and booker names.
Future<(List<Map<String, dynamic>>, List<Handover>, Map<String, String>)> loadHandoverData() async {
  final results = await Future.wait<Object?>([
    companyCol('khata_entries').where('type', isEqualTo: 'payment').get(),
    companyCol('cash_handovers').get(),
    companyCol('sessions').get().then<QuerySnapshot<Map<String, dynamic>>?>((s) => s, onError: (_) => null),
  ]);
  final payments = (results[0] as QuerySnapshot<Map<String, dynamic>>).docs.map((d) => d.data()).toList();
  final handovers = [
    for (final d in (results[1] as QuerySnapshot<Map<String, dynamic>>).docs) Handover.fromMap(d.id, d.data()),
  ]..sort((a, b) => b.date.compareTo(a.date));
  final names = <String, String>{};
  for (final d in (results[2] as QuerySnapshot<Map<String, dynamic>>?)?.docs ?? const []) {
    final m = d.data();
    final n = (m['username'] ?? m['email'] ?? '').toString().trim();
    if (n.isNotEmpty) names[(m['uid'] ?? d.id).toString()] = n;
  }
  try {
    for (final u in await loadCompanyUsers()) {
      names.putIfAbsent(u.uid, () => u.display);
    }
  } catch (e) {
    debugPrint('Handover: names not read: $e');
  }
  return (payments, handovers, names);
}

Future<void> saveHandover(Handover h) async {
  final data = {
    'userId': h.bookerUid,
    'bookerName': h.bookerName,
    'amount': h.amount,
    'date': Timestamp.fromDate(DateTime(h.date.year, h.date.month, h.date.day, 12)),
    'into': h.into.name,
    'note': h.note.trim(),
    'updatedAt': FieldValue.serverTimestamp(),
  };
  if (h.id == null) {
    await companyCol('cash_handovers').add({
      ...data,
      'createdAt': FieldValue.serverTimestamp(),
      'receivedBy': FirebaseAuth.instance.currentUser?.uid ?? '',
      'receivedByName': Account.user?.display ?? '',
    });
  } else {
    await companyCol('cash_handovers').doc(h.id).update(data);
  }
}

Future<void> deleteHandover(String id) => companyCol('cash_handovers').doc(id).delete();
