// Cheques from shops. A cheque isn't money until it clears, so:
//   in hand   → recorded by the booker or office; the shop still owes the amount
//   deposited → the office put it in the bank
//   cleared   → the money came: a khata payment (method "Cheque") is made then, dated that day
//   bounced   → nothing comes off the khata; a bounce charge can be added to it as udhaar
//   returned  → given back to the shop (e.g. replaced by cash)
//
//   cheques/{id}: customer, userId, userEmail, bank, number, amount, chequeDate, receivedOn,
//                 status, depositedOn, clearedOn, bouncedOn, bounceReason, bounceCharge,
//                 khataEntryId, note, createdAt, createdBy
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

import '../account/account.dart';
import '../audit/audit.dart';

enum ChequeStatus { inHand, deposited, cleared, bounced, returned }

extension ChequeStatusX on ChequeStatus {
  String get label => switch (this) {
        ChequeStatus.inHand => 'In hand',
        ChequeStatus.deposited => 'Deposited',
        ChequeStatus.cleared => 'Cleared',
        ChequeStatus.bounced => 'Bounced',
        ChequeStatus.returned => 'Returned',
      };

  /// Still waiting to become money.
  bool get open => this == ChequeStatus.inHand || this == ChequeStatus.deposited;
}

double _n(dynamic v) => (num.tryParse('${v ?? 0}') ?? 0).toDouble();
DateTime? _d(dynamic v) => v is Timestamp ? v.toDate() : null;
DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);
final _fmt = DateFormat('d MMM yyyy');

class Cheque {
  final String id;
  final String customer;
  final String userId; // the booker whose khata the shop is in
  final String userEmail;
  final String bank;
  final String number;
  final double amount;
  final DateTime chequeDate; // the date written on it (it can't be cashed before)
  final DateTime receivedOn;
  final ChequeStatus status;
  final DateTime? depositedOn;
  final DateTime? clearedOn;
  final DateTime? bouncedOn;
  final String bounceReason;
  final double bounceCharge;
  final String note;

  const Cheque({
    required this.id,
    required this.customer,
    required this.userId,
    this.userEmail = '',
    required this.bank,
    required this.number,
    required this.amount,
    required this.chequeDate,
    required this.receivedOn,
    this.status = ChequeStatus.inHand,
    this.depositedOn,
    this.clearedOn,
    this.bouncedOn,
    this.bounceReason = '',
    this.bounceCharge = 0,
    this.note = '',
  });

  factory Cheque.fromMap(String id, Map<String, dynamic> m) => Cheque(
        id: id,
        customer: '${m['customer'] ?? ''}',
        userId: '${m['userId'] ?? ''}',
        userEmail: '${m['userEmail'] ?? ''}',
        bank: '${m['bank'] ?? ''}',
        number: '${m['number'] ?? ''}',
        amount: _n(m['amount']),
        chequeDate: _d(m['chequeDate']) ?? DateTime(2000),
        receivedOn: _d(m['receivedOn']) ?? _d(m['chequeDate']) ?? DateTime(2000),
        status: ChequeStatus.values.where((s) => s.name == m['status']).firstOrNull ?? ChequeStatus.inHand,
        depositedOn: _d(m['depositedOn']),
        clearedOn: _d(m['clearedOn']),
        bouncedOn: _d(m['bouncedOn']),
        bounceReason: '${m['bounceReason'] ?? ''}',
        bounceCharge: _n(m['bounceCharge']),
        note: '${m['note'] ?? ''}',
      );

  /// Days until the date on the cheque (negative: it can be deposited already).
  int daysToDate(DateTime today) => _day(chequeDate).difference(_day(today)).inDays;

  /// In hand and its date has come: time to deposit it.
  bool dueToDeposit(DateTime today) => status == ChequeStatus.inHand && daysToDate(today) <= 0;

  String get title => '${bank.isEmpty ? 'Cheque' : bank} #$number';
}

/// The figures at the top of the cheques page.
class ChequeSummary {
  final int inHand;
  final double inHandAmount;
  final int due; // in hand with today's date or earlier
  final double dueAmount;
  final int deposited;
  final double depositedAmount;
  final int bounced; // this month
  final double bouncedAmount;
  const ChequeSummary(this.inHand, this.inHandAmount, this.due, this.dueAmount, this.deposited, this.depositedAmount,
      this.bounced, this.bouncedAmount);

  factory ChequeSummary.of(Iterable<Cheque> all, DateTime today) {
    final inHand = all.where((c) => c.status == ChequeStatus.inHand).toList();
    final due = inHand.where((c) => c.dueToDeposit(today)).toList();
    final dep = all.where((c) => c.status == ChequeStatus.deposited).toList();
    final bounced = all
        .where((c) => c.status == ChequeStatus.bounced && c.bouncedOn != null && c.bouncedOn!.year == today.year && c.bouncedOn!.month == today.month)
        .toList();
    double sum(List<Cheque> l) => l.fold(0.0, (s, c) => s + c.amount);
    return ChequeSummary(inHand.length, sum(inHand), due.length, sum(due), dep.length, sum(dep), bounced.length, sum(bounced));
  }
}

CollectionReference<Map<String, dynamic>> get _col => companyCol('cheques');

