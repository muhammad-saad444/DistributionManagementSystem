// Khata (shop udhaar ledger) for each booker.
//
// Udhaar comes from two places:
//   - every invoice the booker made (read live from `invoices`, so returns, edits and deletions
//     are reflected automatically and nothing is copied or double-counted);
//   - entries in `khata_entries`: payments received and manual udhaar (e.g. an old balance).
// Balance per shop = invoices + manual udhaar - payments.
//
// The booker uses this with editing on (Khata tab); the admin panel uses the same views read-only.
import 'dart:typed_data';
import 'package:an_agency/ui/app_theme.dart';
import 'account/account.dart';
import 'audit/audit.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'print_preview.dart';

class _Tokens {
  static const navy = AppColors.navy;
  static const navyDark = AppColors.navyDark;
  static const amber = AppColors.amber;
  static const amberBg = AppColors.amberBg;
  static const bg = AppColors.bg;
  static const border = AppColors.border;
  static const textDark = AppColors.text;
  static const muted = AppColors.muted;
  static const red = AppColors.red;
  static const redBg = AppColors.redBg;
  static const green = AppColors.green;
  static const greenBg = AppColors.greenBg;

  static TextStyle display({double size = 18, Color? color, FontWeight w = FontWeight.w700}) =>
      GoogleFonts.inter(fontSize: size, fontWeight: w, color: color ?? textDark);
  static TextStyle body({double size = 13, Color? color, FontWeight w = FontWeight.w400}) =>
      GoogleFonts.inter(fontSize: size, fontWeight: w, color: color ?? textDark);
}

final _money = NumberFormat('#,##0');
final _day = DateFormat('dd-MM-yyyy');
String _rs(num v) => 'Rs. ${_money.format(v.round())}';

// =============================================================================
// Data
// =============================================================================

enum KhataKind { invoice, udhaar, payment }

class KhataLine {
  final String id; // invoice id or khata_entries id
  final KhataKind kind;
  final DateTime date; // business date: the invoice's Sales Date, or the entry's date
  final DateTime createdAt; // orders lines that share a date
  final double amount; // always positive; payments reduce the balance
  final String title;
  final String note;
  final bool office; // a recovery the office entered on the Booker Credit Report (not deleted here)
  double balanceAfter = 0;
  // For an invoice or udhaar: how much of it payments have paid off (oldest first), and the date
  // of the payment that cleared it. Set by [settleOldestFirst].
  double settled = 0;
  DateTime? closedOn;

  KhataLine({
    required this.id,
    required this.kind,
    required this.date,
    required this.createdAt,
    required this.amount,
    required this.title,
    this.note = '',
    this.office = false,
  });

  double get signed => kind == KhataKind.payment ? -amount : amount;
  bool get isManual => kind != KhataKind.invoice;
  bool get isDebt => kind != KhataKind.payment;

  /// Still to be paid on this invoice or udhaar.
  double get due => isDebt ? (amount - settled).clamp(0, double.infinity).toDouble() : 0;

  /// Fully paid (within half a rupee). A zero-value invoice is closed from the start.
  bool get isClosed => isDebt && due < 0.5;
  bool get isPartlyPaid => isDebt && !isClosed && settled >= 0.5;
}

/// Pays off invoices and udhaar oldest first with the shop's payments, so each one can show
/// Closed, Partly paid or Open. [lines] must be oldest first. A payment larger than what is owed
/// at the time is kept as advance and pays the next invoices as they come.
void settleOldestFirst(List<KhataLine> lines) {
  final open = <KhataLine>[]; // debts not yet fully paid, oldest first
  var advance = 0.0;
  for (final l in lines) {
    l.settled = 0;
    l.closedOn = null;
  }
  for (final l in lines) {
    if (l.isDebt) {
      if (advance > 0) {
        final take = advance < l.amount ? advance : l.amount;
        l.settled += take;
        advance -= take;
      }
      if (l.isClosed) {
        l.closedOn = l.date;
      } else {
        open.add(l);
      }
      continue;
    }
    var money = l.amount;
    while (money > 0 && open.isNotEmpty) {
      final d = open.first;
      final take = money < d.due ? money : d.due;
      d.settled += take;
      money -= take;
      if (d.isClosed) {
        d.closedOn = l.date;
        open.removeAt(0);
      }
    }
    advance += money;
  }
}

class ShopKhata {
  final String customer;
  final List<KhataLine> lines; // oldest first, with running balances
  ShopKhata(this.customer, this.lines);

