// CRM data for each booker's shops.
//
// The CRM reads what the app already stores and adds only what was missing:
//   - shops come from `customers` (salesman == booker's username); CRM `tags` and `notes` are
//     extra fields on those same documents;
//   - sales and balances come from the khata (invoices + khata_entries, see khata.dart);
//   - `crm_visits`: one document per shop visit or call the booker logs;
//   - `crm_followups`: reminders with a due date ("collect payment Thursday").
// Queries filter on a single field and sort on the device, so no composite indexes are needed.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../account/account.dart';
import '../khata.dart';
import '../inventory/price_tiers.dart';

/// A shop with no order and no visit for this many days needs a visit.
const needsVisitDays = 14;

/// A shop with no order for this many days is inactive.
const inactiveDays = 30;

DateTime? _asDate(dynamic v) => v is Timestamp ? v.toDate() : (v is DateTime ? v : null);

DateTime _dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

int daysSince(DateTime d) => _dayOf(DateTime.now()).difference(_dayOf(d)).inDays;

// =============================================================================
// Models
// =============================================================================

class VisitOutcome {
  final String key;
  final String label;
  const VisitOutcome(this.key, this.label);

  static const order = VisitOutcome('order', 'Order taken');
  static const noOrder = VisitOutcome('no_order', 'No order');
  static const payment = VisitOutcome('payment', 'Payment collected');
  static const closed = VisitOutcome('closed', 'Shop closed');
  static const complaint = VisitOutcome('complaint', 'Complaint');
  static const call = VisitOutcome('call', 'Phone call');

  static const all = [order, noOrder, payment, closed, complaint, call];

  static VisitOutcome of(String key) =>
      all.firstWhere((o) => o.key == key, orElse: () => VisitOutcome(key, key.isEmpty ? 'Visit' : key));
}

class CrmVisit {
  final String id;
  final String customerId;
  final String customer;
  final VisitOutcome outcome;
  final String note;
  final DateTime date;
  final DateTime createdAt;

  CrmVisit({
    required this.id,
    required this.customerId,
    required this.customer,
    required this.outcome,
    required this.note,
    required this.date,
    required this.createdAt,
  });

  factory CrmVisit.fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data();
    final created = _asDate(m['createdAt']) ?? DateTime.now(); // null while the write is still pending
    return CrmVisit(
      id: d.id,
      customerId: (m['customerId'] ?? '').toString(),
      customer: (m['customer'] ?? '').toString(),
      outcome: VisitOutcome.of((m['outcome'] ?? '').toString()),
      note: (m['note'] ?? '').toString(),
      date: _asDate(m['date']) ?? created,
      createdAt: created,
    );
  }
}

class CrmFollowUp {
  final String id;
  final String customerId;
  final String customer;
  final String title;
  final String note;
  final DateTime dueDate;
  final bool done;
  final DateTime? doneAt;

  CrmFollowUp({
    required this.id,
    required this.customerId,
    required this.customer,
    required this.title,
    required this.note,
    required this.dueDate,
    required this.done,
    this.doneAt,
  });

  bool get isOverdue => !done && _dayOf(dueDate).isBefore(_dayOf(DateTime.now()));
  bool get isDueToday => !done && _dayOf(dueDate) == _dayOf(DateTime.now());
  bool get isDue => isOverdue || isDueToday;

  factory CrmFollowUp.fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data();
    return CrmFollowUp(
      id: d.id,
      customerId: (m['customerId'] ?? '').toString(),
      customer: (m['customer'] ?? '').toString(),
      title: (m['title'] ?? '').toString(),
      note: (m['note'] ?? '').toString(),
      dueDate: _asDate(m['dueDate']) ?? DateTime.now(),
      done: m['done'] == true,
      doneAt: _asDate(m['doneAt']),
    );
  }
}

class CrmCustomer {
  final String id;
  final String name;
  final String code;
  final String contact;
  final String cnic;
  final String ntn;
  final String address;
  final String type;
  final String area;
  final String salesman;
  final String priceTier; // b2b, b2r or b2c: which product price this shop pays
  final double creditLimit; // Rs the shop may owe (0 = no limit)
  final int creditDays; // days an invoice may stay unpaid (0 = no limit)
  final List<String> tags;
  final String notes;
  final DateTime? createdAt;

  // Filled in from the khata and visits by loadCrmBook.
  ShopKhata? khata;
  List<CrmVisit> visits = []; // newest first
  List<CrmFollowUp> followUps = []; // open ones first, by due date

  CrmCustomer({
    required this.id,
    required this.name,
    required this.code,
    required this.contact,
    required this.cnic,
    required this.ntn,
    required this.address,
    required this.type,
    required this.area,
    required this.salesman,
    this.priceTier = 'b2r',
    this.creditLimit = 0,
    this.creditDays = 0,
    required this.tags,
    required this.notes,
    this.createdAt,
  });