/// Every cheque, latest date first (the office's list).
Future<List<Cheque>> loadCheques() async {
  final snap = await _col.orderBy('chequeDate', descending: true).limit(1000).get();
  return [for (final d in snap.docs) Cheque.fromMap(d.id, d.data())];
}

/// A shop's cheques that haven't cleared yet, in [userId]'s khata.
Future<List<Cheque>> loadOpenChequesFor(String customer, String userId) async {
  final snap = await _col.where('userId', isEqualTo: userId).where('customer', isEqualTo: customer.trim()).get();
  return [for (final d in snap.docs) Cheque.fromMap(d.id, d.data())].where((c) => c.status.open).toList()
    ..sort((a, b) => a.chequeDate.compareTo(b.chequeDate));
}

/// Records a cheque received from a shop, in [userId]'s khata (the signed-in user by default).
Future<void> addCheque({
  required String customer,
  required String bank,
  required String number,
  required double amount,
  required DateTime chequeDate,
  required DateTime receivedOn,
  String note = '',
  String? userId,
  String? userEmail,
}) async {
  final me = FirebaseAuth.instance.currentUser;
  await _col.add({
    'customer': customer.trim(),
    'userId': userId ?? me?.uid ?? '',
    'userEmail': userEmail ?? me?.email ?? '',
    'bank': bank.trim(),
    'number': number.trim(),
    'amount': amount,
    'chequeDate': Timestamp.fromDate(_day(chequeDate)),
    'receivedOn': Timestamp.fromDate(_day(receivedOn)),
    'status': ChequeStatus.inHand.name,
    'note': note.trim(),
    'createdAt': FieldValue.serverTimestamp(),
    'createdBy': me?.uid ?? '',
  });
}

Future<void> _log(Cheque c, String action, String what, {String reason = ''}) => logAudit(
      area: AuditArea.cheque,
      action: action,
      refId: c.id,
      title: '${c.title} · ${c.customer}',
      amount: c.amount,
      changes: [AuditChange('Status', c.status.label, what)],
      reason: reason,
    );

/// Put in the bank on [day].
Future<void> depositCheque(Cheque c, DateTime day) async {
  await _col.doc(c.id).update({'status': ChequeStatus.deposited.name, 'depositedOn': Timestamp.fromDate(_day(day))});
  await _log(c, AuditAction.edit, 'Deposited ${_fmt.format(day)}');
}

/// The money came on [day]: the shop's khata gets the payment.
Future<void> clearCheque(Cheque c, DateTime day) async {
  final batch = FirebaseFirestore.instance.batch();
  final entry = companyCol('khata_entries').doc();
  batch.set(entry, {
    'userId': c.userId,
    'userEmail': c.userEmail,
    'customer': c.customer,
    'type': 'payment',
    'amount': c.amount,
    'method': 'Cheque',
    'note': '${c.title}${c.note.isEmpty ? '' : ' · ${c.note}'}',
    'date': Timestamp.fromDate(_day(day)),
    'chequeId': c.id,
    'createdAt': FieldValue.serverTimestamp(),
  });
  batch.update(_col.doc(c.id), {
    'status': ChequeStatus.cleared.name,
    'clearedOn': Timestamp.fromDate(_day(day)),
    'khataEntryId': entry.id,
  });
  await batch.commit();
  await _log(c, AuditAction.edit, 'Cleared ${_fmt.format(day)}');
}

/// The bank returned it unpaid on [day]. The shop still owes the amount; [charge] (the bank's
/// fee, or a penalty) is added to its khata as udhaar.
Future<void> bounceCheque(Cheque c, DateTime day, {required String reason, double charge = 0}) async {
  final batch = FirebaseFirestore.instance.batch();
  batch.update(_col.doc(c.id), {
    'status': ChequeStatus.bounced.name,
    'bouncedOn': Timestamp.fromDate(_day(day)),
    'bounceReason': reason.trim(),
    'bounceCharge': charge,
  });
  if (charge > 0) {
    batch.set(companyCol('khata_entries').doc(), {
      'userId': c.userId,
      'userEmail': c.userEmail,
      'customer': c.customer,
      'type': 'udhaar',
      'amount': charge,
      'method': '',
      'note': 'Bounced cheque charge · ${c.title}',
      'date': Timestamp.fromDate(_day(day)),
      'chequeId': c.id,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
  await batch.commit();
  await _log(c, AuditAction.edit, 'Bounced ${_fmt.format(day)}${charge > 0 ? ', charge ${charge.round()}' : ''}', reason: reason);
}

/// Given back to the shop (paid another way, or written wrong).
Future<void> returnCheque(Cheque c, {String reason = ''}) async {
  await _col.doc(c.id).update({'status': ChequeStatus.returned.name, 'note': [c.note, reason.trim()].where((s) => s.isNotEmpty).join(' · ')});
  await _log(c, AuditAction.edit, 'Returned to the shop', reason: reason);
}

/// Removes a cheque entered by mistake (only before it clears).
Future<void> deleteCheque(Cheque c) async {
  await _col.doc(c.id).delete();
  await logAudit(
    area: AuditArea.cheque,
    action: AuditAction.delete,
    refId: c.id,
    title: '${c.title} · ${c.customer}',
    amount: c.amount,
    changes: [AuditChange('Cheque date', _fmt.format(c.chequeDate), ''), AuditChange('Status', c.status.label, '')],
  );
}