  double get balance => lines.isEmpty ? 0 : lines.last.balanceAfter;
  DateTime? get lastActivity => lines.isEmpty ? null : lines.last.date;
  int get openInvoices => lines.where((l) => l.kind == KhataKind.invoice && !l.isClosed).length;
  int get closedInvoices => lines.where((l) => l.kind == KhataKind.invoice && l.isClosed).length;
}

class KhataBook {
  final List<ShopKhata> shops; // highest balance first
  KhataBook(this.shops);

  double get totalDue => shops.fold(0.0, (s, k) => s + (k.balance > 0 ? k.balance : 0));
  int get shopsOwing => shops.where((k) => k.balance > 0.5).length;
  /// An invoice's khata line by invoice id (for its Closed / Open status), or null.
  KhataLine? invoiceLine(String invoiceId) {
    for (final s in shops) {
      for (final l in s.lines) {
        if (l.kind == KhataKind.invoice && l.id == invoiceId) return l;
      }
    }
    return null;
  }

  ShopKhata? shop(String customer) {
    for (final s in shops) {
      if (s.customer == customer) return s;
    }
    return null;
  }
}

DateTime? _asDate(dynamic v) => v is Timestamp ? v.toDate() : (v is DateTime ? v : null);

DateTime? _salesDate(dynamic v) {
  try {
    return _day.parseStrict((v ?? '').toString().trim());
  } catch (_) {
    return null;
  }
}

Future<QuerySnapshot<Map<String, dynamic>>?> _orNull(Future<QuerySnapshot<Map<String, dynamic>>> q) async {
  try {
    return await q;
  } catch (e) {
    debugPrint('Office recoveries not read: $e');
    return null;
  }
}

/// Loads a booker's whole khata: all their invoices plus their khata entries.
Future<KhataBook> loadKhata(String userId) async {
  final results = await Future.wait([
    companyCol('invoices').where('userId', isEqualTo: userId).get(),
    companyCol('khata_entries').where('userId', isEqualTo: userId).get(),
    // Recoveries the office entered on the Booker Credit Report before those were saved as khata
    // payments. Part of the Khata module: a company with CRM only can't read them, so skip them.
    _orNull(companyCol('customer_recoveries').where('userId', isEqualTo: userId).get()),
  ]);
  return buildKhataBook(results[0]!.docs, results[1]!.docs, results[2]?.docs ?? const []);
}

/// Every booker's khata at once (three reads for the whole company), by booker uid.
Future<Map<String, KhataBook>> loadCompanyKhata() async {
  final results = await Future.wait([
    companyCol('invoices').get(),
    companyCol('khata_entries').get(),
    _orNull(companyCol('customer_recoveries').get()),
  ]);
  String uidOf(QueryDocumentSnapshot<Map<String, dynamic>> d) => (d.data()['userId'] ?? '').toString();
  final byBooker = <String, List<List<QueryDocumentSnapshot<Map<String, dynamic>>>>>{};
  void add(int i, QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final uid = uidOf(d);
    if (uid.isEmpty) return;
    byBooker.putIfAbsent(uid, () => [[], [], []])[i].add(d);
  }

  for (final d in results[0]!.docs) {
    add(0, d);
  }
  for (final d in results[1]!.docs) {
    add(1, d);
  }
  for (final d in results[2]?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[]) {
    add(2, d);
  }
  return {for (final e in byBooker.entries) e.key: buildKhataBook(e.value[0], e.value[1], e.value[2])};
}

