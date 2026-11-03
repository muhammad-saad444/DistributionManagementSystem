// ignore_for_file: prefer_const_constructors, prefer_const_literals_to_create_immutables

import 'package:cloud_firestore/cloud_firestore.dart';
import 'print_preview.dart';
import 'dsr_pdf_table.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

// Delete this block and import your shared _Tokens file if you already have one.
class _Tokens {
  static const navy = Color(0xFF15294D);
  static const navyDark = Color(0xFF0E1D38);
  static const amber = Color(0xFFE0A63A);
  static const bg = Color(0xFFF5F6FA);
  static const border = Color(0xFFE3E7EF);
  static const textDark = Color(0xFF1E2430);
  static const muted = Color(0xFF6B7280);
  static const error = Color(0xFFD64545);
}

class DsrReportsPage extends StatefulWidget {
  const DsrReportsPage({super.key});
  @override
  State<DsrReportsPage> createState() => _DsrReportsPageState();
}

class _DsrReportsPageState extends State<DsrReportsPage> {
  final db = FirebaseFirestore.instance;
  InvoiceDsrReport? _todayReport;
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
    setState(() { _reportDate = picked; _todayReport = null; });
    await _loadTodayReport(); // show that day's saved report if there is one
  }

  @override
  Widget build(BuildContext context) {
    final todayStr = _todayStr();

    return Scaffold(
      backgroundColor: _Tokens.bg,
      appBar: AppBar(
        backgroundColor: _Tokens.navy,
        elevation: 0,
        centerTitle: false,
        title: Text(
          'Daily Sales Report — $todayStr',
          style: GoogleFonts.sora(
            fontWeight: FontWeight.w600,
            fontSize: 18,
            color: Colors.white,
          ),
        ),
        actions: [
          IconButton(
            tooltip: "Change date",
            icon: const Icon(Icons.calendar_month_outlined),
            color: Colors.white,
            onPressed: _busy ? null : _pickReportDate,
          ),
          IconButton(
            tooltip: 'Load saved DSR',
            icon: const Icon(Icons.cloud_download_outlined),
            color: Colors.white,
            onPressed: _busy ? null : _loadTodayReport,
          ),
          IconButton(
            tooltip: 'Print Preview',
            icon: const Icon(Icons.print_outlined),
            color: Colors.white,
            onPressed: (_todayReport == null || _busy) ? null : _showPrintPreview,
          ),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButton: _busy
          ? null
          : Container(
        margin: const EdgeInsets.only(bottom: 6, right: 4),
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
          icon: const Icon(Icons.calculate_outlined),
          label: Text(
            _isToday ? 'Compute Today' : 'Compute ${_todaySalesDate()}',
            style: GoogleFonts.sora(fontWeight: FontWeight.w600),
          ),
          onPressed: _computeTodayAndShow,
        ),
      ),
      body: _busy
          ? Center(child: CircularProgressIndicator(color: _Tokens.navy))
          : _todayReport == null
          ? _empty()
          // One vertical scroll for the whole page: the summary first, then the full table (all rows,
          // BONUS and TOTAL included) however many entries the day has. The table scrolls sideways in its card.
          : SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 90),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _summaryCard(_todayReport!),
            const SizedBox(height: 16),
            _reportView(_todayReport!),
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
          child: Icon(Icons.summarize_outlined,
              size: 40, color: _Tokens.navy.withOpacity(0.6)),
        ),
        const SizedBox(height: 16),
        Text(
          "No DSR loaded",
          style: GoogleFonts.sora(
            fontWeight: FontWeight.w600,
            fontSize: 15,
            color: _Tokens.textDark,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          "Compute or load the report for ${_todaySalesDate()}.\nUse the calendar button for another day.",
          textAlign: TextAlign.center,
          style: GoogleFonts.sora(fontSize: 13, color: _Tokens.muted),
        ),
      ],
    ),
  );

  // ----------------------
  // DSR TABLE VIEW
  // ----------------------
  Widget _reportView(InvoiceDsrReport report) {
    final rows = report.rows;
    final allProducts = <String>{};
    for (var r in rows) allProducts.addAll(r.productQty.keys);
    final productList = allProducts.toList()..sort();

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
          headingRowColor: MaterialStateProperty.all(_Tokens.navy.withOpacity(0.06)),
          columnSpacing: 22,
          headingTextStyle: GoogleFonts.sora(
            fontWeight: FontWeight.w600,
            color: _Tokens.navy,
            fontSize: 13,
          ),
          dataTextStyle: GoogleFonts.sora(fontSize: 13, color: _Tokens.textDark),
          columns: [
            const DataColumn(label: Text("Invoice #")),
            const DataColumn(label: Text("Customer")),
            ...productList.map((p) => DataColumn(label: Text(p), numeric: true)),
            const DataColumn(label: Text("Total Sale"), numeric: true),
            const DataColumn(label: Text("Discount"), numeric: true),
            const DataColumn(label: Text("Net Sale"), numeric: true),
          ],
          rows: List.generate(rows.length, (i) {
            final r = rows[i];
            return DataRow(
              cells: [
                DataCell(Text(r.invoiceNumber.isEmpty ? "-" : r.invoiceNumber)),
                DataCell(Text(r.customer)),
                ...productList.map((p) {
                  int q = r.productQty[p] ?? 0;
                  int ret = r.returnQty[p] ?? 0;
                  String display = ret > 0 ? "$q (R:$ret)" : "$q";
                  return DataCell(
                    Text(
                      display,
                      style: GoogleFonts.sora(
                        fontSize: 13,
                        color: ret > 0 ? _Tokens.error : _Tokens.textDark,
                        fontWeight: ret > 0 ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  );
                }),
                DataCell(Text(_formatInt(r.totalSale))),
                DataCell(Text(_formatInt(r.discount))),
                DataCell(Text(
                  _formatInt(r.netSale),
                  style: GoogleFonts.sora(fontWeight: FontWeight.w600, color: _Tokens.navy),
                )),
              ],
            );
          })
            ..addAll(_summaryRows(rows, productList)),
        ),
      ),
    );
  }

  // ----------------------
  // SUMMARY CARD
  // ----------------------
  Widget _summaryCard(InvoiceDsrReport report) {
    final totalSale = _formatInt(report.rows.fold<double>(0, (a, b) => a + b.totalSale));
    final netSale = _formatInt(report.rows.fold<double>(0, (a, b) => a + b.netSale));

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
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _isToday ? "Today's Summary" : "Summary · ${_todaySalesDate()}",
            style: GoogleFonts.sora(
              fontWeight: FontWeight.w700,
              fontSize: 16,
              color: _Tokens.navy,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _summaryBox("Total Invoices", "${report.rows.length}", Icons.receipt_long_outlined),
              const SizedBox(width: 12),
              _summaryBox("Total Sale", totalSale, Icons.point_of_sale_outlined),
              const SizedBox(width: 12),
              _summaryBox("Net Sale", netSale, Icons.payments_outlined, highlight: true),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryBox(String title, String value, IconData icon, {bool highlight = false}) {
    return Expanded(
      child: Container(
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
              style: GoogleFonts.sora(fontSize: 12, fontWeight: FontWeight.w600, color: _Tokens.muted),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: GoogleFonts.sora(fontSize: 17, fontWeight: FontWeight.w700, color: _Tokens.textDark),
            ),
          ],
        ),
      ),
    );
  }

  /// BONUS (free units per product) and TOTAL rows under the invoices. Net sale comes from the
  /// invoices' priced quantities only; bonus units are never added to it.
  List<DataRow> _summaryRows(List<InvoiceDsrRow> rows, List<String> productList) {
    final bold = GoogleFonts.sora(fontSize: 13, fontWeight: FontWeight.w700, color: _Tokens.textDark);
    return [
      DataRow(
        color: MaterialStateProperty.all(_Tokens.amber.withOpacity(0.12)),
        cells: [
          const DataCell(Text("")),
          DataCell(Text("FOC", style: bold)),
          ...productList.map((p) => DataCell(Text(_fmtQty(rows.fold<double>(0, (s, r) => s + (r.bonusQty[p] ?? 0))), style: bold))),
          const DataCell(Text("")), const DataCell(Text("")), const DataCell(Text("")),
        ],
      ),
      DataRow(
        color: MaterialStateProperty.all(_Tokens.navy.withOpacity(0.05)),
        cells: [
          const DataCell(Text("")),
          DataCell(Text("TOTAL", style: bold)),
          ...productList.map((p) => DataCell(Text("${rows.fold<int>(0, (s, r) => s + (r.productQty[p] ?? 0))}", style: bold))),
          DataCell(Text(_formatInt(rows.fold(0.0, (a, b) => a + b.totalSale)), style: bold)),
          DataCell(Text(_formatInt(rows.fold(0.0, (a, b) => a + b.discount)), style: bold)),
          DataCell(Text(_formatInt(rows.fold(0.0, (a, b) => a + b.netSale)),
              style: GoogleFonts.sora(fontSize: 13, fontWeight: FontWeight.w700, color: _Tokens.navy))),
        ],
      ),
    ];
  }

  // ----------------------
  // PDF BUILDER (unchanged logic)
  // ----------------------
  Future<pw.Document> _buildPdf(InvoiceDsrReport rep) async {
    final pdf = pw.Document();
    final printedUsername = await _getUsernameFromSessionsByEmail(rep.userEmail);
    final areas = rep.rows.map((r) => r.area).where((a) => a.trim().isNotEmpty).toSet().join(", ");

    final allProducts = <String>{};
    for (var r in rep.rows) allProducts.addAll(r.productQty.keys);
    final productList = allProducts.toList()..sort();

    // Products sold + returned per product, e.g. "40" or "40\nR:3" (kept on two lines so columns stay narrow).
    String qtyText(int q, int r) => r > 0 ? "$q\nR:$r" : "$q";
    final prodTotals = <String, String>{};
    for (var p in productList) {
      int sSum = rep.rows.fold(0, (sum, r) => sum + (r.productQty[p] ?? 0));
      int rSum = rep.rows.fold(0, (sum, r) => sum + (r.returnQty[p] ?? 0));
      prodTotals[p] = qtyText(sSum, rSum);
    }
    final prodBonus = {
      for (final p in productList) p: _fmtQty(rep.rows.fold<double>(0, (sum, r) => sum + (r.bonusQty[p] ?? 0))),
    };

    pdf.addPage(
      pw.MultiPage(
        pageFormat: dsrPageFormat,
        build: (context) => [
          pw.Header(
            level: 0,
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text("A.N Agency - Daily Sales Report", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13)),
                pw.Text(rep.dateStr, style: pw.TextStyle(fontSize: 10)),
              ],
            ),
          ),
          // Bold and black so the booker and area stay readable on printed paper.
          pw.Text("Booker: $printedUsername  |  Area: ${areas.isEmpty ? "-" : areas}",
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.black)),
          pw.SizedBox(height: 8),

          ...dsrPdfTables(
            availableWidth: dsrPageFormat.availableWidth,
            products: productList,
            rows: rep.rows.map((r) => DsrPdfRow(
              invoice: r.invoiceNumber.isEmpty ? "-" : r.invoiceNumber,
              customer: r.customer,
              qty: {for (final p in productList) p: qtyText(r.productQty[p] ?? 0, r.returnQty[p] ?? 0)},
              totalSale: _formatInt(r.totalSale),
              discount: _formatInt(r.discount),
              netSale: _formatInt(r.netSale),
            )).toList(),
            productTotals: prodTotals,
            productBonus: prodBonus,
            totalSale: _formatInt(rep.rows.fold(0.0, (a, b) => a + b.totalSale)),
            discount: _formatInt(rep.rows.fold(0.0, (a, b) => a + b.discount)),
            netSale: _formatInt(rep.rows.fold(0.0, (a, b) => a + b.netSale)),
          ),
        ],
      ),
    );

    return pdf;
  }

  // ----------------------
  // PRINT PREVIEW MODAL
  // ----------------------
  void _showPrintPreview() {
    final report = _todayReport;
    if (report == null) return;
    showPrintPreview(
      context,
      title: "DSR Print Preview",
      buildPdf: () async => (await _buildPdf(report)).save(),
      fileName: "DSR_${_todayStr()}.pdf",
    );
  }

  // ----------------------
  // Core Flows (unchanged logic)
  // ----------------------
  Future<void> _computeTodayAndShow() async {
    setState(() => _busy = true);
    try {
      final rep = await _computeTodayReportFromInvoices();
      _todayReport = rep;
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await db.collection('dsr_reports').doc(_dsrDocId(user.uid)).set(rep.toFirestore());
      }
      setState(() {});
      _toast('Computed & saved DSR for ${_todaySalesDate()}');
    } catch (e) {
      _toast('Compute failed: $e', err: true);
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _loadTodayReport() async {
    setState(() => _busy = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final snap = await db.collection('dsr_reports').doc(_dsrDocId(user.uid)).get();
      if (snap.exists) {
        setState(() => _todayReport = InvoiceDsrReport.fromFirestore(snap.data()!));
        _toast("Loaded saved DSR");
      } else {
        _toast("No DSR saved for ${_todaySalesDate()} yet. Tap Compute.");
      }
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<InvoiceDsrReport> _computeTodayReportFromInvoices() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception("Not logged in");

    // The DSR for a day = invoices whose Sales Date is that day. An invoice dated tomorrow belongs to
    // tomorrow's DSR, even if it was entered today (pick tomorrow with the calendar button to compute it).
    final snap = await db.collection('invoices')
        .where('userId', isEqualTo: user.uid)
        .where('salesDate', isEqualTo: _todaySalesDate()).get();

    final rows = <InvoiceDsrRow>[];
    for (var doc in snap.docs) {
      final data = doc.data();
      final items = (data['items'] as List?) ?? [];
      final pQty = <String, int>{};
      final rQty = <String, int>{};
      final bQty = <String, double>{};
      num n(dynamic v) => num.tryParse(v?.toString() ?? '') ?? 0;

      for (var it in items) {
        if (it is! Map) continue;
        final name = it['Product Name']?.toString() ?? '';
        if (name.isEmpty) continue;
        // += : the same product can be entered on two rows of one invoice
        pQty[name] = (pQty[name] ?? 0) + n(it['QTY']).toInt();
        rQty[name] = (rQty[name] ?? 0) + n(it['returnQty'] ?? it['returnedQty']).toInt();
        bQty[name] = (bQty[name] ?? 0) + n(it['BNS'] ?? it['FOC']).toDouble();
      }

      final ts = (data['total'] ?? 0).toDouble();
      final ns = (data['grandTotal'] ?? ts).toDouble();

      rows.add(InvoiceDsrRow(
        invoiceNumber: data['invoiceNumber']?.toString() ?? '',
        customer: data['customer'] ?? 'Unknown',
        area: data['area'] ?? '',
        productQty: pQty,
        returnQty: rQty,
        bonusQty: bQty,
        totalSale: ts,
        discount: ts - ns,
        netSale: ns,
      ));
    }
    rows.sort((a, b) => (int.tryParse(a.invoiceNumber) ?? 0).compareTo(int.tryParse(b.invoiceNumber) ?? 0));
    return InvoiceDsrReport(dateStr: _todayStr(), generatedAt: Timestamp.now(), rows: rows, userId: user.uid, userEmail: user.email);
  }

  Future<String> _getUsernameFromSessionsByEmail(String? email) async {
    if (email == null || email.isEmpty) return "Unknown";
    final snap = await db.collection("sessions").where("email", isEqualTo: email.trim()).limit(1).get();
    if (snap.docs.isEmpty) return "Unknown";
    return snap.docs.first.data()["username"] ?? "Unknown";
  }

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
  String _dsrDocId(String uid) => '${_todayStr()}__$uid';
  String _formatInt(double v) => v.toInt().toString();
  /// Bonus can be fractional: 2 -> "2", 2.5 -> "2.5".
  String _fmtQty(num v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');
  void _toast(String msg, {bool err = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.sora()),
        backgroundColor: err ? _Tokens.error : _Tokens.navy,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}

// =======================
// MODELS (unchanged)
// =======================

class InvoiceDsrRow {
  final String customer, area;
  final String invoiceNumber; // '' on reports saved before invoice numbers were recorded
  final Map<String, int> productQty, returnQty;
  final Map<String, double> bonusQty; // bonus units per product (free goods, not priced into sales)
  final double totalSale, discount, netSale;

  InvoiceDsrRow({required this.customer, required this.area, this.invoiceNumber = '', required this.productQty, required this.returnQty, this.bonusQty = const {}, required this.totalSale, required this.discount, required this.netSale});

  Map<String, dynamic> toMap() => {'customer': customer, 'area': area, 'invoiceNumber': invoiceNumber, 'productQty': productQty, 'returnQty': returnQty, 'productBns': bonusQty, 'totalSale': totalSale, 'discount': discount, 'netSale': netSale};

  static InvoiceDsrRow fromMap(Map<String, dynamic> m) => InvoiceDsrRow(
      customer: m['customer'], area: m['area'] ?? '',
      invoiceNumber: m['invoiceNumber']?.toString() ?? '',
      productQty: Map<String, int>.from(m['productQty'] ?? {}),
      returnQty: Map<String, int>.from(m['returnQty'] ?? {}),
      bonusQty: {for (final e in Map<String, dynamic>.from(m['productBns'] ?? {}).entries) e.key: (e.value as num).toDouble()},
      totalSale: (m['totalSale'] ?? 0).toDouble(), discount: (m['discount'] ?? 0).toDouble(), netSale: (m['netSale'] ?? 0).toDouble());
}

class InvoiceDsrReport {
  final String dateStr;
  final Timestamp generatedAt;
  final List<InvoiceDsrRow> rows;
  final String userId;
  final String? userEmail;

  InvoiceDsrReport({required this.dateStr, required this.generatedAt, required this.rows, required this.userId, this.userEmail});

  Map<String, dynamic> toFirestore() => {'dateStr': dateStr, 'generatedAt': generatedAt, 'userId': userId, 'userEmail': userEmail, 'rows': rows.map((e) => e.toMap()).toList()};

  static InvoiceDsrReport fromFirestore(Map<String, dynamic> m) => InvoiceDsrReport(
      dateStr: m['dateStr'], generatedAt: m['generatedAt'], userId: m['userId'], userEmail: m['userEmail'],
      rows: (m['rows'] as List).map((e) => InvoiceDsrRow.fromMap(Map<String, dynamic>.from(e))).toList());
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
