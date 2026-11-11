// Trade schemes: the company's free-goods offers ("12 + 1": buy 12, get 1 free), set on the product
// by the office. Book Order fills the free goods (FOC) from the quantity; the booker may give fewer,
// never more. A scheme can run between two dates and for some kinds of shop only (B2B, B2R, B2C).
//
// Saved on the product: schemeBuy, schemeFree, schemeFrom, schemeTo (Timestamps, optional) and
// schemeTiers (list; empty = every kind of shop).
import 'package:cloud_firestore/cloud_firestore.dart';

class TradeScheme {
  final int buy;
  final int free;
  final DateTime? from; // first day (inclusive)
  final DateTime? to; // last day (inclusive)
  final Set<String> tiers; // empty: all shops

  const TradeScheme({required this.buy, required this.free, this.from, this.to, this.tiers = const {}});

  static int _int(dynamic v) => (num.tryParse('${v ?? 0}') ?? 0).toInt();
  static DateTime? _date(dynamic v) => v is Timestamp ? v.toDate() : (v is DateTime ? v : null);

  /// The product's scheme, or null when it has none.
  static TradeScheme? of(Map<String, dynamic>? product) {
    if (product == null) return null;
    final buy = _int(product['schemeBuy']);
    final free = _int(product['schemeFree']);
    if (buy <= 0 || free <= 0) return null;
    return TradeScheme(
      buy: buy,
      free: free,
      from: _date(product['schemeFrom']),
      to: _date(product['schemeTo']),
      tiers: {for (final t in (product['schemeTiers'] as List? ?? const [])) t.toString()},
    );
  }

  /// The fields to save on the product ([scheme] null: no scheme).
  static Map<String, dynamic> fields(TradeScheme? scheme) => {
        'schemeBuy': scheme?.buy ?? 0,
        'schemeFree': scheme?.free ?? 0,
        'schemeFrom': scheme?.from == null ? null : Timestamp.fromDate(scheme!.from!),
        'schemeTo': scheme?.to == null ? null : Timestamp.fromDate(scheme!.to!),
        'schemeTiers': scheme?.tiers.toList() ?? const <String>[],
      };

  String get label => '$buy + $free';

  /// Whether a shop of [tier] gets it on [day].
  bool appliesTo(String tier, DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    if (from != null && d.isBefore(DateTime(from!.year, from!.month, from!.day))) return false;
    if (to != null && d.isAfter(DateTime(to!.year, to!.month, to!.day))) return false;
    return tiers.isEmpty || tiers.contains(tier);
  }

  /// Whether it is running (or starts later) rather than over.
  bool isCurrent(DateTime day) => to == null || !DateTime(day.year, day.month, day.day).isAfter(DateTime(to!.year, to!.month, to!.day));

  /// Free units for [qty] sold: a full [free] for every full [buy].
  int freeFor(num qty) => qty <= 0 ? 0 : (qty ~/ buy) * free;
}
