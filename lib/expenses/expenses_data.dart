// The company's running expenses (rent, fuel, salaries paid in cash, loading, bills...), kept in
// `expenses`. Admins only (see firestore.rules). Profit & loss subtracts these from gross profit.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../account/account.dart';
import '../audit/audit.dart';

/// Categories offered by default; any other category typed in is kept and offered again.
const defaultExpenseCategories = [
  'Salaries & wages',
  'Rent',
  'Fuel',
  'Vehicle repair',
  'Loading & labour',
  'Freight & delivery',
  'Electricity & gas',
  'Mobile & internet',
  'Office & stationery',
  'Tea & entertainment',
  'Taxes & fees',
  'Repairs & maintenance',
  'Other',
];

const expenseMethods = ['Cash', 'Bank', 'JazzCash / EasyPaisa', 'Cheque'];

IconData expenseIcon(String category) => switch (category) {
      'Salaries & wages' => Icons.badge_outlined,
      'Rent' => Icons.home_work_outlined,
      'Fuel' => Icons.local_gas_station_outlined,
      'Vehicle repair' => Icons.car_repair_outlined,
      'Loading & labour' => Icons.inventory_2_outlined,
      'Freight & delivery' => Icons.local_shipping_outlined,
      'Electricity & gas' => Icons.bolt_outlined,
      'Mobile & internet' => Icons.wifi_outlined,
      'Office & stationery' => Icons.edit_note_outlined,
      'Tea & entertainment' => Icons.coffee_outlined,
      'Taxes & fees' => Icons.account_balance_outlined,
      'Repairs & maintenance' => Icons.build_outlined,
      _ => Icons.receipt_outlined,
    };

class Expense {
  final String? id;
  final DateTime date;
  final String category;
  final double amount;
  final String method;
  final String paidTo;
  final String note;

  const Expense({
    this.id,
    required this.date,
    required this.category,
    required this.amount,
    this.method = 'Cash',
    this.paidTo = '',
    this.note = '',
  });

  factory Expense.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? const {};
    final ts = m['date'];
    return Expense(
      id: d.id,
      date: ts is Timestamp ? ts.toDate() : DateTime.now(),
      category: (m['category'] ?? 'Other').toString(),
      amount: (num.tryParse('${m['amount'] ?? 0}') ?? 0).toDouble(),
      method: (m['method'] ?? 'Cash').toString(),
      paidTo: (m['paidTo'] ?? '').toString(),
      note: (m['note'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toMap() => {
        'date': Timestamp.fromDate(DateTime(date.year, date.month, date.day, 12)),
        'category': category.trim().isEmpty ? 'Other' : category.trim(),
        'amount': amount,
        'method': method,
        'paidTo': paidTo.trim(),
        'note': note.trim(),
      };
}

/// Totals for a set of expenses (usually one month).
class ExpenseSummary {
  final double total;
  final int count;
  final List<MapEntry<String, double>> byCategory; // biggest first
  final Map<String, double> byMethod;

  const ExpenseSummary(this.total, this.count, this.byCategory, this.byMethod);

  factory ExpenseSummary.of(Iterable<Expense> list) {
    var total = 0.0;
    var count = 0;
    final cat = <String, double>{};
    final method = <String, double>{};
    for (final e in list) {
      total += e.amount;
      count++;
      cat[e.category] = (cat[e.category] ?? 0) + e.amount;
      method[e.method] = (method[e.method] ?? 0) + e.amount;
    }
    final byCat = cat.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return ExpenseSummary(total, count, byCat, method);
  }
}

DateTime monthStart(DateTime d) => DateTime(d.year, d.month);
DateTime nextMonth(DateTime d) => DateTime(d.year, d.month + 1);

Query<Map<String, dynamic>> _between(DateTime from, DateTime to) => companyCol('expenses')
    .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(from))
    .where('date', isLessThan: Timestamp.fromDate(to))
    .orderBy('date', descending: true);

/// Expenses from [from] up to (not including) [to], newest first, kept up to date.
Stream<List<Expense>> watchExpenses(DateTime from, DateTime to) =>
    _between(from, to).snapshots().map((s) => s.docs.map(Expense.fromDoc).toList());

/// Expenses from [from] up to (not including) [to], read once.
Future<List<Expense>> loadExpenses(DateTime from, DateTime to) async =>
    (await _between(from, to).get()).docs.map(Expense.fromDoc).toList();

Future<void> saveExpense(Expense e) async {
  final data = {
    ...e.toMap(),
    'updatedAt': FieldValue.serverTimestamp(),
  };
  if (e.id == null) {
    await companyCol('expenses').add({
      ...data,
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': FirebaseAuth.instance.currentUser?.uid ?? '',
      'createdByName': Account.user?.display ?? '',
    });
  } else {
    final before = (await companyCol('expenses').doc(e.id).get()).data();
    await companyCol('expenses').doc(e.id).update(data);
    final diff = fieldChanges(before, data, _expenseLabels);
    if (diff.isNotEmpty) {
      await logAudit(
          area: AuditArea.expense, action: AuditAction.edit, refId: e.id!, title: 'Expense · ${e.category}', amount: e.amount, changes: diff);
    }
  }
}

const _expenseLabels = {
  'date': 'Date',
  'category': 'Category',
  'amount': 'Amount',
  'method': 'Paid by',
  'paidTo': 'Paid to',
  'note': 'Note',
};

Future<void> deleteExpense(String id) async {
  final before = (await companyCol('expenses').doc(id).get()).data();
  await companyCol('expenses').doc(id).delete();
  await logAudit(
    area: AuditArea.expense,
    action: AuditAction.delete,
    refId: id,
    title: 'Expense · ${before?['category'] ?? ''}',
    amount: (num.tryParse('${before?['amount'] ?? 0}') ?? 0).toDouble(),
    changes: [
      for (final e in _expenseLabels.entries)
        if (e.key != 'amount' && auditValue(before?[e.key]).isNotEmpty) AuditChange(e.value, auditValue(before?[e.key]), ''),
    ],
  );
}
