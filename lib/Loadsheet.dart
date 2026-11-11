import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:an_agency/ui/app_theme.dart';
import 'account/account.dart';
import 'report_areas.dart';
import 'print_preview.dart';
import 'loadsheet_pdf.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pdf/widgets.dart' as pw;

// If you already have a shared _Tokens class (as used in your other screens),
// delete this block and just import that file instead — keep the same names.
class _Tokens {
  static const navy = AppColors.navy;
  static const navyDark = AppColors.navyDark;
  static const amber = AppColors.amber;
  static const bg = AppColors.bg;
  static const border = AppColors.border;
  static const textDark = AppColors.text;
  static const muted = AppColors.muted;
  static const error = AppColors.red;
}

class LoadSheetPage extends StatefulWidget {
  const LoadSheetPage({super.key});

  @override
  State<LoadSheetPage> createState() => _LoadSheetPageState();
}

class _LoadSheetPageState extends State<LoadSheetPage> {
  final db = FirebaseFirestore.instance;

  _LoadSheet? _todaySheet;
  bool _busy = false;

  // The day being reported on. Defaults to today; the calendar button picks another day, e.g. tomorrow,
  // when invoices are entered in advance with a later Sales Date.
  DateTime _reportDate = DateTime.now();

  bool get _isToday {
    final n = DateTime.now();
    return _reportDate.year == n.year && _reportDate.month == n.month && _reportDate.day == n.day;
  }