/// A booker's khata from their invoices, khata entries and office recoveries.
KhataBook buildKhataBook(
  List<QueryDocumentSnapshot<Map<String, dynamic>>> invoices,
  List<QueryDocumentSnapshot<Map<String, dynamic>>> entries,
  List<QueryDocumentSnapshot<Map<String, dynamic>>> recoveries,
) {
  final byShop = <String, List<KhataLine>>{};
  for (final d in recoveries) {
    final m = d.data();
    final customer = (m['customerName'] ?? '').toString().trim();
    final amount = (num.tryParse('${m['amountPaid'] ?? 0}') ?? 0).toDouble();
    if (customer.isEmpty || amount <= 0) continue;
    final created = _asDate(m['createdAt']) ?? DateTime.now();
    DateTime? day;
    try {
      day = DateFormat('yyyy-MM-dd').parseStrict((m['dateStr'] ?? '').toString());
    } catch (_) {}
    byShop.putIfAbsent(customer, () => []).add(KhataLine(
          id: d.id,
          kind: KhataKind.payment,
          date: day ?? created,
          createdAt: created,
          amount: amount,
          title: 'Recovery (office)',
          note: 'Booker Credit Report',
          office: true,
        ));
  }
  for (final d in invoices) {
    final m = d.data();
    final customer = (m['customer'] ?? '').toString().trim();
    if (customer.isEmpty) continue;
    final created = _asDate(m['createdAt']) ?? DateTime(2000);
    byShop.putIfAbsent(customer, () => []).add(KhataLine(
          id: d.id,
          kind: KhataKind.invoice,
          date: _salesDate(m['salesDate']) ?? created,
          createdAt: created,
          // grandTotal is what the shop owes after discount (and after any returns the admin processed)
          amount: (num.tryParse('${m['grandTotal'] ?? m['total'] ?? 0}') ?? 0).toDouble(),
          title: 'Invoice #${m['invoiceNumber'] ?? '-'}',
          note: (m['area'] ?? '').toString(),
        ));
  }
  for (final d in entries) {
    final m = d.data();
    final customer = (m['customer'] ?? '').toString().trim();
    if (customer.isEmpty) continue;
    final isPayment = m['type'] == 'payment';
    final method = (m['method'] ?? '').toString();
    final created = _asDate(m['createdAt']) ?? DateTime.now(); // null while the write is still pending
    byShop.putIfAbsent(customer, () => []).add(KhataLine(
          id: d.id,
          kind: isPayment ? KhataKind.payment : KhataKind.udhaar,
          date: _asDate(m['date']) ?? created,
          createdAt: created,
          amount: (num.tryParse('${m['amount'] ?? 0}') ?? 0).toDouble(),
          title: isPayment ? 'Payment received${method.isEmpty ? '' : ' ($method)'}' : 'Udhaar (manual)',
          note: (m['note'] ?? '').toString(),
        ));
  }

  final shops = byShop.entries.map((e) {
    final lines = e.value
      ..sort((a, b) {
        final byDate = DateTime(a.date.year, a.date.month, a.date.day)
            .compareTo(DateTime(b.date.year, b.date.month, b.date.day));
        return byDate != 0 ? byDate : a.createdAt.compareTo(b.createdAt);
      });
    var running = 0.0;
    for (final l in lines) {
      running += l.signed;
      l.balanceAfter = running;
    }
    settleOldestFirst(lines);
    return ShopKhata(e.key, lines);
  }).toList()
    ..sort((a, b) {
      final byBalance = b.balance.compareTo(a.balance);
      return byBalance != 0 ? byBalance : a.customer.toLowerCase().compareTo(b.customer.toLowerCase());
    });
  return KhataBook(shops);
}

/// Saves a payment ('payment') or manual udhaar ('udhaar') for the signed-in booker.
Future<void> addKhataEntry({
  required String customer,
  required String type,
  required double amount,
  required DateTime date,
  String method = '',
  String note = '',
}) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) throw Exception('Not logged in');
  await companyCol('khata_entries').add({
    'userId': user.uid,
    'userEmail': user.email ?? '',
    'customer': customer.trim(),
    'type': type,
    'amount': amount,
    'method': method,
    'note': note.trim(),
    'date': Timestamp.fromDate(DateTime(date.year, date.month, date.day)),
    'createdAt': FieldValue.serverTimestamp(),
  });
}

// =============================================================================
// Booker tab
// =============================================================================

/// The booker's own khata (bottom-nav tab).
class KhataPage extends StatefulWidget {
  const KhataPage({super.key});
  @override
  State<KhataPage> createState() => _KhataPageState();
}

class _KhataPageState extends State<KhataPage> {
  String _bookerName = '';

  @override
  void initState() {
    super.initState();
    _loadName();
  }

  Future<void> _loadName() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final snap = await companyCol('sessions').doc(user.uid).get();
      if (!mounted) return;
      setState(() => _bookerName = (snap.data()?['username'] ?? user.email ?? '').toString());
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return Scaffold(
      backgroundColor: _Tokens.bg,
      appBar: AppBar(
        elevation: 0,
        title: Text('Khata', style: _Tokens.display(size: 18, color: AppColors.text, w: FontWeight.w600)),
      ),
      body: uid == null
          ? Center(child: Text('Please log in', style: _Tokens.body(color: _Tokens.muted)))
          : KhataView(userId: uid, bookerName: _bookerName),
    );
  }
}

// =============================================================================
// Shop list (booker + admin)
// =============================================================================

/// A booker's khata: total due and the list of shops. [readOnly] hides adding/deleting (admin).
class KhataView extends StatefulWidget {
  final String userId;
  final String bookerName;
  final bool readOnly;
  const KhataView({super.key, required this.userId, required this.bookerName, this.readOnly = false});

  @override
  State<KhataView> createState() => _KhataViewState();
}

