// Audit log and closed books.
//
// Audit log: every edit or delete of money and stock records (invoices, payments, expenses, cash
// entries, purchases, stock counts, returns, trips, product prices) is written down with who did
// it, when, what changed and, for a locked record, why. Nobody can change or delete the log (the
// rules allow only adding to it), and only admins read it.
//
//   audit_log/{id}: at, by, byName, area, action, refId, title, amount, changes [{field, from, to}],
//                   reason
//
// Closed books: the admin closes the books up to a date (companies/{id}.booksClosedUntil, the end
// of that day). Nothing dated on or before it can be added, changed or deleted any more, by anyone:
// the rules refuse it on the server too. Reopening is an admin action that is logged.
//
// Paid or delivered invoices are locked softly: changing or deleting one needs a reason, which
// goes into the log.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../account/account.dart';
import '../ui/app_theme.dart';

enum AuditArea { invoice, payment, expense, cash, stock, purchase, returns, trip, product, books, cheque }

extension AuditAreaX on AuditArea {
  String get label => switch (this) {
        AuditArea.invoice => 'Invoices',
        AuditArea.payment => 'Khata',
        AuditArea.expense => 'Expenses',
        AuditArea.cash => 'Cash book',
        AuditArea.stock => 'Stock',
        AuditArea.purchase => 'Purchases',
        AuditArea.returns => 'Returns',
        AuditArea.trip => 'Deliveries',
        AuditArea.product => 'Products',
        AuditArea.books => 'Closed books',
        AuditArea.cheque => 'Cheques',
      };

  IconData get icon => switch (this) {
        AuditArea.invoice => Icons.receipt_long_outlined,
        AuditArea.payment => Icons.menu_book_outlined,
        AuditArea.expense => Icons.receipt_outlined,
        AuditArea.cash => Icons.account_balance_outlined,
        AuditArea.stock => Icons.inventory_2_outlined,
        AuditArea.purchase => Icons.shopping_cart_outlined,
        AuditArea.returns => Icons.assignment_return_outlined,
        AuditArea.trip => Icons.local_shipping_outlined,
        AuditArea.product => Icons.sell_outlined,
        AuditArea.books => Icons.lock_outline,
        AuditArea.cheque => Icons.money_outlined,
      };
}

/// What was done: the words used in the log.
abstract final class AuditAction {
  static const edit = 'edit';
  static const delete = 'delete';
  static const create = 'create';
  static const close = 'close';
  static const reopen = 'reopen';

  static String label(String a) => switch (a) {
        edit => 'Changed',
        delete => 'Deleted',
        create => 'Added',
        close => 'Closed',
        reopen => 'Reopened',
        _ => a,
      };
}

/// One changed value: "Soap qty: 10 → 12".
class AuditChange {
  final String field;
  final String from;
  final String to;
  const AuditChange(this.field, this.from, this.to);

  factory AuditChange.fromMap(Map m) =>
      AuditChange((m['field'] ?? '').toString(), (m['from'] ?? '').toString(), (m['to'] ?? '').toString());
  Map<String, String> toMap() => {'field': field, 'from': from, 'to': to};

  @override
  String toString() => from.isEmpty
      ? '$field: $to'
      : to.isEmpty
          ? '$field: $from'
          : '$field: $from → $to';

  @override
  bool operator ==(Object other) => other is AuditChange && other.field == field && other.from == from && other.to == to;
  @override
  int get hashCode => Object.hash(field, from, to);
}

final _day = DateFormat('d MMM yyyy');

/// A value as the log shows it: dates as "5 Nov 2026", numbers without ".0".
String auditValue(dynamic v) {
  if (v == null) return '';
  if (v is Timestamp) return _day.format(v.toDate());
  if (v is DateTime) return _day.format(v);
  if (v is num) return v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(2);
  final s = v.toString().trim();
  final n = num.tryParse(s);
  return n != null ? auditValue(n) : s;
}

/// What changed among [labels]' fields (field name → how the log names it).
List<AuditChange> fieldChanges(Map<String, dynamic>? before, Map<String, dynamic> after, Map<String, String> labels) => [
      for (final e in labels.entries)
        if (after.containsKey(e.key) && auditValue(before?[e.key]) != auditValue(after[e.key]))
          AuditChange(e.value, auditValue(before?[e.key]), auditValue(after[e.key])),
    ];