  factory CrmCustomer.fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data();
    String s(String k) => (m[k] ?? '').toString().trim();
    return CrmCustomer(
      id: d.id,
      name: s('name'),
      code: s('code'),
      contact: s('contact'),
      cnic: s('cnic'),
      ntn: s('ntn'),
      address: s('address'),
      type: s('type'),
      area: s('area'),
      salesman: s('salesman'),
      priceTier: customerTier(m),
      creditLimit: (num.tryParse('${m['creditLimit'] ?? 0}') ?? 0).toDouble(),
      creditDays: (num.tryParse('${m['creditDays'] ?? 0}') ?? 0).toInt(),
      tags: List<String>.from((m['tags'] as List?)?.map((t) => t.toString()) ?? const []),
      notes: (m['notes'] ?? '').toString(),
      createdAt: _asDate(m['createdAt']),
    );
  }

  List<KhataLine> get invoices => khata?.lines.where((l) => l.kind == KhataKind.invoice).toList() ?? [];

  double get balance => khata?.balance ?? 0;
  double get totalSales => invoices.fold(0.0, (s, l) => s + l.amount);
  int get orderCount => invoices.length;
  double get averageOrder => orderCount == 0 ? 0 : totalSales / orderCount;

  DateTime? get lastOrder {
    DateTime? last;
    for (final l in invoices) {
      if (last == null || l.date.isAfter(last)) last = l.date;
    }
    return last;
  }

  DateTime? get lastVisit => visits.isEmpty ? null : visits.first.date;

  /// The most recent order or visit.
  DateTime? get lastContact {
    final o = lastOrder, v = lastVisit;
    if (o == null) return v;
    if (v == null) return o;
    return o.isAfter(v) ? o : v;
  }

  bool get isOwing => balance > 0.5;
  bool get needsVisit => lastContact == null || daysSince(lastContact!) >= needsVisitDays;
  bool get isInactive => lastOrder == null || daysSince(lastOrder!) >= inactiveDays;
  List<CrmFollowUp> get openFollowUps => followUps.where((f) => !f.done).toList();
}

/// Everything the CRM shows for one booker.
class CrmBook {
  final String userId;
  final String bookerName;
  final List<CrmCustomer> customers; // by name
  final List<CrmVisit> visits; // newest first
  final List<CrmFollowUp> followUps; // open first, by due date

  CrmBook({
    required this.userId,
    required this.bookerName,
    required this.customers,
    required this.visits,
    required this.followUps,
  });

  CrmCustomer? customer(String id) {
    for (final c in customers) {
      if (c.id == id) return c;
    }
    return null;
  }

  List<CrmFollowUp> get dueFollowUps => followUps.where((f) => f.isDue).toList();
  List<CrmFollowUp> get overdueFollowUps => followUps.where((f) => f.isOverdue).toList();
  /// Counted once per shop name: two customer records with the same name share one khata
  /// (invoices are keyed by name), so summing per record would count that balance twice.
  double get totalDue => {for (final c in customers) if (c.isOwing) c.name: c.balance}
      .values
      .fold(0.0, (s, b) => s + b);
  int visitsInLastDays(int days) => visits.where((v) => daysSince(v.date) < days).length;

  List<String> get allTags {
    final tags = <String>{};
    for (final c in customers) {
      tags.addAll(c.tags);
    }
    return tags.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }
}

// =============================================================================
// Loading
// =============================================================================

/// How long one CRM load may take before the screen shows an error with a retry, instead of
/// spinning forever (e.g. on a dropped connection).
const crmLoadTimeout = Duration(seconds: 45);

// The last book loaded per booker, so screens can show it at once and refresh in the background.
// The booker's bottom nav rebuilds the tab on every switch, which used to mean a full reload.
final _bookCache = <String, CrmBook>{};

CrmBook? cachedCrmBook(String userId) => _bookCache[userId];

/// Runs one query and logs how long it took, so a slow load can be traced in the debug console.
Future<T> _timed<T>(String label, Future<T> query) async {
  final watch = Stopwatch()..start();
  try {
    return await query;
  } finally {
    debugPrint('CRM: $label took ${watch.elapsedMilliseconds} ms');
  }
}