class _KhataViewState extends State<KhataView> {
  KhataBook? _book;
  Object? _error;
  bool _loading = true;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(KhataView old) {
    super.didUpdateWidget(old);
    if (old.userId != widget.userId) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _book == null;
      _error = null;
    });
    try {
      final book = await loadKhata(widget.userId);
      if (!mounted) return;
      setState(() {
        _book = book;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _openShop(String customer) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => KhataShopScreen(
          userId: widget.userId,
          bookerName: widget.bookerName,
          customer: customer,
          readOnly: widget.readOnly,
        ),
      ),
    );
    _load(); // balances may have changed
  }

  Future<void> _newEntryForAnyShop() async {
    final names = _book?.shops.map((s) => s.customer).toList() ?? <String>[];
    final saved = await showKhataEntrySheet(context, shopNames: names);
    if (saved == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: _Tokens.navy));
    if (_error != null && _book == null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text("Couldn't load the khata", style: _Tokens.body(color: _Tokens.red, w: FontWeight.w600)),
          TextButton(onPressed: _load, child: Text('Retry', style: _Tokens.body(color: _Tokens.navy))),
        ]),
      );
    }
    final book = _book!;
    final q = _search.trim().toLowerCase();
    final shops = q.isEmpty ? book.shops : book.shops.where((s) => s.customer.toLowerCase().contains(q)).toList();

    return Stack(
      children: [
        RefreshIndicator(
          color: _Tokens.navy,
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 96),
            children: [
              _totalCard(book),
              const SizedBox(height: 12),
              TextField(
                onChanged: (v) => setState(() => _search = v),
                style: _Tokens.body(),
                decoration: InputDecoration(
                  hintText: 'Search shop',
                  prefixIcon: const Icon(Icons.search, color: _Tokens.muted),
                  filled: true,
                  fillColor: Colors.white,
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _Tokens.border)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _Tokens.border)),
                ),
              ),
              const SizedBox(height: 12),
              if (book.shops.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 40),
                  child: Text(
                    widget.readOnly
                        ? 'No invoices or khata entries for this booker yet.'
                        : 'Your khata fills in automatically from your invoices.\nPayments you record will show here too.',
                    textAlign: TextAlign.center,
                    style: _Tokens.body(color: _Tokens.muted),
                  ),
                )
              else if (shops.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: Text('No shop matches "$_search"', textAlign: TextAlign.center, style: _Tokens.body(color: _Tokens.muted)),
                )
              else
                ...shops.map(_shopTile),
            ],
          ),
        ),
        if (!widget.readOnly)
          Positioned(
            right: 16,
            bottom: 16,
            child: FloatingActionButton.extended(
              heroTag: 'khata-new-entry',
              backgroundColor: _Tokens.amber,
              foregroundColor: _Tokens.navyDark,
              elevation: 2,
              icon: const Icon(Icons.add),
              label: Text('New entry', style: _Tokens.body(w: FontWeight.w700, color: _Tokens.navyDark)),
              onPressed: _newEntryForAnyShop,
            ),
          ),
      ],
    );
  }

  Widget _totalCard(KhataBook book) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [_Tokens.navy, AppColors.navyMid]),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.bookerName.isEmpty ? 'Total due' : 'Total due · ${widget.bookerName}',
                  style: _Tokens.body(size: 12, color: Colors.white70), overflow: TextOverflow.ellipsis),
              const SizedBox(height: 6),
              Text(_rs(book.totalDue), style: _Tokens.display(size: 26, color: Colors.white)),
              const SizedBox(height: 4),
              Text('${book.shopsOwing} of ${book.shops.length} shops owe money',
                  style: _Tokens.body(size: 12, color: Colors.white70)),
            ]),
          ),
          const Icon(Icons.menu_book_outlined, color: _Tokens.amber, size: 34),
        ],
      ),
    );
  }

  Widget _shopTile(ShopKhata s) {
    final bal = s.balance;
    final owes = bal > 0.5, advance = bal < -0.5;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _Tokens.border),
      ),
      child: ListTile(
        onTap: () => _openShop(s.customer),
        leading: CircleAvatar(
          backgroundColor: owes ? _Tokens.redBg : _Tokens.greenBg,
          child: Text(s.customer.isEmpty ? '?' : s.customer[0].toUpperCase(),
              style: _Tokens.body(w: FontWeight.w700, color: owes ? _Tokens.red : _Tokens.green)),
        ),
        title: Text(s.customer, style: _Tokens.body(size: 14, w: FontWeight.w600), overflow: TextOverflow.ellipsis),
        subtitle: Text(
            [
              if (s.openInvoices > 0) '${s.openInvoices} open',
              if (s.closedInvoices > 0) '${s.closedInvoices} closed',
              if (s.lastActivity != null) 'last ${_day.format(s.lastActivity!)}',
            ].join(' · '),
            style: _Tokens.body(size: 11.5, color: _Tokens.muted)),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(owes ? _rs(bal) : advance ? _rs(-bal) : 'Clear',
                style: _Tokens.body(size: 14, w: FontWeight.w700, color: owes ? _Tokens.red : _Tokens.green)),
            Text(owes ? 'due' : advance ? 'advance' : '', style: _Tokens.body(size: 11, color: _Tokens.muted)),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// One shop's ledger
// =============================================================================

class KhataShopScreen extends StatefulWidget {
  final String userId;
  final String bookerName;
  final String customer;
  final bool readOnly;
  const KhataShopScreen({
    super.key,
    required this.userId,
    required this.bookerName,
    required this.customer,
    this.readOnly = false,
  });

  @override
  State<KhataShopScreen> createState() => _KhataShopScreenState();
}

class _KhataShopScreenState extends State<KhataShopScreen> {
  ShopKhata? _shop;
  String _show = 'all'; // all, open, closed

  List<KhataLine> _shown(ShopKhata s) => switch (_show) {
        'open' => s.lines.where((l) => l.isDebt && !l.isClosed).toList(),
        'closed' => s.lines.where((l) => l.isDebt && l.isClosed).toList(),
        _ => s.lines,
      };
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final book = await loadKhata(widget.userId);
      if (!mounted) return;
      setState(() {
        _shop = book.shop(widget.customer) ?? ShopKhata(widget.customer, []);
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _addEntry(String type) async {
    final saved = await showKhataEntrySheet(
      context,
      customer: widget.customer,
      type: type,
      suggestedAmount: type == 'payment' && (_shop?.balance ?? 0) > 0 ? _shop!.balance : null,
    );
    if (saved == true) _load();
  }

  Future<void> _delete(KhataLine l) async {
    if (!await ensureOpenPeriod(context, l.date) || !mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Delete entry?', style: _Tokens.display(size: 17)),
        content: Text('${l.title} · ${_rs(l.amount)} on ${_day.format(l.date)}', style: _Tokens.body(color: _Tokens.muted)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text('Cancel', style: _Tokens.body(color: _Tokens.muted))),
          TextButton(onPressed: () => Navigator.pop(c, true), child: Text('Delete', style: _Tokens.body(color: _Tokens.red, w: FontWeight.w700))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await companyCol('khata_entries').doc(l.id).delete();
      logAudit(
        area: AuditArea.payment,
        action: AuditAction.delete,
        refId: l.id,
        title: '${l.title} · ${widget.customer}',
        amount: l.amount,
        changes: [AuditChange('Date', _day.format(l.date), ''), if (l.note.isNotEmpty) AuditChange('Note', l.note, '')],
      );
      _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't delete the entry. Try again.")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final shop = _shop;
    return Scaffold(
      backgroundColor: _Tokens.bg,
      appBar: AppBar(
        elevation: 0,
        title: Text(widget.customer, style: _Tokens.display(size: 17, color: AppColors.text, w: FontWeight.w600), overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Print / share statement',
            icon: const Icon(Icons.print_outlined, color: AppColors.text),
            onPressed: shop == null || shop.lines.isEmpty
                ? null
                : () => showPrintPreview(
                      context,
                      title: 'Khata · ${widget.customer}',
                      buildPdf: () => _statementPdf(shop, widget.bookerName),
                      fileName: 'Khata_${widget.customer.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')}.pdf',
                    ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _Tokens.navy))
          : _error != null
              ? Center(child: TextButton(onPressed: _load, child: Text("Couldn't load. Retry", style: _Tokens.body(color: _Tokens.red))))
              : RefreshIndicator(
                  color: _Tokens.navy,
                  onRefresh: _load,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(14),
                    children: [
                      _balanceCard(shop!),
                      if (!widget.readOnly) ...[
                        const SizedBox(height: 12),
                        Row(children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _Tokens.green,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(vertical: 13),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              icon: const Icon(Icons.call_received, size: 18),
                              label: Text('Payment received', style: _Tokens.body(w: FontWeight.w700, color: Colors.white)),
                              onPressed: () => _addEntry('payment'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: _Tokens.red,
                                side: const BorderSide(color: _Tokens.red),
                                padding: const EdgeInsets.symmetric(vertical: 13),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              icon: const Icon(Icons.call_made, size: 18),
                              label: Text('Add udhaar', style: _Tokens.body(w: FontWeight.w700, color: _Tokens.red)),
                              onPressed: () => _addEntry('udhaar'),
                            ),
                          ),
                        ]),
                      ],
                      const SizedBox(height: 16),
                      Text('Entries', style: _Tokens.display(size: 15, color: _Tokens.navy)),
                      const SizedBox(height: 8),
                      if (shop.lines.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Wrap(spacing: 8, children: [
                            for (final (key, label) in [
                              ('all', 'All'),
                              ('open', 'Open (${shop.lines.where((l) => l.isDebt && !l.isClosed).length})'),
                              ('closed', 'Closed (${shop.lines.where((l) => l.isDebt && l.isClosed).length})'),
                            ])
                              ChoiceChip(
                                label: Text(label, style: _Tokens.body(size: 12, w: FontWeight.w600,
                                    color: _show == key ? _Tokens.navyDark : _Tokens.muted)),
                                selected: _show == key,
                                selectedColor: _Tokens.amberBg,
                                backgroundColor: Colors.white,
                                side: const BorderSide(color: _Tokens.border),
                                showCheckmark: false,
                                onSelected: (_) => setState(() => _show = key),
                              ),
                          ]),
                        ),
                      if (_shown(shop).isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 20),
                          child: Text(
                              shop.lines.isEmpty
                                  ? 'No entries yet.'
                                  : _show == 'open'
                                      ? 'Nothing open. Every invoice is paid.'
                                      : 'No closed invoices yet.',
                              textAlign: TextAlign.center,
                              style: _Tokens.body(color: _Tokens.muted)),
                        ),
                      ..._shown(shop).reversed.map(_lineTile), // newest first
                    ],
                  ),
                ),
    );
  }

  Widget _balanceCard(ShopKhata s) {
    final bal = s.balance;
    final owes = bal > 0.5, advance = bal < -0.5;
    final udhaar = s.lines.where((l) => l.kind != KhataKind.payment).fold(0.0, (a, l) => a + l.amount);
    final paid = s.lines.where((l) => l.kind == KhataKind.payment).fold(0.0, (a, l) => a + l.amount);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: owes ? _Tokens.redBg : _Tokens.greenBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: owes ? _Tokens.red.withValues(alpha: .25) : _Tokens.green.withValues(alpha: .25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(owes ? 'Shop owes' : advance ? 'Advance with you' : 'All clear', style: _Tokens.body(size: 12.5, color: _Tokens.muted)),
        const SizedBox(height: 4),
        Text(_rs(bal.abs()), style: _Tokens.display(size: 26, color: owes ? _Tokens.red : _Tokens.green)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _mini('Total udhaar', _rs(udhaar))),
          Expanded(child: _mini('Total received', _rs(paid))),
        ]),
      ]),
    );
  }

  Widget _mini(String label, String value) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: _Tokens.body(size: 11, color: _Tokens.muted)),
        Text(value, style: _Tokens.body(size: 13.5, w: FontWeight.w700)),
      ]);

  Widget _lineTile(KhataLine l) {
    final isPay = l.kind == KhataKind.payment;
    final icon = l.kind == KhataKind.invoice
        ? Icons.receipt_long_outlined
        : isPay
            ? Icons.call_received
            : Icons.edit_note;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: _Tokens.border)),
      child: Row(children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: isPay ? _Tokens.greenBg : (l.kind == KhataKind.invoice ? _Tokens.amberBg : _Tokens.redBg),
          child: Icon(icon, size: 18, color: isPay ? _Tokens.green : (l.kind == KhataKind.invoice ? AppColors.amberDark : _Tokens.red)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l.title, style: _Tokens.body(w: FontWeight.w600)),
            Text([_day.format(l.date), if (l.note.isNotEmpty) l.note].join(' · '),
                style: _Tokens.body(size: 11.5, color: _Tokens.muted), maxLines: 2, overflow: TextOverflow.ellipsis),
            if (l.isDebt) Padding(padding: const EdgeInsets.only(top: 4), child: KhataStatusPill(l)),
          ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('${isPay ? '−' : '+'} ${_rs(l.amount)}', style: _Tokens.body(w: FontWeight.w700, color: isPay ? _Tokens.green : _Tokens.red)),
          Text('Bal ${_rs(l.balanceAfter)}', style: _Tokens.body(size: 11, color: _Tokens.muted)),
        ]),
        if (!widget.readOnly && l.isManual && !l.office)
          IconButton(
            tooltip: 'Delete entry',
            icon: const Icon(Icons.delete_outline, size: 20, color: _Tokens.muted),
            onPressed: () => _delete(l),
          )
        else
          const SizedBox(width: 8),
      ]),
    );
  }
}