  Future<void> _pickReportDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _reportDate,
      firstDate: DateTime(2023),
      lastDate: now.add(const Duration(days: 365)),
      helpText: "Report for which Sales Date?",
    );
    if (picked == null || !mounted) return;
    setState(() { _reportDate = picked; _todaySheet = null; });
    await _loadToday(); // show that day's saved report if there is one
  }

  @override
  Widget build(BuildContext context) {
    final todayStr = _todayStr();

    return Scaffold(
      backgroundColor: _Tokens.bg,
      appBar: AppBar(
        elevation: 0,
        centerTitle: false,
        title: Text(
          "Load Sheet — $todayStr",
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w600,
            fontSize: 18,
            color: AppColors.text,
          ),
        ),
        actions: [
          IconButton(
            tooltip: "Change date",
            icon: const Icon(Icons.calendar_month_outlined),
            color: AppColors.text,
            onPressed: _busy ? null : _pickReportDate,
          ),
          IconButton(
            tooltip: "Load Saved Sheet",
            icon: const Icon(Icons.cloud_download_outlined),
            color: AppColors.text,
            onPressed: _busy ? null : _loadToday,
          ),
          IconButton(
            tooltip: "Print Preview",
            icon: const Icon(Icons.print_outlined),
            color: AppColors.text,
            onPressed: (_todaySheet == null || _busy) ? null : _printToday,
          ),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButton: _busy
          ? null
          : Container(
        margin: const EdgeInsets.only(bottom: 20, right: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: _Tokens.navy.withOpacity(0.18),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: FloatingActionButton.extended(
          backgroundColor: _Tokens.amber,
          foregroundColor: _Tokens.navyDark,
          elevation: 0,
          onPressed: _computeToday,
          icon: const Icon(Icons.calculate_outlined),
          label: Text(
            _isToday ? "Compute Today" : "Compute ${_todaySalesDate()}",
            style: GoogleFonts.inter(fontWeight: FontWeight.w600),
          ),
        ),
      ),
      body: _busy
          ? Center(
        child: CircularProgressIndicator(color: _Tokens.navy),
      )
          : _todaySheet == null
          ? _empty()
          // One vertical scroll for the whole page: the summary first, then the full table (all rows,
          // BONUS and TOTAL included) however many entries the day has. The table scrolls sideways in its card.
          : SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 140),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _summaryCard(_todaySheet!),
            const SizedBox(height: 16),
            _sheetView(_todaySheet!),
          ],
        ),
      ),
    );
  }

  Widget _empty() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: _Tokens.navy.withOpacity(0.06),
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.receipt_long_outlined,
              size: 40, color: _Tokens.navy.withOpacity(0.6)),
        ),
        const SizedBox(height: 16),
        Text(
          "No load sheet yet",
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w600,
            fontSize: 15,
            color: _Tokens.textDark,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          "Tap Compute to generate the load sheet for ${_todaySalesDate()}.\nUse the calendar button for another day.",
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(fontSize: 13, color: _Tokens.muted),
        ),
      ],
    ),
  );

  Widget _sheetView(_LoadSheet s) {
    final rows = [...s.items]..sort((a, b) => a.productName.compareTo(b.productName));

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _Tokens.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: _FullWidthScroll(
        child: DataTable(
          columnSpacing: 24,
          headingRowColor: MaterialStateProperty.all(_Tokens.navy.withOpacity(0.06)),
          headingTextStyle: GoogleFonts.inter(
            fontWeight: FontWeight.w600,
            color: _Tokens.navy,
            fontSize: 13,
          ),
          dataTextStyle: GoogleFonts.inter(
            fontSize: 13,
            color: _Tokens.textDark,
          ),
          columns: const [
            DataColumn(label: Text("Product")),
            DataColumn(label: Text("Qty"), numeric: true),
            DataColumn(label: Text("FOC"), numeric: true),
            DataColumn(label: Text("Amount (PKR)"), numeric: true),
          ],
          rows: rows
              .map(
                (r) => DataRow(cells: [
              DataCell(Text(r.productName)),
              DataCell(Text("${r.qty}")),
              DataCell(Text(_fmtQty(r.bns))),
              DataCell(Text(_fmtMoney(r.amount))),
            ]),
          )
              .toList(),
        ),
      ),
    );
  }

  Widget _summaryCard(_LoadSheet s) {
    final tiles = [
      _summaryBox("Unique Products", "${s.totals.uniqueProducts}", Icons.category_outlined),
      _summaryBox("Total Qty", "${s.totals.sumQty}", Icons.inventory_2_outlined),
      _summaryBox("Total FOC", _fmtQty(s.totals.sumBns), Icons.card_giftcard_outlined),
      _summaryBox("Total Sale", _fmtMoney(s.totals.sumAmount), Icons.payments_outlined,
          highlight: true),
    ];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _Tokens.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _isToday ? "Today's Summary" : "Summary · ${_todaySalesDate()}",
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w700,
              fontSize: 16,
              color: _Tokens.navy,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: tiles
                .map((t) => Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: t,
              ),
            ))
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _summaryBox(String title, String value, IconData icon, {bool highlight = false}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: highlight ? _Tokens.amber.withOpacity(0.14) : _Tokens.navy.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: highlight ? _Tokens.amber.withOpacity(0.4) : _Tokens.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: highlight ? _Tokens.amber : _Tokens.navy),
          const SizedBox(height: 10),
          Text(
            title,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _Tokens.muted,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: _Tokens.textDark,
            ),
          ),
        ],
      ),
    );
  }

  // -------------------- CORE ACTIONS (unchanged logic) --------------------

  Future<void> _computeToday() async {
    setState(() => _busy = true);
    try {
      final sheet = await _computeTodayFromInvoices();
      _todaySheet = sheet;

      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        await companyCol('load_sheets')
            .doc(_loadSheetDocId(uid))
            .set(sheet.toFirestore(), SetOptions(merge: false));
      }

      setState(() {});
      _toast("Computed & saved load sheet for ${_todaySalesDate()}");
    } catch (e) {
      _toast("Compute failed: $e", err: true);
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _loadToday() async {
    setState(() => _busy = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      final snap = await companyCol('load_sheets').doc(_loadSheetDocId(uid)).get();

      if (!snap.exists) {
        _toast("No load sheet saved for ${_todaySalesDate()} yet. Tap Compute.");
        return;
      }

      _todaySheet = _LoadSheet.fromFirestore(snap.data()!);
      setState(() {});
      _toast("Loaded saved load sheet");
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _printToday() async {
    final s = _todaySheet;
    if (s == null) return;

    try {
      final doc = await _buildPdf(s);
      if (!mounted) return;
      await showPrintPreview(
        context,
        title: "Load Sheet Preview",
        buildPdf: doc.save,
        fileName: "LoadSheet_${s.dateStr}.pdf",
      );
    } catch (e) {
      _toast("Print failed: $e", err: true);
    }
  }

  Future<String> _getUsernameFromSessionsByEmail(String? email) async {
    if (email == null || email.trim().isEmpty) return "Unknown";
    final snap = await companyCol('sessions').where("email", isEqualTo: email.trim()).limit(1).get();
    if (snap.docs.isEmpty) return "Unknown";
    return (snap.docs.first.data()["username"] ?? "").toString().trim();
  }

  Future<String> _getAreasForTodayByUser(String userId) => bookerDayAreas(userId, _todaySalesDate());

  // -------------------- COMPUTE FROM INVOICES (unchanged logic) --------------------

  Future<_LoadSheet> _computeTodayFromInvoices() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception("Not logged in");

    // The load sheet for a day = invoices whose Sales Date is that day (pick tomorrow to load tomorrow's stock).
    final q = await companyCol('invoices')
        .where("userId", isEqualTo: user.uid)
        .where("salesDate", isEqualTo: _todaySalesDate())
        .get();

    final qtyMap = <String, int>{};
    final bnsMap = <String, double>{};
    final amountMap = <String, double>{};
    double totalInvoiceDiscounts = 0.0;

    for (final doc in q.docs) {
      final data = doc.data();
      final items = (data["items"] as List?) ?? [];

      double ts = (data['total'] ?? 0).toDouble();
      double ns = (data['grandTotal'] ?? ts).toDouble();
      totalInvoiceDiscounts += (ts - ns);

      for (final it in items) {
        if (it is! Map) continue;

        final name = (it["Product Name"] ?? "").toString().trim();
        if (name.isEmpty) continue;

        final qv = _parseIntish((it["QTY"] ?? "0").toString());
        final bv = double.tryParse((it["BNS"] ?? it["FOC"] ?? "0").toString().trim()) ?? 0.0; // bonus can be fractional
        final itemGrossTotal = double.tryParse((it["Gross Total"] ?? "0").toString()) ?? 0.0;

        qtyMap[name] = (qtyMap[name] ?? 0) + qv;
        bnsMap[name] = (bnsMap[name] ?? 0.0) + bv;
        amountMap[name] = (amountMap[name] ?? 0.0) + itemGrossTotal;
      }
    }

    final rows = qtyMap.keys
        .map((p) => _LoadRow(
      productName: p,
      qty: qtyMap[p]!,
      bns: bnsMap[p] ?? 0.0,
      amount: amountMap[p]!,
    ))
        .toList()
      ..sort((a, b) => a.productName.compareTo(b.productName));

    double grossSumAmount = rows.fold(0.0, (a, b) => a + b.amount);
    double netSumAmount = grossSumAmount - totalInvoiceDiscounts;

    final totals = _LoadTotals(
      sumQty: rows.fold(0, (a, b) => a + b.qty),
      sumBns: rows.fold(0.0, (a, b) => a + b.bns),
      sumAmount: netSumAmount,
      uniqueProducts: rows.length,
    );

    return _LoadSheet(
      dateStr: _todayStr(),
      generatedAt: Timestamp.now(),
      userId: user.uid,
      userEmail: user.email,
      items: rows,
      totals: totals,
      areas: await _getAreasForTodayByUser(user.uid),
    );
  }

  // -------------------- PDF (unchanged logic) --------------------

  Future<pw.Document> _buildPdf(_LoadSheet s) async {
    final pdf = pw.Document();
    final printedUsername = await _getUsernameFromSessionsByEmail(s.userEmail);
    final printedAreas = s.userId == null ? "-" : await _getAreasForTodayByUser(s.userId!);
    pdf.addPage(
      pw.MultiPage(
        pageFormat: loadSheetPageFormat,
        build: (context) => loadSheetPdfContent(
          company: Account.companyName,
          dateStr: s.dateStr,
          booker: "$printedUsername (${s.userEmail ?? "-"})",
          areas: printedAreas,
          rows: s.items.map((r) => LoadSheetPdfRow(product: r.productName, qty: r.qty, bonus: r.bns, amount: r.amount)).toList(),
          netAmount: s.totals.sumAmount,
        ),
      ),
    );

    return pdf;
  }

  // -------------------- UTILS (unchanged logic) --------------------

  /// The report date as yyyy-MM-dd (saved report ID, title, PDF name).
  String _todayStr() {
    final n = _reportDate;
    return "${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}";
  }

  /// The report date in the invoices' Sales Date format (dd-MM-yyyy).
  String _todaySalesDate() {
    final n = _reportDate;
    return "${n.day.toString().padLeft(2, '0')}-${n.month.toString().padLeft(2, '0')}-${n.year}";
  }

  String _loadSheetDocId(String uid) => "${_todayStr()}__$uid";

  int _parseIntish(String s) {
    final i = int.tryParse(s);
    if (i != null) return i;
    final d = double.tryParse(s);
    return d?.round() ?? 0;
  }

  String _fmtMoney(double v) => v.toInt().toString();

  /// Whole numbers without ".0", fractions to at most 2 decimals (2 -> "2", 2.5 -> "2.5").
  String _fmtQty(num v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');
  }

  void _toast(String msg, {bool err = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.inter()),
        backgroundColor: err ? _Tokens.error : _Tokens.navy,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}

class _LoadSheet {
  final String dateStr;
  final Timestamp generatedAt;
  final String? userId;
  final String? userEmail;
  final _LoadTotals totals;
  final List<_LoadRow> items;
  final String areas; // printed header, saved so the admin's print shows it too

  _LoadSheet({required this.dateStr, required this.generatedAt, required this.userId, required this.userEmail, required this.items, required this.totals, this.areas = ''});

  Map<String, dynamic> toFirestore() => {
    "dateStr": dateStr,
    "generatedAt": generatedAt,
    "userId": userId,
    "userEmail": userEmail,
    "items": items.map((e) => e.toMap()).toList(),
    "totals": totals.toMap(),
    if (areas.isNotEmpty && areas != "-") "areas": areas,
  };

  static _LoadSheet fromFirestore(Map<String, dynamic> m) {
    return _LoadSheet(
      dateStr: m["dateStr"],
      generatedAt: m["generatedAt"],
      userId: m["userId"],
      userEmail: m["userEmail"],
      items: (m["items"] as List).map((e) => _LoadRow.fromMap(Map<String, dynamic>.from(e))).toList(),
      totals: _LoadTotals.fromMap(Map<String, dynamic>.from(m["totals"])),
      areas: (m["areas"] ?? "").toString(),
    );
  }
}

class _LoadTotals {
  final int sumQty;
  final double sumBns;
  final double sumAmount;
  final int uniqueProducts;

  _LoadTotals({required this.sumQty, required this.sumBns, required this.sumAmount, required this.uniqueProducts});

  Map<String, dynamic> toMap() => {"sumQty": sumQty, "sumBns": sumBns, "sumAmount": sumAmount, "uniqueProducts": uniqueProducts};

  static _LoadTotals fromMap(Map<String, dynamic> m) {
    return _LoadTotals(
      sumQty: m["sumQty"],
      sumBns: (m["sumBns"] ?? 0).toDouble(),
      sumAmount: (m["sumAmount"] ?? 0).toDouble(),
      uniqueProducts: m["uniqueProducts"],
    );
  }
}

class _LoadRow {
  final String productName;
  final int qty;
  final double bns;
  final double amount;

  _LoadRow({required this.productName, required this.qty, required this.bns, required this.amount});

  Map<String, dynamic> toMap() => {"productName": productName, "qty": qty, "bns": bns, "amount": amount};

  static _LoadRow fromMap(Map<String, dynamic> m) {
    return _LoadRow(
      productName: m["productName"],
      qty: m["qty"],
      bns: (m["bns"] ?? 0).toDouble(),
      amount: (m["amount"] ?? 0).toDouble(),
    );
  }
}

/// Lets a table fill the width of its card, and scroll sideways only when it is wider than the card.
class _FullWidthScroll extends StatelessWidget {
  final Widget child;
  const _FullWidthScroll({required this.child});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(constraints: BoxConstraints(minWidth: constraints.maxWidth), child: child),
        ),
      );
}
