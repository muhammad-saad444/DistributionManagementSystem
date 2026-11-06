// Areas for printed DSRs and load sheets. An invoice booked before the booker had an area
// assigned was saved with no area, so fall back to the shop's area, then the booker's areas.
import 'package:cloud_firestore/cloud_firestore.dart';

import 'account/account.dart';

String _s(dynamic v) => (v ?? '').toString().trim();

/// Each invoice's area, by invoice id: its own, else its shop's area from customers.
Future<Map<String, String>> invoiceAreas(List<QueryDocumentSnapshot<Map<String, dynamic>>> invoices) async {
  final out = <String, String>{};
  final missing = <String>{};
  for (final d in invoices) {
    final a = _s(d.data()['area']);
    out[d.id] = a;
    if (a.isEmpty && _s(d.data()['customer']).isNotEmpty) missing.add(_s(d.data()['customer']));
  }
  if (missing.isEmpty) return out;

  final shopArea = <String, String>{};
  try {
    final names = missing.toList();
    for (var i = 0; i < names.length; i += 30) {
      final snap = await companyCol('customers')
          .where('name', whereIn: names.sublist(i, i + 30 > names.length ? names.length : i + 30))
          .get();
      for (final c in snap.docs) {
        final a = _s(c.data()['area']);
        if (a.isNotEmpty) shopArea[_s(c.data()['name'])] = a;
      }
    }
  } catch (_) {
    // No access to shops: leave those invoices without an area.
  }
  for (final d in invoices) {
    if (out[d.id]!.isEmpty) out[d.id] = shopArea[_s(d.data()['customer'])] ?? '';
  }
  return out;
}

/// The areas a booker worked on a sales date (dd-MM-yyyy), joined for a header; "-" when none.
/// Falls back to the booker's assigned areas when no invoice or shop has one.
Future<String> bookerDayAreas(String userId, String salesDate) async {
  if (userId.isEmpty) return '-';
  final found = <String>{};
  try {
    final snap = await companyCol('invoices')
        .where('userId', isEqualTo: userId)
        .where('salesDate', isEqualTo: salesDate)
        .get();
    found.addAll((await invoiceAreas(snap.docs)).values.where((a) => a.isNotEmpty));
  } catch (_) {}
  if (found.isEmpty) found.addAll(await bookerAssignedAreas(userId));
  return found.isEmpty ? '-' : found.join(', ');
}

/// The areas the admin allocated to a booker (user_areas, by their username).
Future<List<String>> bookerAssignedAreas(String userId) async {
  try {
    final session = await companyCol('sessions').doc(userId).get();
    final username = _s(session.data()?['username']);
    if (username.isEmpty) return const [];
    final snap = await companyCol('user_areas').where('username', isEqualTo: username).limit(1).get();
    if (snap.docs.isEmpty) return const [];
    return [for (final a in (snap.docs.first.data()['areas'] as List? ?? const [])) if (_s(a).isNotEmpty) _s(a)];
  } catch (_) {
    return const [];
  }
}

/// A saved report's date (yyyy-MM-dd) as an invoice sales date (dd-MM-yyyy).
String salesDateOf(String dateStr) {
  final p = dateStr.split('-');
  return p.length == 3 && p[0].length == 4 ? '${p[2]}-${p[1]}-${p[0]}' : dateStr;
}

/// One invoice's area for printing: its own, else its shop's; "-" when neither has one.
Future<String> invoiceAreaOf(Map<String, dynamic> invoice) async {
  final own = _s(invoice['area']);
  if (own.isNotEmpty) return own;
  final shop = _s(invoice['customer']);
  if (shop.isEmpty) return '-';
  try {
    final snap = await companyCol('customers').where('name', isEqualTo: shop).limit(1).get();
    final a = snap.docs.isEmpty ? '' : _s(snap.docs.first.data()['area']);
    return a.isEmpty ? '-' : a;
  } catch (_) {
    return '-';
  }
}