/// Closed (paid in full), Partly paid (with what is left) or Open, for an invoice or udhaar.
class KhataStatusPill extends StatelessWidget {
  final KhataLine line;
  const KhataStatusPill(this.line, {super.key});

  @override
  Widget build(BuildContext context) {
    final l = line;
    final (String text, Color color, Color bg, IconData icon) = l.isClosed
        ? ('Closed${l.closedOn == null ? '' : ' · ${_day.format(l.closedOn!)}'}', _Tokens.green, _Tokens.greenBg, Icons.check_circle)
        : l.isPartlyPaid
            ? ('Partly paid · ${_rs(l.due)} left', AppColors.amberDark, _Tokens.amberBg, Icons.timelapse)
            : ('Open · ${_rs(l.due)} due', _Tokens.red, _Tokens.redBg, Icons.radio_button_unchecked);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Text(text, style: _Tokens.body(size: 11, color: color, w: FontWeight.w700)),
      ]),
    );
  }
}

// =============================================================================
// Entry form
// =============================================================================

/// Bottom sheet to record a payment or manual udhaar. Returns true when saved.
/// Without [customer], the booker types or picks the shop (from [shopNames]).
Future<bool?> showKhataEntrySheet(
  BuildContext context, {
  String? customer,
  String type = 'payment',
  double? suggestedAmount,
  List<String> shopNames = const [],
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
    builder: (_) => _KhataEntrySheet(customer: customer, type: type, suggestedAmount: suggestedAmount, shopNames: shopNames),
  );
}

