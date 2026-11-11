// The cash and bank book: every rupee in and out, by where the money is (cash in hand, the bank,
// a mobile wallet), built from what is already recorded:
//   in  — shop payments (khata) and office recoveries
//   out — expenses and payments to suppliers (including money paid with a purchase)
// plus manual entries in `cash_entries` (admins only): opening balances, transfers between
// accounts (e.g. cash deposited in the bank), and other money in or out (capital, drawings).
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../account/account.dart';

enum MoneyAccount { cash, bank, wallet }

extension MoneyAccountX on MoneyAccount {
  String get label => switch (this) {
        MoneyAccount.cash => 'Cash in hand',
        MoneyAccount.bank => 'Bank',
        MoneyAccount.wallet => 'Mobile wallet',
      };
  String get short => switch (this) {
        MoneyAccount.cash => 'Cash',
        MoneyAccount.bank => 'Bank',
        MoneyAccount.wallet => 'Wallet',
      };
  IconData get icon => switch (this) {
        MoneyAccount.cash => Icons.payments_outlined,
        MoneyAccount.bank => Icons.account_balance_outlined,
        MoneyAccount.wallet => Icons.phone_android_outlined,
      };
}

MoneyAccount? _accountNamed(String? s) => MoneyAccount.values.where((a) => a.name == s).firstOrNull;

/// Where money paid by [method] ends up. The forms word methods differently ("Bank transfer",
/// "Online", "JazzCash / EasyPaisa"...); anything not clearly bank or wallet counts as cash.
MoneyAccount accountForMethod(String method) {
  final m = method.toLowerCase();
  if (m.contains('jazz') || m.contains('easypaisa') || m.contains('wallet')) return MoneyAccount.wallet;
  if (m.contains('bank') || m.contains('online') || m.contains('cheque') || m.contains('check')) return MoneyAccount.bank;
  return MoneyAccount.cash;
}

enum CashSource { shopPayment, officeRecovery, expense, supplier, manual }

/// One movement of money in one account. [amount] is positive for money in, negative for out.
class CashLine {
  final DateTime date;
  final MoneyAccount account;
  final double amount;
  final CashSource source;
  final String title;
  final String note;
  final String? entryId; // manual entries: the cash_entries id, so they can be edited

  const CashLine({
    required this.date,
    required this.account,
    required this.amount,
    required this.source,
    required this.title,
    this.note = '',
    this.entryId,
  });

  bool get isIn => amount > 0;
}

/// A manual entry in the book.
enum CashEntryType { opening, moneyIn, moneyOut, transfer }

class CashEntry {
  final String? id;
  final DateTime date;
  final CashEntryType type;
  final MoneyAccount account; // for a transfer: where the money comes from
  final MoneyAccount? toAccount; // transfers only
  final double amount;
  final String note;

  const CashEntry({
    this.id,
    required this.date,
    required this.type,
    required this.account,
    this.toAccount,
    required this.amount,
    this.note = '',
  });

  factory CashEntry.fromMap(String id, Map<String, dynamic> m) => CashEntry(
        id: id,
        date: m['date'] is Timestamp ? (m['date'] as Timestamp).toDate() : DateTime(2000),
        type: CashEntryType.values.where((t) => t.name == m['type']).firstOrNull ?? CashEntryType.moneyIn,
        account: _accountNamed(m['account']) ?? MoneyAccount.cash,
        toAccount: _accountNamed(m['toAccount']),
        amount: (num.tryParse('${m['amount'] ?? 0}') ?? 0).toDouble(),
        note: (m['note'] ?? '').toString(),
      );

  Map<String, dynamic> toMap() => {
        'date': Timestamp.fromDate(DateTime(date.year, date.month, date.day, 12)),
        'type': type.name,
        'account': account.name,
        if (type == CashEntryType.transfer && toAccount != null) 'toAccount': toAccount!.name,
        'amount': amount,
        'note': note.trim(),
      };

  String get typeLabel => switch (type) {
        CashEntryType.opening => 'Opening balance',
        CashEntryType.moneyIn => 'Money in',
        CashEntryType.moneyOut => 'Money out',
        CashEntryType.transfer => 'Transfer',
      };