/// What changed in an invoice's product lines, by product: quantity, price, free goods, added or
/// removed lines.
List<AuditChange> itemChanges(List? before, List? after) {
  Map<String, Map> byName(List? items) => {
        for (final it in items ?? const [])
          if (it is Map && (it['Product Name'] ?? '').toString().trim().isNotEmpty)
            (it['Product Name'] ?? '').toString().trim().toLowerCase(): it,
      };
  String name(Map it) => (it['Product Name'] ?? '').toString().trim();
  final was = byName(before), now = byName(after);
  final out = <AuditChange>[];
  for (final k in {...was.keys, ...now.keys}) {
    final a = was[k], b = now[k];
    if (a == null) {
      out.add(AuditChange(name(b!), '', 'added, qty ${auditValue(b['QTY'] ?? 0)}'));
    } else if (b == null) {
      out.add(AuditChange(name(a), 'removed, was qty ${auditValue(a['QTY'] ?? 0)}', ''));
    } else {
      for (final (key, label) in const [('QTY', 'qty'), ('TP', 'price'), ('BNS', 'free')]) {
        final x = auditValue(a[key] ?? 0), y = auditValue(b[key] ?? 0);
        if (x != y) out.add(AuditChange('${name(b)} $label', x, y));
      }
    }
  }
  return out;
}

/// Writes one line to the log. Never throws: the change itself has already been saved.
Future<void> logAudit({
  required AuditArea area,
  required String action,
  required String refId,
  required String title,
  double? amount,
  List<AuditChange> changes = const [],
  String reason = '',
}) async {
  try {
    await companyCol('audit_log').add({
      'at': FieldValue.serverTimestamp(),
      'by': FirebaseAuth.instance.currentUser?.uid ?? '',
      'byName': Account.user?.display ?? FirebaseAuth.instance.currentUser?.email ?? '',
      'area': area.name,
      'action': action,
      'refId': refId,
      'title': title,
      'amount': ?amount,
      'changes': [for (final c in changes) c.toMap()],
      'reason': reason.trim(),
    });
  } catch (e) {
    debugPrint('Audit log: $e');
  }
}

class AuditEntry {
  final String id;
  final DateTime at;
  final String by;
  final String byName;
  final AuditArea area;
  final String action;
  final String refId;
  final String title;
  final double? amount;
  final List<AuditChange> changes;
  final String reason;

  const AuditEntry({
    required this.id,
    required this.at,
    required this.by,
    required this.byName,
    required this.area,
    required this.action,
    required this.refId,
    required this.title,
    this.amount,
    this.changes = const [],
    this.reason = '',
  });

  factory AuditEntry.fromMap(String id, Map<String, dynamic> m) => AuditEntry(
        id: id,
        at: m['at'] is Timestamp ? (m['at'] as Timestamp).toDate() : DateTime.now(),
        by: (m['by'] ?? '').toString(),
        byName: (m['byName'] ?? '').toString(),
        area: AuditArea.values.where((a) => a.name == m['area']).firstOrNull ?? AuditArea.invoice,
        action: (m['action'] ?? '').toString(),
        refId: (m['refId'] ?? '').toString(),
        title: (m['title'] ?? '').toString(),
        amount: m['amount'] is num ? (m['amount'] as num).toDouble() : null,
        changes: [for (final c in (m['changes'] as List? ?? const [])) if (c is Map) AuditChange.fromMap(c)],
        reason: (m['reason'] ?? '').toString(),
      );
}

/// The log from [from] up to (not including) [to], newest first.
Future<List<AuditEntry>> loadAudit(DateTime from, DateTime to) async {
  final snap = await companyCol('audit_log')
      .where('at', isGreaterThanOrEqualTo: Timestamp.fromDate(from))
      .where('at', isLessThan: Timestamp.fromDate(to))
      .orderBy('at', descending: true)
      .get();
  return [for (final d in snap.docs) AuditEntry.fromMap(d.id, d.data())];
}

// =============================================================================
// Closed books
// =============================================================================

DateTime? _closedUntil;
bool _closedLoaded = false;