/// Loads a booker's shops with their khata, visits and follow-ups (and caches the result).
Future<CrmBook> loadCrmBook({required String userId, required String bookerName}) async {
  final db = FirebaseFirestore.instance;
  final results = await Future.wait<Object>([
    _timed('customers ($bookerName)', companyCol('customers').where('salesman', isEqualTo: bookerName).get()),
    _timed('invoices + khata ($bookerName)', loadKhata(userId)),
    _timed('visits ($bookerName)', companyCol('crm_visits').where('userId', isEqualTo: userId).get()),
    _timed('follow-ups ($bookerName)', companyCol('crm_followups').where('userId', isEqualTo: userId).get()),
  ]).timeout(crmLoadTimeout);

  final customers = (results[0] as QuerySnapshot<Map<String, dynamic>>)
      .docs
      .map(CrmCustomer.fromDoc)
      .where((c) => c.name.isNotEmpty)
      .toList()
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  final khata = results[1] as KhataBook;
  final visits = (results[2] as QuerySnapshot<Map<String, dynamic>>).docs.map(CrmVisit.fromDoc).toList()
    ..sort((a, b) {
      final byDate = b.date.compareTo(a.date);
      return byDate != 0 ? byDate : b.createdAt.compareTo(a.createdAt);
    });
  final followUps = (results[3] as QuerySnapshot<Map<String, dynamic>>).docs.map(CrmFollowUp.fromDoc).toList()
    ..sort((a, b) {
      if (a.done != b.done) return a.done ? 1 : -1;
      return a.done ? (b.doneAt ?? b.dueDate).compareTo(a.doneAt ?? a.dueDate) : a.dueDate.compareTo(b.dueDate);
    });

  final byId = {for (final c in customers) c.id: c};
  for (final c in customers) {
    c.khata = khata.shop(c.name); // invoices and khata entries are keyed by shop name
  }
  for (final v in visits) {
    byId[v.customerId]?.visits.add(v);
  }
  for (final f in followUps) {
    byId[f.customerId]?.followUps.add(f);
  }

  final book = CrmBook(userId: userId, bookerName: bookerName, customers: customers, visits: visits, followUps: followUps);
  _bookCache[userId] = book;
  return book;
}

class Booker {
  final String uid;
  final String name;
  final String email;
  const Booker(this.uid, this.name, this.email);
}

/// Every booker in the company who has logged in, by name.
Future<List<Booker>> loadBookers() async {
  final isBooker = await bookerFilter();
  final snap = await companyCol('sessions').get();
  return snap.docs
      .map((d) => d.data())
      .where((m) => isBooker((m['uid'] ?? '').toString(), (m['email'] ?? '').toString()))
      .map((m) => Booker(
            (m['uid'] ?? '').toString(),
            (m['username'] ?? m['email'] ?? '').toString().trim(),
            (m['email'] ?? '').toString(),
          ))
      .where((b) => b.uid.isNotEmpty && b.name.isNotEmpty)
      .toList()
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
}

String? _nameUid, _name;

/// The signed-in booker's username, read from their session once per login.
String? cachedBookerName() {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  return uid != null && uid == _nameUid ? _name : null;
}

/// The signed-in booker's username from their session, or '' if there is none.
Future<String> currentBookerName() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return '';
  final cached = cachedBookerName();
  if (cached != null) return cached;
  final snap = await _timed('session', companyCol('sessions').doc(user.uid).get())
      .timeout(crmLoadTimeout);
  final name = (snap.data()?['username'] ?? '').toString().trim();
  if (name.isNotEmpty) {
    _nameUid = user.uid;
    _name = name;
  }
  return name;
}

// =============================================================================
// Writing (signed-in booker)
// =============================================================================

Future<void> logVisit({
  required CrmCustomer customer,
  required VisitOutcome outcome,
  required DateTime date,
  String note = '',
}) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) throw Exception('Not logged in');
  await companyCol('crm_visits').add({
    'userId': user.uid,
    'userEmail': user.email ?? '',
    'customerId': customer.id,
    'customer': customer.name,
    'area': customer.area,
    'outcome': outcome.key,
    'note': note.trim(),
    'date': Timestamp.fromDate(date),
    'createdAt': FieldValue.serverTimestamp(),
  });
}

Future<void> deleteVisit(String id) => companyCol('crm_visits').doc(id).delete();

Future<void> addFollowUp({
  required CrmCustomer customer,
  required String title,
  required DateTime dueDate,
  String note = '',
}) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) throw Exception('Not logged in');
  await companyCol('crm_followups').add({
    'userId': user.uid,
    'userEmail': user.email ?? '',
    'customerId': customer.id,
    'customer': customer.name,
    'title': title.trim(),
    'note': note.trim(),
    'dueDate': Timestamp.fromDate(_dayOf(dueDate)),
    'done': false,
    'doneAt': null,
    'createdAt': FieldValue.serverTimestamp(),
  });
}

Future<void> setFollowUpDone(String id, bool done) =>
    companyCol('crm_followups').doc(id).update({
      'done': done,
      'doneAt': done ? FieldValue.serverTimestamp() : null,
    });

Future<void> deleteFollowUp(String id) => companyCol('crm_followups').doc(id).delete();

/// Sets a shop's credit limit (Rs) and credit days; 0 means no limit (office only).
Future<void> updateCustomerCredit(String customerId, {required double limit, required int days}) =>
    companyCol('customers').doc(customerId).update({'creditLimit': limit, 'creditDays': days});

/// Sets which product price a shop pays (office only). Keeps its type in step.
Future<void> updateCustomerTier(String customerId, String tier) => companyCol('customers').doc(customerId).update({
      'priceTier': tier,
      'type': switch (tier) { 'b2b' => 'Wholesaler', 'b2c' => 'Consumer', _ => 'Retailer' },
    });

/// Saves the CRM fields on the shop's `customers` document.
Future<void> updateCustomerCrm(String customerId, {List<String>? tags, String? notes}) =>
    companyCol('customers').doc(customerId).update({
      'tags': ?tags,
      if (notes != null) 'notes': notes.trim(),
    });