  List<CashLine> get lines {
    final title = note.isNotEmpty ? note : typeLabel;
    return switch (type) {
      CashEntryType.opening => [
          CashLine(date: date, account: account, amount: amount, source: CashSource.manual, title: 'Opening balance', note: note, entryId: id),
        ],
      CashEntryType.moneyIn => [
          CashLine(date: date, account: account, amount: amount, source: CashSource.manual, title: title, entryId: id),
        ],
      CashEntryType.moneyOut => [
          CashLine(date: date, account: account, amount: -amount, source: CashSource.manual, title: title, entryId: id),
        ],
      CashEntryType.transfer => [
          CashLine(
              date: date,
              account: account,
              amount: -amount,
              source: CashSource.manual,
              title: 'Transfer to ${(toAccount ?? MoneyAccount.bank).label}',
              note: note,
              entryId: id),
          CashLine(
              date: date,
              account: toAccount ?? MoneyAccount.bank,
              amount: amount,
              source: CashSource.manual,
              title: 'Transfer from ${account.label}',
              note: note,
              entryId: id),
        ],
    };
  }
}

double _n(dynamic v) => (num.tryParse('${v ?? 0}') ?? 0).toDouble();
DateTime? _ts(dynamic v) => v is Timestamp ? v.toDate() : (v is DateTime ? v : null);

/// Every movement, oldest first, from the raw records.
List<CashLine> buildCashLines({
  List<Map<String, dynamic>> khataEntries = const [],
  List<Map<String, dynamic>> officeRecoveries = const [],
  List<Map<String, dynamic>> expenses = const [],
  List<Map<String, dynamic>> supplierPayments = const [],
  List<CashEntry> manual = const [],
}) {
  final out = <CashLine>[];
  for (final m in khataEntries) {
    if (m['type'] != 'payment') continue;
    final amount = _n(m['amount']);
    final date = _ts(m['date']) ?? _ts(m['createdAt']);
    if (amount <= 0 || date == null) continue;
    final method = (m['method'] ?? '').toString();
    out.add(CashLine(
      date: date,
      account: accountForMethod(method),
      amount: amount,
      source: method == 'Office recovery' ? CashSource.officeRecovery : CashSource.shopPayment,
      title: 'Payment from ${(m['customer'] ?? 'shop').toString().trim()}',
      note: [if (method.isNotEmpty) method, (m['note'] ?? '').toString().trim()].where((s) => s.isNotEmpty).join(' · '),
    ));
  }
  for (final m in officeRecoveries) {
    final amount = _n(m['amountPaid']);
    DateTime? date;
    try {
      date = DateFormat('yyyy-MM-dd').parseStrict((m['dateStr'] ?? '').toString());
    } catch (_) {
      date = _ts(m['createdAt']);
    }
    if (amount <= 0 || date == null) continue;
    out.add(CashLine(
      date: date,
      account: MoneyAccount.cash,
      amount: amount,
      source: CashSource.officeRecovery,
      title: 'Recovery from ${(m['customerName'] ?? 'shop').toString().trim()}',
      note: 'Office recovery',
    ));
  }
  for (final m in expenses) {
    final amount = _n(m['amount']);
    final date = _ts(m['date']);
    if (amount <= 0 || date == null) continue;
    final paidTo = (m['paidTo'] ?? '').toString().trim();
    final category = (m['category'] ?? 'Expense').toString();
    out.add(CashLine(
      date: date,
      account: accountForMethod((m['method'] ?? '').toString()),
      amount: -amount,
      source: CashSource.expense,
      title: paidTo.isEmpty ? category : '$category · $paidTo',
      note: (m['note'] ?? '').toString().trim(),
    ));
  }
  for (final m in supplierPayments) {
    final amount = _n(m['amount']);
    final date = _ts(m['date']);
    if (amount <= 0 || date == null) continue;
    final method = (m['method'] ?? '').toString();
    out.add(CashLine(
      date: date,
      account: accountForMethod(method),
      amount: -amount,
      source: CashSource.supplier,
      title: 'Paid to ${(m['supplierName'] ?? 'supplier').toString().trim()}',
      note: [if (method.isNotEmpty) method, (m['note'] ?? '').toString().trim()].where((s) => s.isNotEmpty).join(' · '),
    ));
  }
  for (final e in manual) {
    out.addAll(e.lines);
  }
  out.sort((a, b) => a.date.compareTo(b.date));
  return out;
}

