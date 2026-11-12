// Monthly targets for bookers: a sales target and a recovery target per booker per month, set by
// the office (`targets`, one document per booker per month: "2026-11__uid"). Achievement comes from
// what is already recorded: invoices for sales, khata payments and office recoveries for recovery.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

import '../account/account.dart';

final _monthKey = DateFormat('yyyy-MM');

String monthKey(DateTime month) => _monthKey.format(month);
String targetDocId(DateTime month, String uid) => '${monthKey(month)}__$uid';

class BookerTarget {
  final String uid;
  final double sales;
  final double recovery;
  const BookerTarget(this.uid, {this.sales = 0, this.recovery = 0});

  bool get isSet => sales > 0 || recovery > 0;
}

enum Pace { none, ahead, onTrack, behind, done }

/// One figure against its target, and whether it is keeping up with the month so far.
class TargetProgress {
  final double target;
  final double achieved;
  final double monthShare; // how much of the month has gone, 0..1

  const TargetProgress(this.target, this.achieved, this.monthShare);

  double get pct => target <= 0 ? 0 : achieved / target * 100;
  double get left => target - achieved > 0 ? target - achieved : 0;

  /// Done: reached. Ahead or behind: against where it should be by now (5 points either way
  /// counts as on track).
  Pace get pace {
    if (target <= 0) return Pace.none;
    if (achieved >= target - 0.5) return Pace.done;
    final expected = monthShare * 100;
    if (pct >= expected + 5) return Pace.ahead;
    if (pct >= expected - 5) return Pace.onTrack;
    return Pace.behind;
  }

  /// What is needed per remaining day to reach the target ([daysLeft] including today).
  double perDayNeeded(int daysLeft) => daysLeft <= 0 ? left : left / daysLeft;
}

/// How much of [month] has gone by [today]: 1 for a past month, 0 for a future one.
double monthShare(DateTime month, DateTime today) {
  final start = DateTime(month.year, month.month);
  final days = DateTime(month.year, month.month + 1, 0).day;
  final t = DateTime(today.year, today.month, today.day);
  if (t.isBefore(start)) return 0;
  if (!t.isBefore(DateTime(month.year, month.month + 1))) return 1;
  return t.day / days; // today counts as gone, so the last day of the month is 100%
}

/// Days left in [month] from [today] (today included); 0 for a past month.
int daysLeft(DateTime month, DateTime today) {
  final end = DateTime(month.year, month.month + 1, 0);
  final t = DateTime(today.year, today.month, today.day);
  if (t.isAfter(end)) return 0;
  final start = DateTime(month.year, month.month);
  return end.difference(t.isBefore(start) ? start : t).inDays + 1;
}

/// One booker's month.
class BookerMonth {
  final String uid;
  final String name;
  final BookerTarget target;
  final double sales;
  final double recovery;
  final int invoices;

  const BookerMonth({
    required this.uid,
    required this.name,
    required this.target,
    required this.sales,
    required this.recovery,
    required this.invoices,
  });

  TargetProgress salesProgress(double share) => TargetProgress(target.sales, sales, share);
  TargetProgress recoveryProgress(double share) => TargetProgress(target.recovery, recovery, share);
}

double _n(dynamic v) => (num.tryParse('${v ?? 0}') ?? 0).toDouble();

/// Sales and recovery per booker uid for the month, from raw records.
(Map<String, double>, Map<String, int>, Map<String, double>) achievedFrom({
  List<Map<String, dynamic>> invoices = const [],
  List<Map<String, dynamic>> khataEntries = const [],
  List<Map<String, dynamic>> officeRecoveries = const [],
}) {
  final sales = <String, double>{};
  final count = <String, int>{};
  final rec = <String, double>{};
  for (final m in invoices) {
    final uid = (m['userId'] ?? '').toString();
    sales[uid] = (sales[uid] ?? 0) + _n(m['grandTotal'] ?? m['total']);
    count[uid] = (count[uid] ?? 0) + 1;
  }
  for (final m in khataEntries) {
    if (m['type'] != 'payment') continue;
    final uid = (m['userId'] ?? '').toString();
    rec[uid] = (rec[uid] ?? 0) + _n(m['amount']);
  }
  for (final m in officeRecoveries) {
    final uid = (m['userId'] ?? '').toString();
    rec[uid] = (rec[uid] ?? 0) + _n(m['amountPaid']);
  }
  return (sales, count, rec);
}

Future<List<Map<String, dynamic>>> _maps(Query<Map<String, dynamic>> q) async {
  try {
    return (await q.get()).docs.map((d) => d.data()).toList();
  } catch (_) {
    return const []; // a module the company doesn't have
  }
}

