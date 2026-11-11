// Company-wide receivables: what every shop owes, with every booker, split by how long it has
// been unpaid (ageing). Built from each booker's khata, where payments settle the oldest invoice
// first, so each unpaid rupee keeps the date of the invoice (or udhaar) it belongs to.
import 'package:cloud_firestore/cloud_firestore.dart';

import '../account/account.dart';
import '../khata.dart';

/// Money owed, split by age: 0–30, 31–60, 61–90 and over 90 days.
class Ageing {
  double d0to30 = 0;
  double d31to60 = 0;
  double d61to90 = 0;
  double over90 = 0;

  double get total => d0to30 + d31to60 + d61to90 + over90;

  /// Owed for more than 30 days.
  double get overdue => d31to60 + d61to90 + over90;

  void add(int days, double amount) {
    if (days <= 30) {
      d0to30 += amount;
    } else if (days <= 60) {
      d31to60 += amount;
    } else if (days <= 90) {
      d61to90 += amount;
    } else {
      over90 += amount;
    }
  }

  void addAll(Ageing o) {
    d0to30 += o.d0to30;
    d31to60 += o.d31to60;
    d61to90 += o.d61to90;
    over90 += o.over90;
  }

  List<double> get buckets => [d0to30, d31to60, d61to90, over90];
}

const ageingLabels = ['0–30 days', '31–60 days', '61–90 days', 'Over 90 days'];

/// One shop's debt with one booker.
class ShopReceivable {
  final String bookerUid;
  final String bookerName;
  final String shop;
  final String area;
  final Ageing ageing;
  final int oldestDays; // age of the oldest unpaid invoice or udhaar (0 when nothing is owed)
  final int openInvoices;
  final DateTime? lastPayment;
  final double creditLimit; // 0 = none set

  const ShopReceivable({
    required this.bookerUid,
    required this.bookerName,
    required this.shop,
    required this.area,
    required this.ageing,
    required this.oldestDays,
    required this.openInvoices,
    required this.lastPayment,
    this.creditLimit = 0,
  });

  double get total => ageing.total;
  bool get overLimit => creditLimit > 0 && total > creditLimit + 0.5;
}

/// A group of shops (a booker or an area) with their combined ageing.
class ReceivableGroup {
  final String name;
  final Ageing ageing = Ageing();
  int shops = 0;
  ReceivableGroup(this.name);
}

int _days(DateTime today, DateTime d) =>
    DateTime(today.year, today.month, today.day).difference(DateTime(d.year, d.month, d.day)).inDays;

/// Every shop that owes money, most owed first. [books]: each booker's khata by uid;
/// [bookerNames] by uid; [shopInfo] by shop name: (area, credit limit).
List<ShopReceivable> receivablesFrom(
  Map<String, KhataBook> books,
  Map<String, String> bookerNames,
  DateTime today, {
  Map<String, (String, double)> shopInfo = const {},
}) {
  final out = <ShopReceivable>[];
  for (final entry in books.entries) {
    for (final shop in entry.value.shops) {
      final ageing = Ageing();
      var oldest = 0;
      var open = 0;
      DateTime? lastPayment;
      String area = '';
      for (final l in shop.lines) {
        if (l.kind == KhataKind.payment) {
          if (lastPayment == null || l.date.isAfter(lastPayment)) lastPayment = l.date;
          continue;
        }
        if (l.kind == KhataKind.invoice && l.note.trim().isNotEmpty) area = l.note.trim(); // latest invoice's area
        final due = l.due;
        if (due < 0.5) continue;
        final age = _days(today, l.date).clamp(0, 100000).toInt();
        ageing.add(age, due);
        if (age > oldest) oldest = age;
        if (l.kind == KhataKind.invoice) open++;
      }
      if (ageing.total < 0.5) continue;
      final info = shopInfo[shop.customer];
      if (info != null && info.$1.isNotEmpty) area = info.$1;
      out.add(ShopReceivable(
        bookerUid: entry.key,
        bookerName: bookerNames[entry.key] ?? 'Booker',
        shop: shop.customer,
        area: area.isEmpty ? '-' : area,
        ageing: ageing,
        oldestDays: oldest,
        openInvoices: open,
        lastPayment: lastPayment,
        creditLimit: info?.$2 ?? 0,
      ));
    }
  }
  out.sort((a, b) => b.total.compareTo(a.total));
  return out;
}

/// Groups shops by [key] (booker or area), most owed first.
List<ReceivableGroup> groupReceivables(List<ShopReceivable> rows, String Function(ShopReceivable r) key) {
  final groups = <String, ReceivableGroup>{};
  for (final r in rows) {
    final g = groups.putIfAbsent(key(r), () => ReceivableGroup(key(r)));
    g.ageing.addAll(r.ageing);
    g.shops++;
  }
  return groups.values.toList()..sort((a, b) => b.ageing.total.compareTo(a.ageing.total));
}

Ageing totalAgeing(Iterable<ShopReceivable> rows) {
  final t = Ageing();
  for (final r in rows) {
    t.addAll(r.ageing);
  }
  return t;
}

/// Reads everything the receivables screen needs.
Future<List<ShopReceivable>> loadReceivables() async {
  final results = await Future.wait<Object?>([
    loadCompanyKhata(),
    companyCol('sessions').get().then<QuerySnapshot<Map<String, dynamic>>?>((s) => s, onError: (_) => null),
    companyCol('customers').get().then<QuerySnapshot<Map<String, dynamic>>?>((s) => s, onError: (_) => null),
  ]);
  final books = results[0] as Map<String, KhataBook>;
  final names = <String, String>{};
  for (final d in (results[1] as QuerySnapshot<Map<String, dynamic>>?)?.docs ?? const []) {
    final m = d.data();
    final n = (m['username'] ?? m['email'] ?? '').toString().trim();
    if (n.isNotEmpty) names[(m['uid'] ?? d.id).toString()] = n;
  }
  try {
    for (final u in await loadCompanyUsers()) {
      names.putIfAbsent(u.uid, () => u.display);
    }
  } catch (_) {}
  final info = <String, (String, double)>{};
  for (final d in (results[2] as QuerySnapshot<Map<String, dynamic>>?)?.docs ?? const []) {
    final m = d.data();
    final name = (m['name'] ?? '').toString().trim();
    if (name.isEmpty) continue;
    info[name] = ((m['area'] ?? '').toString().trim(), (num.tryParse('${m['creditLimit'] ?? 0}') ?? 0).toDouble());
  }
  return receivablesFrom(books, names, DateTime.now(), shopInfo: info);
}