/// The book for one period: balances at the start and end, and what came in and went out.
class CashPeriod {
  final DateTime start;
  final DateTime end; // the day after the last
  final Map<MoneyAccount, double> opening;
  final Map<MoneyAccount, double> moneyIn;
  final Map<MoneyAccount, double> moneyOut; // positive numbers
  final List<CashLine> lines; // in the period, oldest first

  const CashPeriod(this.start, this.end, this.opening, this.moneyIn, this.moneyOut, this.lines);

  double closing(MoneyAccount a) => (opening[a] ?? 0) + (moneyIn[a] ?? 0) - (moneyOut[a] ?? 0);
  double get totalClosing => MoneyAccount.values.fold(0, (s, a) => s + closing(a));
  double get totalOpening => MoneyAccount.values.fold(0, (s, a) => s + (opening[a] ?? 0));
  double get totalIn => MoneyAccount.values.fold(0, (s, a) => s + (moneyIn[a] ?? 0));
  double get totalOut => MoneyAccount.values.fold(0, (s, a) => s + (moneyOut[a] ?? 0));

  /// Running balance after each day of the period, for one account (or all when null).
  List<double> dailyBalance([MoneyAccount? a]) {
    var bal = a == null ? totalOpening : (opening[a] ?? 0);
    final days = end.difference(start).inDays.clamp(1, 400);
    final out = <double>[];
    var i = 0;
    for (var d = 0; d < days; d++) {
      final dayEnd = DateTime(start.year, start.month, start.day + d + 1);
      while (i < lines.length && lines[i].date.isBefore(dayEnd)) {
        if (a == null || lines[i].account == a) bal += lines[i].amount;
        i++;
      }
      out.add(bal);
    }
    return out;
  }
}

CashPeriod cashPeriod(List<CashLine> all, DateTime start, DateTime end) {
  final opening = {for (final a in MoneyAccount.values) a: 0.0};
  final inn = {for (final a in MoneyAccount.values) a: 0.0};
  final out = {for (final a in MoneyAccount.values) a: 0.0};
  final lines = <CashLine>[];
  for (final l in all) {
    if (l.date.isBefore(start)) {
      opening[l.account] = opening[l.account]! + l.amount;
    } else if (l.date.isBefore(end)) {
      lines.add(l);
      if (l.amount > 0) {
        inn[l.account] = inn[l.account]! + l.amount;
      } else {
        out[l.account] = out[l.account]! - l.amount;
      }
    }
  }
  return CashPeriod(start, end, opening, inn, out, lines);
}

/// Reads everything the cash book needs (all of it: balances carry forward from the start).
Future<List<CashLine>> loadCashLines() async {
  Future<List<Map<String, dynamic>>> all(Query<Map<String, dynamic>> q) async {
    try {
      return (await q.get()).docs.map((d) => d.data()).toList();
    } catch (e) {
      debugPrint('Cash book: a list was not read: $e'); // e.g. a module the company doesn't have
      return const [];
    }
  }

  final manual = companyCol('cash_entries').get(); // admins only; a failure here should show
  final results = await Future.wait([
    all(companyCol('khata_entries').where('type', isEqualTo: 'payment')),
    all(companyCol('customer_recoveries')),
    all(companyCol('expenses')),
    all(companyCol('supplier_payments')),
  ]);
  return buildCashLines(
    khataEntries: results[0],
    officeRecoveries: results[1],
    expenses: results[2],
    supplierPayments: results[3],
    manual: [for (final d in (await manual).docs) CashEntry.fromMap(d.id, d.data())],
  );
}

Future<CashEntry?> loadCashEntry(String id) async {
  final d = await companyCol('cash_entries').doc(id).get();
  return d.exists ? CashEntry.fromMap(d.id, d.data()!) : null;
}

Future<void> saveCashEntry(CashEntry e) async {
  final data = {...e.toMap(), 'updatedAt': FieldValue.serverTimestamp()};
  if (e.id == null) {
    await companyCol('cash_entries').add({
      ...data,
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': FirebaseAuth.instance.currentUser?.uid ?? '',
    });
  } else {
    await companyCol('cash_entries').doc(e.id).set(data);
  }
}

Future<void> deleteCashEntry(String id) => companyCol('cash_entries').doc(id).delete();
