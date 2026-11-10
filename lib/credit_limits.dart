// A shop's credit terms, set by the office: how much it may owe (credit limit) and for how long an
// invoice may stay unpaid (credit days). Book Order checks them before saving a new invoice.
import 'khata.dart';

num _n(dynamic v) => v is num ? v : num.tryParse((v ?? '').toString().trim()) ?? 0;

class CreditTerms {
  final double limit; // Rs; 0 = no limit
  final int days; // 0 = no limit
  const CreditTerms({this.limit = 0, this.days = 0});

  factory CreditTerms.fromCustomer(Map<String, dynamic>? m) =>
      CreditTerms(limit: _n(m?['creditLimit']).toDouble(), days: _n(m?['creditDays']).toInt());

  bool get none => limit <= 0 && days <= 0;
}

/// Why a new invoice of [amount] can't be booked for this shop, or null when it can.
/// [shop] is the shop's khata with this booker (null: no history yet).
String? creditProblem(CreditTerms terms, ShopKhata? shop, double amount, DateTime today) {
  if (terms.none) return null;
  final balance = shop?.balance ?? 0;
  if (terms.limit > 0 && balance + amount > terms.limit + 0.5) {
    final room = terms.limit - balance;
    return 'This shop already owes Rs ${_rs(balance)} and its credit limit is Rs ${_rs(terms.limit)}. '
        '${room > 0.5 ? 'Only Rs ${_rs(room)} more can go on credit.' : 'Nothing more can go on credit.'} '
        'Collect a payment first, or ask the office to raise the limit.';
  }
  if (terms.days > 0 && shop != null) {
    final day = DateTime(today.year, today.month, today.day);
    for (final l in shop.lines) {
      if (l.kind != KhataKind.invoice || l.isClosed) continue;
      final age = day.difference(DateTime(l.date.year, l.date.month, l.date.day)).inDays;
      if (age > terms.days) {
        return '${l.title} (Rs ${_rs(l.due)} left) has been unpaid for $age days; this shop gets '
            '${terms.days} days of credit. Collect it first, or ask the office.';
      }
    }
  }
  return null;
}

String _rs(num v) {
  final s = v.round().abs().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return (v < 0 ? '-' : '') + b.toString();
}