class _KhataEntrySheet extends StatefulWidget {
  final String? customer;
  final String type;
  final double? suggestedAmount;
  final List<String> shopNames;
  const _KhataEntrySheet({this.customer, required this.type, this.suggestedAmount, required this.shopNames});

  @override
  State<_KhataEntrySheet> createState() => _KhataEntrySheetState();
}

class _KhataEntrySheetState extends State<_KhataEntrySheet> {
  late String _type = widget.type;
  TextEditingController? _shopField; // the autocomplete's own field, when the shop isn't fixed
  late final _amount = TextEditingController(
      text: widget.suggestedAmount == null ? '' : widget.suggestedAmount!.round().toString());
  final _note = TextEditingController();
  String _method = 'Cash';
  DateTime _date = DateTime.now();
  bool _saving = false;
  String? _error;

  Future<void> _save() async {
    final shop = (widget.customer ?? _shopField?.text ?? '').trim();
    final amount = double.tryParse(_amount.text.replaceAll(',', '').trim()) ?? 0;
    if (shop.isEmpty) return setState(() => _error = 'Enter the shop name');
    if (amount <= 0) return setState(() => _error = 'Enter an amount greater than 0');
    if (!await ensureOpenPeriod(context, _date)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await addKhataEntry(
        customer: shop,
        type: _type,
        amount: amount,
        date: _date,
        method: _type == 'payment' ? _method : '',
        note: _note.text,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = "Couldn't save. Check your internet connection and try again.";
        });
      }
    }
  }

  InputDecoration _dec(String label) => InputDecoration(
        labelText: label,
        labelStyle: _Tokens.body(color: _Tokens.muted),
        filled: true,
        fillColor: _Tokens.bg,
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _Tokens.border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _Tokens.amber, width: 1.5)),
      );

  @override
  Widget build(BuildContext context) {
    final isPay = _type == 'payment';
    return Padding(
      padding: EdgeInsets.fromLTRB(18, 12, 18, 18 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(width: 40, height: 5, decoration: BoxDecoration(color: _Tokens.border, borderRadius: BorderRadius.circular(10))),
            ),
            const SizedBox(height: 14),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'payment', label: Text('Payment received'), icon: Icon(Icons.call_received)),
                ButtonSegment(value: 'udhaar', label: Text('Add udhaar'), icon: Icon(Icons.call_made)),
              ],
              selected: {_type},
              onSelectionChanged: (s) => setState(() => _type = s.first),
            ),
            const SizedBox(height: 14),
            if (widget.customer == null)
              Autocomplete<String>(
                optionsBuilder: (v) => widget.shopNames.where((n) => n.toLowerCase().contains(v.text.toLowerCase())),
                fieldViewBuilder: (context, ctrl, focus, onSubmit) {
                  _shopField = ctrl;
                  return TextField(controller: ctrl, focusNode: focus, style: _Tokens.body(), decoration: _dec('Shop name'));
                },
              )
            else
              Text(widget.customer!, style: _Tokens.display(size: 16)),
            const SizedBox(height: 12),
            TextField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: _Tokens.body(size: 16, w: FontWeight.w600),
              decoration: _dec('Amount (Rs.)'),
            ),
            if (isPay) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: ['Cash', 'Online', 'Cheque']
                    .map((m) => ChoiceChip(
                          label: Text(m, style: _Tokens.body(size: 12.5)),
                          selected: _method == m,
                          selectedColor: _Tokens.amberBg,
                          onSelected: (_) => setState(() => _method = m),
                        ))
                    .toList(),
              ),
            ],
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.calendar_today_outlined, size: 16, color: _Tokens.navy),
                  label: Text(_day.format(_date), style: _Tokens.body(color: _Tokens.navy, w: FontWeight.w600)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    side: const BorderSide(color: _Tokens.border),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _date,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (picked != null) setState(() => _date = picked);
                  },
                ),
              ),
            ]),
            const SizedBox(height: 12),
            TextField(controller: _note, style: _Tokens.body(), decoration: _dec('Note (optional)')),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: _Tokens.body(color: _Tokens.red, size: 12.5)),
            ],
            const SizedBox(height: 16),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: isPay ? _Tokens.green : _Tokens.red,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(isPay ? 'Save payment' : 'Save udhaar', style: _Tokens.body(w: FontWeight.w700, color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// PDF statement (one shop)
// =============================================================================

Future<Uint8List> _statementPdf(ShopKhata shop, String bookerName) async {
  final doc = pw.Document();
  final udhaar = shop.lines.where((l) => l.kind != KhataKind.payment).fold(0.0, (a, l) => a + l.amount);
  final paid = shop.lines.where((l) => l.kind == KhataKind.payment).fold(0.0, (a, l) => a + l.amount);
  pw.Widget cell(String t, {bool bold = false, pw.TextAlign align = pw.TextAlign.right, PdfColor? color}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
        child: pw.Text(t, textAlign: align, style: pw.TextStyle(fontSize: 9, fontWeight: bold ? pw.FontWeight.bold : null, color: color)),
      );
  String m(double v) => _money.format(v.round());

  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4.copyWith(marginLeft: 36, marginRight: 36, marginTop: 36, marginBottom: 36),
    build: (_) => [
      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
        pw.Text(Account.companyName, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
        pw.Text('Khata Statement', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
        pw.Text(_day.format(DateTime.now()), style: const pw.TextStyle(fontSize: 10)),
      ]),
      pw.SizedBox(height: 6),
      pw.Text('Shop: ${shop.customer}', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
      if (bookerName.isNotEmpty) pw.Text('Booker: $bookerName', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
      pw.SizedBox(height: 12),
      pw.Table(
        border: pw.TableBorder.all(color: PdfColors.grey500, width: 0.5),
        columnWidths: const {
          0: pw.FixedColumnWidth(62),
          1: pw.FlexColumnWidth(1),
          2: pw.FixedColumnWidth(70),
          3: pw.FixedColumnWidth(70),
          4: pw.FixedColumnWidth(76),
          5: pw.FixedColumnWidth(64),
        },
        children: [
          pw.TableRow(repeat: true, decoration: const pw.BoxDecoration(color: PdfColors.grey300), children: [
            cell('Date', bold: true, align: pw.TextAlign.left),
            cell('Details', bold: true, align: pw.TextAlign.left),
            cell('Udhaar', bold: true),
            cell('Received', bold: true),
            cell('Balance', bold: true),
            cell('Status', bold: true, align: pw.TextAlign.left),
          ]),
          ...shop.lines.map((l) => pw.TableRow(children: [
                cell(_day.format(l.date), align: pw.TextAlign.left),
                cell(l.note.isEmpty ? l.title : '${l.title} · ${l.note}', align: pw.TextAlign.left),
                cell(l.kind == KhataKind.payment ? '' : m(l.amount)),
                cell(l.kind == KhataKind.payment ? m(l.amount) : ''),
                cell(m(l.balanceAfter)),
                cell(
                  !l.isDebt ? '' : l.isClosed ? 'Closed' : l.isPartlyPaid ? '${m(l.due)} left' : 'Open',
                  align: pw.TextAlign.left,
                  color: !l.isDebt ? null : l.isClosed ? PdfColors.green800 : PdfColors.red800,
                ),
              ])),
          pw.TableRow(decoration: const pw.BoxDecoration(color: PdfColors.grey100), children: [
            cell(''),
            cell('TOTAL', bold: true, align: pw.TextAlign.left),
            cell(m(udhaar), bold: true),
            cell(m(paid), bold: true),
            cell(m(shop.balance), bold: true, color: shop.balance > 0.5 ? PdfColors.red800 : PdfColors.green800),
            cell(''),
          ]),
        ],
      ),
      pw.SizedBox(height: 10),
      pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(
          shop.balance > 0.5
              ? 'Amount due: PKR ${m(shop.balance)}'
              : shop.balance < -0.5
                  ? 'Advance: PKR ${m(-shop.balance)}'
                  : 'All clear',
          style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
        ),
      ),
    ],
  ));
  return doc.save();
}
