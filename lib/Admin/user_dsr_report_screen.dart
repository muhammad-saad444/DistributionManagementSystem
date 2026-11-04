import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../account/account.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import '../dsr_pdf_table.dart';
import '../loadsheet_pdf.dart';

// Same tokens used across the Admin section (admin_dashboard_screen.dart,
// stock_and_sales_screen.dart, user_invoices_screen.dart). Delete this block
// and import your shared _Tokens file if you already have one.
class _Tokens {
  static const navy = Color(0xFF15294D);
  static const navyDark = Color(0xFF0E1D38);
  static const amber = Color(0xFFE0A63A);
  static const bg = Color(0xFFF5F6FA);
  static const border = Color(0xFFE3E7EF);
  static const textDark = Color(0xFF1E2430);
  static const muted = Color(0xFF6B7280);
  static const error = Color(0xFFD64545);
  static const green = Color(0xFF2E8B57);

  static TextStyle display({double size = 18, Color? color, FontWeight w = FontWeight.w700}) =>
      GoogleFonts.sora(fontSize: size, fontWeight: w, color: color ?? textDark);

  static TextStyle body({double size = 13, Color? color, FontWeight w = FontWeight.w400}) =>
      GoogleFonts.sora(fontSize: size, fontWeight: w, color: color ?? textDark);

  static InputDecoration fieldDecoration({String? label, Widget? suffixIcon}) {
    return InputDecoration(
      labelText: label,
      labelStyle: body(color: muted),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: bg,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: border)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: amber, width: 1.5)),
    );
  }
}

class AdminDSRReportsScreen extends StatefulWidget {
  const AdminDSRReportsScreen({super.key});

  @override
  State<AdminDSRReportsScreen> createState() => _AdminDSRReportsScreenState();
}

class _AdminDSRReportsScreenState extends State<AdminDSRReportsScreen> {
  final _firestore = FirebaseFirestore.instance;
  final NumberFormat _money = NumberFormat("#,##0");

  String? selectedUserId;
  DateTime? selectedDate;
  bool showAllDates = true;
  bool isLoadingUsers = true;
  List<Map<String, dynamic>> userList = [];
  bool showLoadsheets = false;
  bool _printingAll = false;

  // --- PAGINATION STATE ---
  static const int _pageSize = 20;
  final ScrollController _scrollController = ScrollController();
  final List<QueryDocumentSnapshot> _docs = [];
  DocumentSnapshot? _lastDoc;
  bool _isLoadingFirst = true;
  bool _isLoadingMore = false;
  bool _isSyncingFirstPage = false; // cached first page is showing, server copy still on its way
  bool _hasMore = true;
  Object? _loadError;
  int _loadGen = 0; // bumps on every filter change so stale responses are ignored

