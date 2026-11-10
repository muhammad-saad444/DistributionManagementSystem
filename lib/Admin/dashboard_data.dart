// The admin dashboard's live readings: sales, recoveries, what shops owe, open invoices, orders
// waiting, and how each booker is doing. Worked out from the company's own records on every load;
// [DashboardStats.compute] is plain arithmetic over those records so it can be tested.
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../account/account.dart';
import '../khata.dart' show KhataKind, KhataLine, settleOldestFirst;

final _salesDay = DateFormat('dd-MM-yyyy');

DateTime _d(DateTime t) => DateTime(t.year, t.month, t.day);
num _n(dynamic v) => v is num ? v : num.tryParse((v ?? '').toString().trim()) ?? 0;

DateTime? _parseSalesDate(dynamic v) {
  try {
    return _salesDay.parseStrict((v ?? '').toString().trim());
  } catch (_) {
    return null;
  }
}

/// One invoice, as the dashboard needs it.
class DashInvoice {
  final String id;
  final DateTime date;
  final double amount; // after discount
  final String customer;
  final String userId;
  final String area;
  final List<Map> items;
  const DashInvoice({
    required this.id,
    required this.date,
    required this.amount,
    required this.customer,
    required this.userId,
    this.area = '',
    this.items = const [],
  });
}

/// Money in (a payment or office recovery) or manual udhaar, for one shop of one booker.
class DashEntry {
  final DateTime date;
  final double amount;
  final String customer;
  final String userId;
  final bool payment;
  const DashEntry({required this.date, required this.amount, required this.customer, required this.userId, this.payment = true});
}

class BookerDay {
  final String userId;
  final String name;
  int invoices = 0;
  double sales = 0;
  double recovered = 0;
  double outstanding = 0;
  BookerDay(this.userId, this.name);
}

class ShopDue {
  final String customer;
  final String booker;
  final double balance;
  final int oldestOpenDays; // age of the oldest unpaid invoice, in days
  const ShopDue(this.customer, this.booker, this.balance, this.oldestOpenDays);
}

class DashboardStats {
  final DateTime asOf;
  // Today and the day before
  final double todaySales;
  final int todayInvoices;
  final double yesterdaySales;
  final double todayRecovered;
  final double yesterdayRecovered;
  // This month to date, and the same days of last month
  final double monthSales;
  final double lastMonthSales;
  final double monthRecovered;
  final int monthInvoices;
  // Owed by shops
  final double outstanding;
  final int shopsOwing;
  final int openInvoices;
  final int overdueInvoices; // open more than 30 days
  final double overdueAmount;
  // Last 30 days, oldest first
  final List<double> dailySales;
  final List<double> dailyRecovered;
  // Breakdowns
  final List<BookerDay> bookers; // best sales today first
  final int activeBookersToday;
  final List<MapEntry<String, double>> topProducts; // this month, by value
  final List<MapEntry<String, double>> areaSales; // this month
  final List<ShopDue> topDues;
  // Shops and orders
  final int customers;
  final int newCustomersThisMonth;
  final int pendingOrders;
  final double pendingOrdersValue;

  const DashboardStats({
    required this.asOf,
    this.todaySales = 0,
    this.todayInvoices = 0,
    this.yesterdaySales = 0,
    this.todayRecovered = 0,
    this.yesterdayRecovered = 0,
    this.monthSales = 0,
    this.lastMonthSales = 0,
    this.monthRecovered = 0,
    this.monthInvoices = 0,
    this.outstanding = 0,
    this.shopsOwing = 0,
    this.openInvoices = 0,
    this.overdueInvoices = 0,
    this.overdueAmount = 0,
    this.dailySales = const [],
    this.dailyRecovered = const [],
    this.bookers = const [],
    this.activeBookersToday = 0,
    this.topProducts = const [],
    this.areaSales = const [],
    this.topDues = const [],
    this.customers = 0,
    this.newCustomersThisMonth = 0,
    this.pendingOrders = 0,
    this.pendingOrdersValue = 0,
  });

  /// Recovered as a share of what was sold this month (0..1).
  double get monthRecoveryRate => monthSales <= 0 ? 0 : (monthRecovered / monthSales).clamp(0, 1).toDouble();