/// The last day of the closed books (null = nothing closed).
Future<DateTime?> booksClosedUntil({bool fresh = false}) async {
  if (_closedLoaded && !fresh) return _closedUntil;
  final id = Account.companyId;
  if (id == null) return null;
  try {
    final d = await FirebaseFirestore.instance.collection('companies').doc(id).get();
    final v = d.data()?['booksClosedUntil'];
    _closedUntil = v is Timestamp ? v.toDate() : null;
    _closedLoaded = true;
  } catch (e) {
    debugPrint('Closed books: $e');
  }
  return _closedUntil;
}

/// Whether [day] falls in the closed books (on or before [until]).
bool isClosedPeriod(DateTime? day, DateTime? until) {
  if (day == null || until == null) return false;
  final end = DateTime(until.year, until.month, until.day).add(const Duration(days: 1));
  return day.isBefore(end);
}

/// Closes the books up to the end of [day], or reopens them all (null). Admins only.
Future<void> setBooksClosedUntil(DateTime? day) async {
  final before = await booksClosedUntil(fresh: true);
  final end = day == null ? null : DateTime(day.year, day.month, day.day, 23, 59, 59);
  await FirebaseFirestore.instance
      .collection('companies')
      .doc(Account.companyId)
      .update({'booksClosedUntil': end == null ? FieldValue.delete() : Timestamp.fromDate(end)});
  _closedUntil = end;
  _closedLoaded = true;
  final reopening = before != null && (end == null || end.isBefore(before));
  await logAudit(
    area: AuditArea.books,
    action: reopening ? AuditAction.reopen : AuditAction.close,
    refId: 'books',
    title: end == null ? 'Books reopened' : 'Books closed up to ${_day.format(end)}',
    changes: [AuditChange('Closed up to', before == null ? 'none' : _day.format(before), end == null ? 'none' : _day.format(end))],
  );
}

/// For a record dated [day]: true if it can still be changed. If the books are closed for that
/// day, says so and returns false.
Future<bool> ensureOpenPeriod(BuildContext context, DateTime? day) async {
  final until = await booksClosedUntil();
  if (!isClosedPeriod(day, until)) return true;
  if (!context.mounted) return false;
  await showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      icon: const Icon(Icons.lock_outline, color: AppColors.navy),
      title: const Text('Books are closed'),
      content: Text(
        'The books are closed up to ${_day.format(until!)}, so records dated ${_day.format(day!)} can\'t be '
        'added, changed or deleted. An admin can reopen them in Accounts → Audit log.',
      ),
      actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
    ),
  );
  return false;
}

// =============================================================================
// Locked invoices
// =============================================================================

enum InvoiceLock { none, paid, delivered, closedPeriod }

/// Why an invoice is locked, if it is. [paid]: the khata shows it fully paid.
InvoiceLock invoiceLock(Map<String, dynamic> data, {bool paid = false, DateTime? closedUntil}) {
  final ts = data['salesDateTs'];
  if (isClosedPeriod(ts is Timestamp ? ts.toDate() : null, closedUntil)) return InvoiceLock.closedPeriod;
  final amount = num.tryParse('${data['grandTotal'] ?? data['total'] ?? 0}') ?? 0;
  if (paid && amount >= 0.5) return InvoiceLock.paid;
  if ((data['deliveryStatus'] ?? '').toString() case 'delivered' || 'partial' || 'returned') return InvoiceLock.delivered;
  return InvoiceLock.none;
}

/// For a paid or delivered invoice: asks why it's being changed. Returns the reason, '' if it isn't
/// locked, or null to stop.
Future<String?> askLockReason(BuildContext context, InvoiceLock lock, {required String doing}) async {
  if (lock == InvoiceLock.none) return '';
  if (lock == InvoiceLock.closedPeriod) return null;
  final ctrl = TextEditingController();
  final why = lock == InvoiceLock.paid ? 'has been paid in full' : 'has been delivered';
  final reason = await showDialog<String>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => AlertDialog(
        icon: const Icon(Icons.lock_outline, color: AppColors.amberDark),
        title: Text('This invoice $why'),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('To $doing it, write why. The reason is kept in the audit log with your name.',
                style: const TextStyle(fontSize: 13, color: AppColors.muted)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Reason'),
              onChanged: (_) => set(() {}),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(
            onPressed: ctrl.text.trim().length < 3 ? null : () => Navigator.pop(c, ctrl.text.trim()),
            child: const Text('Continue'),
          ),
        ],
      ),
    ),
  );
  return reason; // ctrl isn't disposed here: the dialog may still be closing
}