  @override
  void initState() {
    super.initState();
    _fetchUsers();
    _scrollController.addListener(_onScroll);
    _loadFirstPage();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 300) _loadMore();
  }

  // --- PAGINATED FETCH ---
  Future<void> _loadFirstPage() async {
    final gen = ++_loadGen;
    setState(() {
      _docs.clear();
      _lastDoc = null;
      _hasMore = true;
      _isLoadingFirst = true;
      _isLoadingMore = false;
      _isSyncingFirstPage = false;
      _loadError = null;
    });
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
    await _fetchPage(gen);
  }

  Future<void> _loadMore() async {
    if (_isLoadingFirst || _isLoadingMore || _isSyncingFirstPage || !_hasMore || _loadError != null) return;
    setState(() => _isLoadingMore = true);
    await _fetchPage(_loadGen);
  }

  Future<void> _fetchPage(int gen) async {
    final isFirstPage = _lastDoc == null;
    Query q = _buildQuery().limit(_pageSize);
    if (!isFirstPage) q = q.startAfterDocument(_lastDoc!);

    // First page: paint whatever Firestore already has on the device instantly,
    // then replace it with the server result once that arrives.
    var shownFromCache = false;
    if (isFirstPage) {
      try {
        final cached = await q.get(const GetOptions(source: Source.cache));
        if (!mounted || gen != _loadGen) return;
        if (cached.docs.isNotEmpty) {
          shownFromCache = true;
          setState(() {
            _docs
              ..clear()
              ..addAll(cached.docs);
            _lastDoc = cached.docs.last;
            _hasMore = cached.docs.length == _pageSize;
            _isLoadingFirst = false;
            _isSyncingFirstPage = true;
          });
        }
      } catch (_) {
        // Nothing cached (or cache unsupported on this platform) — fall through to the server.
      }
    }

    try {
      final snap = await q.get(const GetOptions(source: Source.server));
      if (!mounted || gen != _loadGen) return;
      setState(() {
        if (isFirstPage) _docs.clear();
        _docs.addAll(snap.docs);
        _lastDoc = snap.docs.isNotEmpty ? snap.docs.last : (isFirstPage ? null : _lastDoc);
        _hasMore = snap.docs.length == _pageSize;
        _isLoadingFirst = false;
        _isLoadingMore = false;
        _isSyncingFirstPage = false;
      });
      // If the first page doesn't fill the screen there's nothing to scroll, so keep loading.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scrollController.hasClients && _scrollController.position.maxScrollExtent <= 0) {
          _loadMore();
        }
      });
    } catch (e) {
      if (!mounted || gen != _loadGen) return;
      setState(() {
        _isLoadingFirst = false;
        _isLoadingMore = false;
        _isSyncingFirstPage = false;
        // Offline but cached rows are already on screen: keep them rather than showing an error.
        if (!shownFromCache) _loadError = e;
      });
      if (shownFromCache) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: _Tokens.error,
            content: Text("Showing saved data — couldn't reach server", style: _Tokens.body(color: Colors.white)),
          ),
        );
      }
    }
  }

  /// Bonus can be fractional: whole numbers without ".0", fractions to at most 2 decimals.
  String _fmtQty(dynamic value) {
    final d = double.tryParse((value ?? 0).toString()) ?? 0.0;
    if (d == d.roundToDouble()) return d.toInt().toString();
    return d.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');
  }

  String _toRoundedIntStr(dynamic value) {
    if (value == null) return "0";
    double parsed = double.tryParse(value.toString()) ?? 0.0;
    return parsed.round().toString();
  }

  // --- FETCH USERS ---
  Future<void> _fetchUsers() async {
    final isBooker = await bookerFilter();
    final snapshot = await _firestore.collection("sessions").get();
    final users = snapshot.docs
        .where((doc) => isBooker((doc.data()["uid"] ?? "").toString(), (doc.data()["email"] ?? "").toString()))
        .map((doc) => {
      "uid": doc["uid"],
      "username": doc["username"],
      "email": doc["email"],
    })
        .toList();

    setState(() {
      userList = users;
      isLoadingUsers = false;
    });
  }

  // --- HELPERS FOR PDF ---
  Future<String> _getUsernameFromSessionsByEmail(String? email) async {
    if (email == null || email.trim().isEmpty) return "Unknown Booker";
    final snap = await _firestore
        .collection("sessions")
        .where("email", isEqualTo: email.trim())
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return "Unknown Booker";
    return (snap.docs.first.data()["username"] ?? "Unknown Booker").toString();
  }

  // --- UNIFIED AREA EXTRACTOR FIXED FOR LOADSHEETS & DSR ---
  String _extractAreas(Map<String, dynamic> data) {
    final List<String> extractedAreas = [];

    if (data["areas"] != null) {
      if (data["areas"] is List) {
        for (var item in data["areas"]) {
          if (item != null && item.toString().trim().isNotEmpty) {
            extractedAreas.add(item.toString().trim());
          }
        }
      } else if (data["areas"].toString().trim().isNotEmpty) {
        extractedAreas.add(data["areas"].toString().trim());
      }
    }

    if (data["selectedAreas"] != null) {
      if (data["selectedAreas"] is List) {
        for (var item in data["selectedAreas"]) {
          if (item != null && item.toString().trim().isNotEmpty) {
            extractedAreas.add(item.toString().trim());
          }
        }
      } else if (data["selectedAreas"].toString().trim().isNotEmpty) {
        extractedAreas.add(data["selectedAreas"].toString().trim());
      }
    }

    if (data["area"] != null && data["area"].toString().trim().isNotEmpty) {
      extractedAreas.add(data["area"].toString().trim());
    }

    if (data.containsKey("rows")) {
      final rows = List<Map<String, dynamic>>.from(data["rows"] ?? []);
      for (var r in rows) {
        final area = (r["area"] ?? "").toString().trim();
        if (area.isNotEmpty) extractedAreas.add(area);
      }
    }

    if (data.containsKey("items")) {
      final items = List<Map<String, dynamic>>.from(data["items"] ?? []);
      for (var i in items) {
        final area = (i["area"] ?? "").toString().trim();
        if (area.isNotEmpty) extractedAreas.add(area);
      }
    }

    final finalSet = extractedAreas.toSet().join(", ");
    return finalSet.isEmpty ? "-" : finalSet;
  }

  // --- PDF LOADSHEET: same shared layout as the booker app's print ---
  List<pw.Widget> _pdfLoadsheet(Map<String, dynamic> data, String username, String areas) {
    final items = List<Map<String, dynamic>>.from(data["items"] ?? []);
    final totals = Map<String, dynamic>.from(data["totals"] ?? {});
    num n(dynamic v) => num.tryParse(v?.toString() ?? '') ?? 0;
    final rows = items.map((i) => LoadSheetPdfRow(
          product: (i["productName"] ?? i["Product Name"] ?? "").toString(),
          qty: n(i["qty"]),
          bonus: n(i["bns"]),
          amount: n(i["amount"]).toDouble(),
        )).toList();
    return loadSheetPdfContent(
      company: "A.N Agency",
      dateStr: (data["dateStr"] ?? "").toString(),
      booker: "$username (${data["userEmail"] ?? "-"})",
      areas: areas,
      rows: rows,
      // Net total saved with the sheet (after invoice discounts); older sheets without it fall back to the gross.
      netAmount: totals["sumAmount"] != null ? n(totals["sumAmount"]).toDouble() : rows.fold<double>(0, (s, r) => s + r.amount),
    );
  }

  // --- PDF DSR WIDGET (FIXED ROUNDING DISCREPANCY) ---
  List<pw.Widget> _pdfDSR(Map<String, dynamic> data, String username, String areas) {
    final rows = List<Map<String, dynamic>>.from(data["rows"] ?? [])
      ..sort((a, b) => (int.tryParse(a["invoiceNumber"]?.toString() ?? "") ?? 0)
          .compareTo(int.tryParse(b["invoiceNumber"]?.toString() ?? "") ?? 0));

    final allProducts = <String>{};
    for (var r in rows) {
      final productQty = Map<String, dynamic>.from(r["productQty"] ?? {});
      allProducts.addAll(productQty.keys);
    }
    final productList = allProducts.toList()..sort();

    double totalSaleSum = 0;
    double netSaleSum = 0;
    final productTotals = <String, int>{};

    for (var r in rows) {
      totalSaleSum += (double.tryParse(r["totalSale"].toString()) ?? 0);
      netSaleSum += (double.tryParse(r["netSale"].toString()) ?? 0);

      final pQty = Map<String, dynamic>.from(r["productQty"] ?? {});

      for (var p in productList) {
        final int qty = (pQty[p] ?? 0).toInt();
        productTotals[p] = (productTotals[p] ?? 0) + qty;
      }
    }
    double discountSum = totalSaleSum - netSaleSum;

    int roundedTotalSale = totalSaleSum.round();
    int roundedNetSale = netSaleSum.round();
    int roundedDiscount = discountSum.round();

    return [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text("A.N Agency", style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
            pw.Text("Daily Sales Report", style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
            pw.Text(data["dateStr"] ?? ""),
          ],
        ),
        pw.SizedBox(height: 5),
        pw.Text(
          "Booker: $username (${data["userEmail"] ?? "-"})  |  Area: $areas",
          style: pw.TextStyle(fontSize: 11, color: PdfColors.black, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 15),

        ...dsrPdfTables(
          availableWidth: dsrPageFormat.availableWidth,
          products: productList,
          rows: rows.map((r) {
            final pQty = Map<String, dynamic>.from(r["productQty"] ?? {});
            final inv = (r["invoiceNumber"] ?? "").toString();
            return DsrPdfRow(
              invoice: inv.isEmpty ? "-" : inv,
              customer: (r["customer"] ?? "").toString(),
              qty: {for (final p in productList) p: _fmtQty(pQty[p] ?? 0)},
              totalSale: _toRoundedIntStr(r["totalSale"]),
              discount: _toRoundedIntStr(r["discount"]),
              netSale: _toRoundedIntStr(r["netSale"]),
            );
          }).toList(),
          productTotals: {for (final p in productList) p: "${productTotals[p] ?? 0}"},
          productBonus: {
            for (final p in productList)
              p: _fmtQty(rows.fold<double>(0, (sum, r) =>
                  sum + (num.tryParse((Map<String, dynamic>.from(r["productBns"] ?? {})[p] ?? 0).toString()) ?? 0))),
          },
          totalSale: "$roundedTotalSale",
          discount: "$roundedDiscount",
          netSale: "$roundedNetSale",
        ),
      ];
  }

  // Every admin print, preview and print-all goes through here: multi-page so long reports flow onto
  // extra pages, and the DSR in landscape so a wide product list stays readable.
  void _addReportPages(pw.Document pdf, Map<String, dynamic> data, String username, String areas) {
    pdf.addPage(pw.MultiPage(
      pageFormat: showLoadsheets ? loadSheetPageFormat : dsrPageFormat,
      build: (_) => showLoadsheets ? _pdfLoadsheet(data, username, areas) : _pdfDSR(data, username, areas),
    ));
  }

  // --- PRINT LOGIC ---
  Future<void> _printAllReports(List<QueryDocumentSnapshot> docs) async {
    if (docs.isEmpty) return;
    setState(() => _printingAll = true);
    final pdf = pw.Document();
    try {
      for (var d in docs) {
        final data = d.data() as Map<String, dynamic>;
        final username = await _getUsernameFromSessionsByEmail(data['userEmail']);
        final areas = _extractAreas(data);
        _addReportPages(pdf, data, username, areas);
      }
      await Printing.layoutPdf(onLayout: (_) => pdf.save());
    } finally {
      if (mounted) setState(() => _printingAll = false);
    }
  }

  Future<void> _printSingle(Map<String, dynamic> data) async {
    final pdf = pw.Document();
    final username = await _getUsernameFromSessionsByEmail(data['userEmail']);
    final areas = _extractAreas(data);
    _addReportPages(pdf, data, username, areas);
    await Printing.layoutPdf(onLayout: (_) => pdf.save());
  }

  // --- QUERY BUILDER ---
  Query _buildQuery() {
    String coll = showLoadsheets ? "load_sheets" : "dsr_reports";
    Query q = _firestore.collection(coll);
    if (selectedUserId != null) q = q.where("userId", isEqualTo: selectedUserId);
    if (!showAllDates && selectedDate != null) {
      q = q.where("dateStr", isEqualTo: DateFormat("yyyy-MM-dd").format(selectedDate!));
    }
    return q.orderBy("generatedAt", descending: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _Tokens.bg,
      appBar: AppBar(
        title: Text(
          showLoadsheets ? "Loadsheet Reports" : "DSR Reports",
          style: _Tokens.display(size: 17, color: Colors.white),
        ),
        backgroundColor: _Tokens.navy,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.print_outlined),
            onPressed: _printingAll ? null : () async {
              // Print still covers every report matching the filters, not just loaded pages.
              final snap = await _buildQuery().get();
              await _printAllReports(snap.docs);
            },
          ),
          IconButton(
            icon: Icon(Icons.swap_horiz, color: _Tokens.amber),
            tooltip: 'Switch report type',
            onPressed: () {
              showLoadsheets = !showLoadsheets;
              _loadFirstPage();
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                child: isLoadingUsers
                    ? Center(child: CircularProgressIndicator(color: _Tokens.navy))
                    : DropdownButtonFormField<String>(
                  isExpanded: true,
                  style: _Tokens.body(color: _Tokens.textDark),
                  icon: Icon(Icons.keyboard_arrow_down, color: _Tokens.muted),
                  decoration: _Tokens.fieldDecoration(label: "Select User"),
                  value: selectedUserId,
                  items: [
                    DropdownMenuItem(value: null, child: Text("All Users", style: _Tokens.body())),
                    ...userList.map((u) => DropdownMenuItem(
                      value: u["uid"],
                      child: Text(u["username"], overflow: TextOverflow.ellipsis, style: _Tokens.body()),
                    )),
                  ],
                  onChanged: (v) {
                    selectedUserId = v;
                    _loadFirstPage();
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: _Tokens.border),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2)),
                    ],
                  ),
                  child: Row(children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: Icon(Icons.date_range, color: _Tokens.navy, size: 18),
                        label: Text(
                          selectedDate == null ? "Select Date" : DateFormat("dd-MM-yyyy").format(selectedDate!),
                          style: _Tokens.body(color: _Tokens.navy, w: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: _Tokens.border),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () async {
                          final picked = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(2024), lastDate: DateTime(2030));
                          if (picked != null) {
                            selectedDate = picked;
                            showAllDates = false;
                            _loadFirstPage();
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Switch(
                      value: showAllDates,
                      activeColor: _Tokens.amber,
                      onChanged: (v) {
                        showAllDates = v;
                        _loadFirstPage();
                      },
                    ),
                    Text("All", style: _Tokens.body(size: 12, color: _Tokens.muted)),
                  ]),
                ),
              ),
              Expanded(child: _buildReportList()),
            ],
          ),
          if (_printingAll)
            Container(
              color: _Tokens.navyDark.withOpacity(0.6),
              child: Center(child: CircularProgressIndicator(color: _Tokens.amber)),
            ),
        ],
      ),
    );
  }

  // --- PAGINATED REPORT LIST ---
  Widget _buildReportList() {
    if (_isLoadingFirst) return Center(child: CircularProgressIndicator(color: _Tokens.navy));

    if (_docs.isEmpty) {
      return RefreshIndicator(
        color: _Tokens.navy,
        onRefresh: _loadFirstPage,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 120),
            Center(
              child: _loadError != null
                  ? _retryButton("Failed to load reports", _loadFirstPage)
                  : Text("No reports found", style: _Tokens.body(color: _Tokens.muted)),
            ),
          ],
        ),
      );
    }

    final showFooter = _hasMore || _loadError != null;
    return RefreshIndicator(
      color: _Tokens.navy,
      onRefresh: _loadFirstPage,
      child: ListView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        itemCount: _docs.length + (showFooter ? 1 : 0),
        itemBuilder: (context, i) {
          if (i == _docs.length) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: _loadError != null
                    ? _retryButton("Couldn't load more", () {
                        setState(() => _loadError = null);
                        _loadMore();
                      })
                    : SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: _Tokens.navy),
                      ),
              ),
            );
          }
          return _buildReportTile(_docs[i].data() as Map<String, dynamic>);
        },
      ),
    );
  }

  Widget _retryButton(String message, VoidCallback onRetry) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(message, style: _Tokens.body(color: _Tokens.error)),
        TextButton(
          onPressed: onRetry,
          child: Text("Retry", style: _Tokens.body(color: _Tokens.navy, w: FontWeight.w600)),
        ),
      ],
    );
  }

  Widget _buildReportTile(Map<String, dynamic> data) {
    double exactSum = 0;

    if (showLoadsheets) {
      // ⭐ FIX: Read the exact pre-computed Net total map structure from database so list views match 3134
      final totals = Map<String, dynamic>.from(data["totals"] ?? {});
      exactSum = double.tryParse(totals["sumAmount"]?.toString() ?? "0.0") ?? 0.0;
    } else {
      final rows = List<Map<String, dynamic>>.from(data["rows"] ?? []);
      exactSum = rows.fold(0.0, (sum, row) => sum + (double.tryParse(row["netSale"].toString()) ?? 0.0));
    }
    int totalVal = exactSum.round();
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _Tokens.border),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2)),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        title: Text("Date: ${data["dateStr"] ?? "-"}", style: _Tokens.display(size: 15)),
        subtitle: Text("User: ${data["userEmail"] ?? "-"}", style: _Tokens.body(color: _Tokens.muted, size: 12)),
        trailing: Text(
          "Rs. ${_money.format(totalVal)}",
          style: _Tokens.body(color: _Tokens.green, w: FontWeight.w700, size: 14),
        ),
        onTap: () => _showDetails(data),
      ),
    );
  }

  // --- MODAL PREVIEW SCREEN IMPLEMENTATION ---
  void _showDetails(Map<String, dynamic> data) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Center(child: CircularProgressIndicator(color: _Tokens.amber)),
    );

    final username = await _getUsernameFromSessionsByEmail(data['userEmail']);
    final areas = _extractAreas(data);

    if (mounted) Navigator.pop(context);

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Container(
                width: 40,
                height: 5,
                margin: const EdgeInsets.only(bottom:10),
                decoration: BoxDecoration(color: _Tokens.border, borderRadius: BorderRadius.circular(10)),
              ),
              Text(showLoadsheets ? "Loadsheet Preview" : "DSR Preview", style: _Tokens.display(size: 17)),
              const SizedBox(height: 4),
              Text("User: $username (${data['userEmail']})", style: _Tokens.body(color: _Tokens.muted, size: 12.5)),
              Divider(height: 20, color: _Tokens.border),

              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: PdfPreview(
                    build: (format) async {
                      final pdf = pw.Document();
                      _addReportPages(pdf, data, username, areas);
                      return pdf.save();
                    },
                    allowPrinting: false,
                    allowSharing: false,
                    canChangePageFormat: false,
                    canChangeOrientation: false,
                    loadingWidget: Center(child: CircularProgressIndicator(color: _Tokens.navy)),
                  ),
                ),
              ),

              Divider(height: 25, color: _Tokens.border),

              SafeArea(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: _Tokens.amber,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))
                        ),
                        icon: const Icon(Icons.print_outlined, color: _Tokens.navyDark),
                        label: Text("Print Document", style: _Tokens.body(color: _Tokens.navyDark, w: FontWeight.w700)),
                        onPressed: () => _printSingle(data)
                    ),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                          side: BorderSide(color: _Tokens.border),
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))
                      ),
                      onPressed: () => Navigator.pop(context),
                      child: Text("Close", style: _Tokens.body(color: _Tokens.muted, w: FontWeight.w600)),
                    ),
                  ],
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}