  static DashboardStats compute({
    required DateTime now,
    required List<DashInvoice> invoices,
    required List<DashEntry> entries,
    Map<String, String> bookerNames = const {},
    int customers = 0,
    int newCustomersThisMonth = 0,
    int pendingOrders = 0,
    double pendingOrdersValue = 0,
    int days = 30,
  }) {
    final today = _d(now);
    final yesterday = today.subtract(const Duration(days: 1));
    final monthStart = DateTime(today.year, today.month);
    final lastMonthStart = DateTime(today.year, today.month - 1);
    // Same span of last month: 1st to the same day number (or the month's end).
    final lastMonthEnd = DateTime(today.year, today.month - 1, today.day).isBefore(monthStart)
        ? DateTime(today.year, today.month - 1, today.day)
        : monthStart.subtract(const Duration(days: 1));
    final firstChartDay = today.subtract(Duration(days: days - 1));

    double todaySales = 0, yesterdaySales = 0, monthSales = 0, lastMonthSales = 0;
    double todayRec = 0, yesterdayRec = 0, monthRec = 0;
    int todayInv = 0, monthInv = 0;
    final dailySales = List<double>.filled(days, 0);
    final dailyRec = List<double>.filled(days, 0);
    final bookers = <String, BookerDay>{};
    final products = <String, double>{};
    final areas = <String, double>{};

    BookerDay booker(String uid) =>
        bookers.putIfAbsent(uid, () => BookerDay(uid, bookerNames[uid] ?? 'Unknown booker'));
    for (final uid in bookerNames.keys) {
      booker(uid);
    }

    for (final inv in invoices) {
      final day = _d(inv.date);
      if (day == today) {
        todaySales += inv.amount;
        todayInv++;
        booker(inv.userId)
          ..sales += inv.amount
          ..invoices += 1;
      } else if (day == yesterday) {
        yesterdaySales += inv.amount;
      }
      if (!day.isBefore(monthStart) && !day.isAfter(today)) {
        monthSales += inv.amount;
        monthInv++;
        final area = inv.area.trim();
        areas[area.isEmpty ? 'No area' : area] = (areas[area.isEmpty ? 'No area' : area] ?? 0) + inv.amount;
        for (final it in inv.items) {
          final name = (it['Product Name'] ?? it['productName'] ?? '').toString().trim();
          if (name.isEmpty) continue;
          final qty = _n(it['QTY'] ?? it['qty']) - _n(it['returnQty'] ?? it['returnedQty']);
          final value = qty * _n(it['TP']);
          if (value > 0) products[name] = (products[name] ?? 0) + value.toDouble();
        }
      } else if (!day.isBefore(lastMonthStart) && !day.isAfter(lastMonthEnd)) {
        lastMonthSales += inv.amount;
      }
      final i = day.difference(firstChartDay).inDays;
      if (i >= 0 && i < days) dailySales[i] += inv.amount;
    }

    for (final e in entries.where((e) => e.payment)) {
      final day = _d(e.date);
      if (day == today) {
        todayRec += e.amount;
        booker(e.userId).recovered += e.amount;
      } else if (day == yesterday) {
        yesterdayRec += e.amount;
      }
      if (!day.isBefore(monthStart) && !day.isAfter(today)) monthRec += e.amount;
      final i = day.difference(firstChartDay).inDays;
      if (i >= 0 && i < days) dailyRec[i] += e.amount;
    }

    // What shops owe: each booker's khata per shop, invoices paid off oldest first.
    final ledgers = <String, List<KhataLine>>{};
    String key(String uid, String shop) => '$uid\u0000${shop.trim()}';
    for (final inv in invoices) {
      if (inv.customer.trim().isEmpty) continue;
      ledgers.putIfAbsent(key(inv.userId, inv.customer), () => []).add(KhataLine(
          id: inv.id, kind: KhataKind.invoice, date: inv.date, createdAt: inv.date, amount: inv.amount, title: ''));
    }
    for (final e in entries) {
      if (e.customer.trim().isEmpty) continue;
      ledgers.putIfAbsent(key(e.userId, e.customer), () => []).add(KhataLine(
          id: '',
          kind: e.payment ? KhataKind.payment : KhataKind.udhaar,
          date: e.date,
          createdAt: e.date,
          amount: e.amount,
          title: ''));
    }
    double outstanding = 0, overdueAmount = 0;
    int shopsOwing = 0, openInv = 0, overdueInv = 0;
    final dues = <ShopDue>[];
    for (final entry in ledgers.entries) {
      final lines = entry.value
        ..sort((a, b) {
          final c = _d(a.date).compareTo(_d(b.date));
          // On the same day, debts first, so that day's payment settles that day's invoice.
          return c != 0 ? c : (a.isDebt == b.isDebt ? 0 : (a.isDebt ? -1 : 1));
        });
      settleOldestFirst(lines);
      final balance = lines.fold<double>(0, (s, l) => s + l.signed);
      final uid = entry.key.split('\u0000').first;
      final shop = entry.key.split('\u0000').last;
      if (balance > 0.5) {
        outstanding += balance;
        shopsOwing++;
        booker(uid).outstanding += balance;
      }
      int oldest = 0;
      for (final l in lines.where((l) => l.kind == KhataKind.invoice && !l.isClosed)) {
        openInv++;
        final age = today.difference(_d(l.date)).inDays;
        if (age > oldest) oldest = age;
        if (age > 30) {
          overdueInv++;
          overdueAmount += l.due;
        }
      }
      if (balance > 0.5) dues.add(ShopDue(shop, bookerNames[uid] ?? '', balance, oldest));
    }
    dues.sort((a, b) => b.balance.compareTo(a.balance));

    List<MapEntry<String, double>> top(Map<String, double> m, int n) =>
        (m.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).take(n).toList();

    final bookerList = bookers.values.toList()
      ..sort((a, b) {
        final c = b.sales.compareTo(a.sales);
        return c != 0 ? c : b.outstanding.compareTo(a.outstanding);
      });

    return DashboardStats(
      asOf: now,
      todaySales: todaySales,
      todayInvoices: todayInv,
      yesterdaySales: yesterdaySales,
      todayRecovered: todayRec,
      yesterdayRecovered: yesterdayRec,
      monthSales: monthSales,
      lastMonthSales: lastMonthSales,
      monthRecovered: monthRec,
      monthInvoices: monthInv,
      outstanding: outstanding,
      shopsOwing: shopsOwing,
      openInvoices: openInv,
      overdueInvoices: overdueInv,
      overdueAmount: overdueAmount,
      dailySales: dailySales,
      dailyRecovered: dailyRec,
      bookers: bookerList,
      activeBookersToday: bookerList.where((b) => b.invoices > 0).length,
      topProducts: top(products, 6),
      areaSales: top(areas, 6),
      topDues: dues.take(5).toList(),
      customers: customers,
      newCustomersThisMonth: newCustomersThisMonth,
      pendingOrders: pendingOrders,
      pendingOrdersValue: pendingOrdersValue,
    );
  }
}