/// Every booker's month: their targets and what they achieved.
Future<List<BookerMonth>> loadTargetBoard(DateTime month) async {
  final start = DateTime(month.year, month.month);
  final end = DateTime(month.year, month.month + 1);
  final day = DateFormat('yyyy-MM-dd');
  final results = await Future.wait<Object?>([
    _maps(companyCol('invoices')
        .where('salesDateTs', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('salesDateTs', isLessThan: Timestamp.fromDate(end))),
    _maps(companyCol('khata_entries')
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('date', isLessThan: Timestamp.fromDate(end))),
    _maps(companyCol('customer_recoveries')
        .where('dateStr', isGreaterThanOrEqualTo: day.format(start))
        .where('dateStr', isLessThan: day.format(end))),
    companyCol('targets').where('month', isEqualTo: monthKey(month)).get(),
    companyCol('sessions').get(),
    bookerFilter(),
  ]);
  final (sales, count, rec) = achievedFrom(
    invoices: results[0] as List<Map<String, dynamic>>,
    khataEntries: results[1] as List<Map<String, dynamic>>,
    officeRecoveries: results[2] as List<Map<String, dynamic>>,
  );
  final targets = <String, BookerTarget>{
    for (final d in (results[3] as QuerySnapshot<Map<String, dynamic>>).docs)
      (d.data()['userId'] ?? '').toString(): BookerTarget(
        (d.data()['userId'] ?? '').toString(),
        sales: _n(d.data()['sales']),
        recovery: _n(d.data()['recovery']),
      ),
  };
  final isBooker = results[5] as bool Function(String, String);
  final out = <BookerMonth>[];
  for (final s in (results[4] as QuerySnapshot<Map<String, dynamic>>).docs) {
    final m = s.data();
    final uid = (m['uid'] ?? s.id).toString();
    if (!isBooker(uid, (m['email'] ?? '').toString())) continue;
    final name = (m['username'] ?? m['email'] ?? 'Booker').toString().trim();
    out.add(BookerMonth(
      uid: uid,
      name: name.isEmpty ? 'Booker' : name,
      target: targets[uid] ?? BookerTarget(uid),
      sales: sales[uid] ?? 0,
      recovery: rec[uid] ?? 0,
      invoices: count[uid] ?? 0,
    ));
  }
  out.sort((a, b) => b.sales.compareTo(a.sales));
  return out;
}

Future<void> saveTarget(DateTime month, String uid, {required double sales, required double recovery}) =>
    companyCol('targets').doc(targetDocId(month, uid)).set({
      'month': monthKey(month),
      'userId': uid,
      'sales': sales,
      'recovery': recovery,
      'updatedAt': FieldValue.serverTimestamp(),
      'setBy': FirebaseAuth.instance.currentUser?.uid ?? '',
    });

/// Copies last month's targets to [month] for bookers who have none yet. Returns how many.
Future<int> copyLastMonthTargets(DateTime month, Iterable<BookerMonth> bookers) async {
  final prev = DateTime(month.year, month.month - 1);
  final snap = await companyCol('targets').where('month', isEqualTo: monthKey(prev)).get();
  final last = {for (final d in snap.docs) (d.data()['userId'] ?? '').toString(): d.data()};
  var copied = 0;
  for (final b in bookers) {
    if (b.target.isSet) continue;
    final t = last[b.uid];
    if (t == null) continue;
    await saveTarget(month, b.uid, sales: _n(t['sales']), recovery: _n(t['recovery']));
    copied++;
  }
  return copied;
}

/// The signed-in booker's own target for [month] (null when none is set).
Future<BookerTarget?> loadMyTarget(DateTime month) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return null;
  try {
    final d = await companyCol('targets').doc(targetDocId(month, uid)).get();
    if (!d.exists) return null;
    final t = BookerTarget(uid, sales: _n(d.data()?['sales']), recovery: _n(d.data()?['recovery']));
    return t.isSet ? t : null;
  } catch (_) {
    return null;
  }
}

/// The signed-in booker's recoveries this month (their khata payments).
Future<double> loadMyRecovery(DateTime month) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return 0;
  final start = DateTime(month.year, month.month);
  final end = DateTime(month.year, month.month + 1);
  final list = await _maps(companyCol('khata_entries').where('userId', isEqualTo: uid));
  return list.where((m) {
    final ts = m['date'];
    if (m['type'] != 'payment' || ts is! Timestamp) return false;
    final d = ts.toDate();
    return !d.isBefore(start) && d.isBefore(end);
  }).fold<double>(0, (s, m) => s + _n(m['amount']));
}