/// One reading of the dashboard. [live]: every list came from the server (not just this device's
/// saved copy), so the figures are up to date.
class DashboardLive {
  final DashboardStats stats;
  final bool live;
  const DashboardLive(this.stats, {required this.live});
}

/// The dashboard, kept in sync: the first reading comes from what this device saved last time
/// (instant), then a new one whenever data arrives from the server or anything changes there
/// (a new invoice, a payment). Parts the company can't read (a module that is off) count as empty.
Stream<DashboardLive> watchDashboardStats() {
  final queries = <Query<Map<String, dynamic>>>[
    companyCol('invoices'),
    companyCol('khata_entries'),
    companyCol('customer_recoveries'),
    companyCol('customers'),
    companyCol('sales_orders').where('status', isEqualTo: 'pending'),
    companyCol('sessions'),
  ];
  final latest = List<QuerySnapshot<Map<String, dynamic>>?>.filled(queries.length, null);
  final fromServer = List<bool>.filled(queries.length, false);
  final subs = <StreamSubscription<Object?>>[];
  var isBooker = (String uid, String email) => true;
  Timer? soon;
  late final StreamController<DashboardLive> out;

  void emit() {
    // Several lists usually arrive together: work the figures out once for the batch.
    soon?.cancel();
    soon = Timer(const Duration(milliseconds: 80), () {
      final inv = latest[0];
      // Nothing known about sales yet (or only an empty saved copy): don't show zeros that aren't real.
      if (inv == null && !fromServer[0]) return;
      if (inv != null && inv.metadata.isFromCache && inv.docs.isEmpty) return;
      if (!out.isClosed) out.add(DashboardLive(_statsFrom(latest, isBooker), live: fromServer.every((x) => x)));
    });
  }

  out = StreamController<DashboardLive>(
    onListen: () {
      bookerFilter(cached: true).then((f) {
        isBooker = f;
        emit();
      }, onError: (_) {});
      bookerFilter().then((f) {
        isBooker = f;
        emit();
      }, onError: (_) {});
      for (var i = 0; i < queries.length; i++) {
        subs.add(queries[i].snapshots(includeMetadataChanges: true).listen((s) {
          final server = !s.metadata.isFromCache;
          // Only work the figures out again when the data or where it came from actually changed.
          if (latest[i] != null && s.docChanges.isEmpty && server == fromServer[i]) return;
          latest[i] = s;
          fromServer[i] = server;
          emit();
        }, onError: (Object e) {
          debugPrint('Dashboard: list $i not read: $e');
          fromServer[i] = true; // not readable (module off): counts as empty
          emit();
        }));
      }
    },
    onCancel: () {
      soon?.cancel();
      for (final s in subs) {
        s.cancel();
      }
    },
  );
  return out.stream;
}

/// Reads the company's records once and works out the dashboard.
Future<DashboardStats> loadDashboardStats() async {
  Future<QuerySnapshot<Map<String, dynamic>>?> safe(Future<QuerySnapshot<Map<String, dynamic>>> q, String what) async {
    try {
      return await q;
    } catch (e) {
      debugPrint('Dashboard: $what not read: $e');
      return null;
    }
  }

  final results = await Future.wait([
    safe(companyCol('invoices').get(), 'invoices'),
    safe(companyCol('khata_entries').get(), 'khata'),
    safe(companyCol('customer_recoveries').get(), 'office recoveries'),
    safe(companyCol('customers').get(), 'customers'),
    safe(companyCol('sales_orders').where('status', isEqualTo: 'pending').get(), 'sales orders'),
    safe(companyCol('sessions').get(), 'sessions'),
  ]);
  var isBooker = (String uid, String email) => true;
  try {
    isBooker = await bookerFilter();
  } catch (_) {}
  return _statsFrom(results, isBooker);
}

/// The dashboard from the six lists: invoices, khata entries, office recoveries, customers,
/// pending sales orders, sessions (any may be null: not readable).
DashboardStats _statsFrom(
    List<QuerySnapshot<Map<String, dynamic>>?> results, bool Function(String uid, String email) isBooker) {
  final now = DateTime.now();
  final invoices = <DashInvoice>[];
  for (final d in results[0]?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[]) {
    final m = d.data();
    final date = _parseSalesDate(m['salesDate']) ?? (m['createdAt'] is Timestamp ? (m['createdAt'] as Timestamp).toDate() : null);
    if (date == null) continue;
    invoices.add(DashInvoice(
      id: d.id,
      date: date,
      amount: _n(m['grandTotal'] ?? m['total']).toDouble(),
      customer: (m['customer'] ?? '').toString().trim(),
      userId: (m['userId'] ?? '').toString(),
      area: (m['area'] ?? '').toString(),
      items: [for (final it in (m['items'] as List? ?? const [])) if (it is Map) it],
    ));
  }

  final entries = <DashEntry>[];
  for (final d in results[1]?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[]) {
    final m = d.data();
    final ts = m['date'] ?? m['createdAt'];
    if (ts is! Timestamp) continue;
    entries.add(DashEntry(
      date: ts.toDate(),
      amount: _n(m['amount']).toDouble(),
      customer: (m['customer'] ?? '').toString().trim(),
      userId: (m['userId'] ?? '').toString(),
      payment: m['type'] == 'payment',
    ));
  }
  for (final d in results[2]?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[]) {
    final m = d.data();
    DateTime? date;
    try {
      date = DateFormat('yyyy-MM-dd').parseStrict((m['dateStr'] ?? '').toString());
    } catch (_) {
      date = m['createdAt'] is Timestamp ? (m['createdAt'] as Timestamp).toDate() : null;
    }
    if (date == null) continue;
    entries.add(DashEntry(
      date: date,
      amount: _n(m['amountPaid']).toDouble(),
      customer: (m['customerName'] ?? '').toString().trim(),
      userId: (m['userId'] ?? '').toString(),
    ));
  }

  final monthStart = DateTime(now.year, now.month);
  final customerDocs = results[3]?.docs ?? const [];
  final newShops = customerDocs.where((d) {
    final c = d.data()['createdAt'];
    return c is Timestamp && !c.toDate().isBefore(monthStart);
  }).length;

  final orders = results[4]?.docs ?? const [];
  double ordersValue = 0;
  for (final o in orders) {
    final m = o.data();
    final items = (m['items'] as List? ?? const []).whereType<Map>();
    final total = items.fold<num>(0, (s, it) => s + _n(it['TP']) * _n(it['QTY']));
    final disc = _n(m['discount']);
    ordersValue += (m['discountType'] == 'amount' ? total - disc : total * (100 - disc) / 100).toDouble();
  }

  final names = <String, String>{};
  for (final s in results[5]?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[]) {
    final m = s.data();
    final uid = (m['uid'] ?? s.id).toString();
    if (!isBooker(uid, (m['email'] ?? '').toString())) continue;
    final name = (m['username'] ?? m['email'] ?? '').toString().trim();
    names[uid] = name.isEmpty ? 'Booker' : name;
  }

  return DashboardStats.compute(
    now: now,
    invoices: invoices,
    entries: entries,
    bookerNames: names,
    customers: customerDocs.length,
    newCustomersThisMonth: newShops,
    pendingOrders: orders.length,
    pendingOrdersValue: ordersValue,
  );
}
