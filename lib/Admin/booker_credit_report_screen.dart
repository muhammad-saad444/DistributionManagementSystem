import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../account/account.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

// ---------------------------------------------------------------------------
// Same design tokens used across the rest of the app. Worth pulling into a
// shared lib/design_tokens.dart at some point instead of duplicating this
// class per file.
// ---------------------------------------------------------------------------
class _Tokens {
  static const navyDark = Color(0xFF131C31);
  static const navySlate = Color(0xFF24345C);
  static const amber = Color(0xFFE8973A);
  static const bg = Color(0xFFF5F6F8);
  static const textPrimary = Color(0xFF101828);
  static const textSecondary = Color(0xFF667085);
  static const border = Color(0xFFE4E7EC);
  static const error = Color(0xFFD92D20);
  static const green = Color(0xFF12B76A);
  static const navySlateBg = Color(0xFFE7EAF2);
  static const amberBg = Color(0xFFFCEEDA);

  static TextStyle display({double size = 18, Color? color, FontWeight w = FontWeight.w600}) =>
      GoogleFonts.sora(fontSize: size, fontWeight: w, color: color ?? textPrimary, height: 1.2);

  static TextStyle body({double size = 13, Color? color, FontWeight w = FontWeight.w400}) =>
      GoogleFonts.inter(fontSize: size, fontWeight: w, color: color ?? textPrimary);

  static InputDecoration fieldDecoration({String? label, Widget? suffixIcon}) {
    return InputDecoration(
      labelText: label,
      labelStyle: body(color: textSecondary),
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

class AdminBookerCreditReportScreen extends StatefulWidget {
  const AdminBookerCreditReportScreen({Key? key}) : super(key: key);

  @override
  State<AdminBookerCreditReportScreen> createState() => _AdminBookerCreditReportScreenState();
}

class _AdminBookerCreditReportScreenState extends State<AdminBookerCreditReportScreen> with SingleTickerProviderStateMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final NumberFormat _moneyFormat = NumberFormat("#,##0.00");

  late TabController _tabController;
  DateTime _selectedDate = DateTime.now();

  // Tab 1 Data States
  List<Map<String, dynamic>> _bookerReportList = [];
  bool _isLoadingSummary = true;

  // Tab 2 Data States
  List<Map<String, dynamic>> _userList = [];
  String? _selectedDetailedUserId;
  DateTime _selectedLedgerDate = DateTime.now();
  List<Map<String, dynamic>> _customerLedgerList = [];
  bool _isLoadingLedger = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _initData();
  }

  // Fetch the booker list once, then compute the first day's credit summary
  // from it — avoids reading the 'sessions' collection twice on startup.
  Future<void> _initData() async {
    await _fetchBookersList();
    await _generateCreditData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // --- FETCH BOOKERS LIST ---
  Future<void> _fetchBookersList() async {
    try {
      final isBooker = await bookerFilter();
      final usersSnapshot = await companyCol('sessions').get();
      setState(() {
        _userList = usersSnapshot.docs
            .where((doc) => isBooker((doc.data()['uid'] ?? '').toString(), (doc.data()['email'] ?? '').toString()))
            .map((doc) => {
          'uid': doc.data()['uid']?.toString() ?? '',
          'username': doc.data()['username']?.toString() ?? '',
          'email': doc.data()['email']?.toString() ?? '',
        })
            .toList();
      });
    } catch (e) {
      debugPrint("Error fetching bookers: $e");
    }
  }

  // ===========================================================================
  // TAB 1: DAILY SUMMARY COMPUTE
  // ===========================================================================
  Future<void> _generateCreditData() async {
    setState(() => _isLoadingSummary = true);
    try {
      final String formattedTargetDate = DateFormat("yyyy-MM-dd").format(_selectedDate);

      // Reuse the booker list already fetched by _fetchBookersList instead of
      // re-querying 'sessions' on every date change — the list of bookers
      // doesn't depend on the selected date.
      if (_userList.isEmpty) {
        await _fetchBookersList();
      }
      final bookers = _userList;

      // These two queries don't depend on each other — run them concurrently
      // instead of one after another to cut the wait roughly in half.
      final results = await Future.wait([
        companyCol('dsr_reports')
            .where('dateStr', isEqualTo: formattedTargetDate)
            .get(),
        companyCol('booker_credits')
            .where('dateStr', isEqualTo: formattedTargetDate)
            .get(),
      ]);
      final dsrSnapshot = results[0];
      final creditSnapshot = results[1];

      Map<String, double> paymentMap = {};
      for (var doc in creditSnapshot.docs) {
        final data = doc.data();
        paymentMap[data['userId']] = (num.tryParse(data['amountReceived']?.toString() ?? "0") ?? 0).toDouble();
      }

      List<Map<String, dynamic>> computedList = [];

      for (var booker in bookers) {
        final String uid = booker['uid']!;
        double totalSalesAmount = 0.0;

        final matchDsr = dsrSnapshot.docs.where((d) => d.data()['userId'] == uid);
        if (matchDsr.isNotEmpty) {
          final dsrData = matchDsr.first.data();
          final rows = List.from(dsrData['rows'] ?? []);
          for (var row in rows) {
            totalSalesAmount += (num.tryParse(row['netSale']?.toString() ?? "0") ?? 0).toDouble();
          }
        }

        double amountReceived = paymentMap[uid] ?? 0.0;
        double balanceRemaining = totalSalesAmount - amountReceived;

        computedList.add({
          'userId': uid,
          'username': booker['username'],
          'email': booker['email'],
          'totalSale': totalSalesAmount,
          'amountReceived': amountReceived,
          'balance': balanceRemaining,
        });
      }

      setState(() {
        _bookerReportList = computedList;
        _isLoadingSummary = false;
      });
    } catch (e) {
      debugPrint("Error generating credit metrics: $e");
      setState(() => _isLoadingSummary = false);
    }
  }

  // ===========================================================================
  // TAB 2: DATE-SPECIFIC CUSTOMER-WISE LEDGER STATEMENT BUILDER
  // ===========================================================================
  Future<void> _generateCustomerLedgerData(String userId) async {
    setState(() => _isLoadingLedger = true);
    try {
      final String targetedInvoiceDate = DateFormat("dd-MM-yyyy").format(_selectedLedgerDate);
      final String targetedRecoveryDate = DateFormat("yyyy-MM-dd").format(_selectedLedgerDate);

      // Independent queries — run concurrently instead of sequentially.
      final results = await Future.wait([
        companyCol('invoices')
            .where('userId', isEqualTo: userId)
            .where('salesDate', isEqualTo: targetedInvoiceDate)
            .get(),
        companyCol('customer_recoveries')
            .where('userId', isEqualTo: userId)
            .where('dateStr', isEqualTo: targetedRecoveryDate)
            .get(),
        // Payments in the booker's khata (entered by the booker, or here by the office).
        companyCol('khata_entries').where('userId', isEqualTo: userId).get(),
      ]);
      final invoicesSnap = results[0];
      final recoverySnap = results[1];

      Map<String, double> recoveryMap = {};
      for (var doc in recoverySnap.docs) {
        final d = doc.data();
        String key = d['customerName'].toString().trim().toLowerCase();
        recoveryMap[key] = (recoveryMap[key] ?? 0.0) + (num.tryParse(d['amountPaid']?.toString() ?? "0") ?? 0).toDouble();
      }
      final day = DateTime(_selectedLedgerDate.year, _selectedLedgerDate.month, _selectedLedgerDate.day);
      for (var doc in results[2].docs) {
        final d = doc.data();
        if (d['type'] != 'payment') continue;
        final ts = d['date'];
        if (ts is! Timestamp) continue;
        final t = ts.toDate();
        if (DateTime(t.year, t.month, t.day) != day) continue;
        final key = (d['customer'] ?? '').toString().trim().toLowerCase();
        recoveryMap[key] = (recoveryMap[key] ?? 0.0) + (num.tryParse(d['amount']?.toString() ?? "0") ?? 0).toDouble();
      }

      Map<String, Map<String, dynamic>> customerAggregation = {};

      for (var doc in invoicesSnap.docs) {
        final data = doc.data();
        String clientName = (data['customer'] ?? 'Unknown Store').toString().trim();
        String lookupKey = clientName.toLowerCase();

        double netSale = (num.tryParse(data['grandTotal']?.toString() ?? "0") ?? 0).toDouble();

        if (!customerAggregation.containsKey(lookupKey)) {
          customerAggregation[lookupKey] = {
            'customerName': clientName,
            'area': data['area'] ?? '-',
            'totalSales': 0.0,
            'recovered': recoveryMap[lookupKey] ?? 0.0,
            'balance': 0.0
          };
        }
        customerAggregation[lookupKey]!['totalSales'] += netSale;
      }

      for (var key in customerAggregation.keys) {
        double sales = customerAggregation[key]!['totalSales'];
        double collected = customerAggregation[key]!['recovered'];
        customerAggregation[key]!['balance'] = sales - collected;
      }

      setState(() {
        _customerLedgerList = customerAggregation.values.toList();
        _isLoadingLedger = false;
      });
    } catch (e) {
      debugPrint("Error loading customer ledger matrices: $e");
      setState(() => _isLoadingLedger = false);
    }
  }

  // --- RECORD CUSTOMER RECOVERY ---
  void _showCustomerPaymentDialog(Map<String, dynamic> ledgerRow) {
    final TextEditingController recoveryCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text("Receive Recovery — ${ledgerRow['customerName']}", style: _Tokens.display(size: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Total Sales Amount: Rs. ${_moneyFormat.format(ledgerRow['totalSales'])}", style: _Tokens.body(color: _Tokens.textPrimary)),
            const SizedBox(height: 4),
            Text("Previously Recovered: Rs. ${_moneyFormat.format(ledgerRow['recovered'])}", style: _Tokens.body(color: _Tokens.green, w: FontWeight.w600)),
            const SizedBox(height: 4),
            Text("Current Outstanding: Rs. ${_moneyFormat.format(ledgerRow['balance'])}", style: _Tokens.body(color: _Tokens.error, w: FontWeight.w700)),
            const SizedBox(height: 16),
            TextField(
              controller: recoveryCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: _Tokens.body(),
              decoration: _Tokens.fieldDecoration(label: "Amount Paid Now").copyWith(prefixText: "Rs. "),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("Cancel", style: _Tokens.body(color: _Tokens.textSecondary, w: FontWeight.w600)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _Tokens.amber,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () async {
              double paymentAmount = double.tryParse(recoveryCtrl.text.trim()) ?? 0.0;
              if (paymentAmount <= 0) return;

              // Saved as a payment in the booker's khata, so the shop's balance and its invoices'
              // Closed / Open status count it too.
              final booker = _userList.firstWhere((u) => u['uid'] == _selectedDetailedUserId, orElse: () => const {});
              final d = _selectedLedgerDate;
              await companyCol('khata_entries').add({
                'userId': _selectedDetailedUserId,
                'userEmail': booker['email'] ?? '',
                'customer': ledgerRow['customerName'].toString().trim(),
                'type': 'payment',
                'amount': paymentAmount,
                'method': 'Office recovery',
                'note': 'Recorded on the Booker Credit Report',
                'date': Timestamp.fromDate(DateTime(d.year, d.month, d.day)),
                'createdAt': FieldValue.serverTimestamp(),
              });

              if (mounted) Navigator.pop(context);
              if (_selectedDetailedUserId != null) {
                _generateCustomerLedgerData(_selectedDetailedUserId!);
              }
            },
            child: Text("Confirm Recovery", style: _Tokens.body(w: FontWeight.w600, color: _Tokens.navyDark)),
          ),
        ],
      ),
    );
  }

  // --- POPUP DIALOG FOR LEDGER DOCUMENT PREVIEW ---
  void _showDetailedLedgerPreview() {
    if (_selectedDetailedUserId == null) return;

    final selectedUserMap = _userList.firstWhere((u) => u['uid'] == _selectedDetailedUserId);
    final String bookerName = selectedUserMap['username'] ?? 'Booker';

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
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(color: _Tokens.border, borderRadius: BorderRadius.circular(10)),
              ),
              Text("Customer Ledger Preview — $bookerName", style: _Tokens.display(size: 17)),
              Divider(height: 20, color: _Tokens.border),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: PdfPreview(
                    build: (format) async => _generateLedgerPdfDocument(bookerName),
                    allowPrinting: false,
                    allowSharing: false,
                    canChangePageFormat: false,
                    canChangeOrientation: false,
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
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: const Icon(Icons.print_outlined, color: _Tokens.navyDark),
                      label: Text("Print Ledger Document", style: _Tokens.body(color: _Tokens.navyDark, w: FontWeight.w700)),
                      onPressed: () async {
                        final pdfData = await _generateLedgerPdfDocument(bookerName);
                        await Printing.layoutPdf(onLayout: (_) => pdfData);
                      },
                    ),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: _Tokens.border),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () => Navigator.pop(context),
                      child: Text("Close", style: _Tokens.body(color: _Tokens.textSecondary, w: FontWeight.w600)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- GENERATE PDF DOCUMENT FOR THE SELECTED DATE ONLY ---
  Future<Uint8List> _generateLedgerPdfDocument(String bookerName) async {
    final pdf = pw.Document();
    final String formattedDateLabel = DateFormat("dd-MM-yyyy").format(_selectedLedgerDate);

    double grandTotalSales = 0.0;
    double grandTotalRecovered = 0.0;
    double grandTotalBalance = 0.0;

    for (var l in _customerLedgerList) {
      grandTotalSales += l['totalSales'];
      grandTotalRecovered += l['recovered'];
      grandTotalBalance += l['balance'];
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) => [
          pw.Center(
            child: pw.Column(children: [
              pw.Text(Account.companyName, style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 4),
              pw.Text("Booker Customer-wise Ledger Statement", style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
              pw.Text("Booker Profile: $bookerName | Statement Date: $formattedDateLabel"),
              pw.SizedBox(height: 15),
            ]),
          ),
          pw.Table.fromTextArray(
            headers: const ["Customer Name", "Area", "Total Sales", "Recovered Amount", "Remaining Balance"],
            data: _customerLedgerList.map((l) => [
              l['customerName'] ?? '',
              l['area'] ?? '',
              _moneyFormat.format(l['totalSales']),
              _moneyFormat.format(l['recovered']),
              _moneyFormat.format(l['balance']),
            ]).toList(),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.purpleAccent),
            cellPadding: const pw.EdgeInsets.all(6),
            cellStyle: const pw.TextStyle(fontSize: 9),
          ),
          pw.SizedBox(height: 20),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Container(
              width: 260,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text("Total Sales: Rs. ${_moneyFormat.format(grandTotalSales)}"),
                  pw.Text("Total Recovery: Rs. ${_moneyFormat.format(grandTotalRecovered)}"),
                  pw.Divider(),
                  pw.Text("Total Balance Due: Rs. ${_moneyFormat.format(grandTotalBalance)}",
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.red800)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    return pdf.save();
  }

  // --- RECORD TAB 1 PAYMENTS ---
  void _showPaymentEntryDialog(Map<String, dynamic> bookerData) {
    final TextEditingController amountController = TextEditingController(
      text: bookerData['amountReceived'] > 0 ? bookerData['amountReceived'].toStringAsFixed(0) : "",
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text("Receive Payment — ${bookerData['username']}", style: _Tokens.display(size: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Total Credit Sale: Rs. ${_moneyFormat.format(bookerData['totalSale'])}", style: _Tokens.body(w: FontWeight.w700)),
            const SizedBox(height: 16),
            TextField(
              controller: amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: _Tokens.body(),
              decoration: _Tokens.fieldDecoration(label: "Enter Amount Received").copyWith(prefixText: "Rs. "),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("Cancel", style: _Tokens.body(color: _Tokens.textSecondary, w: FontWeight.w600)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _Tokens.amber,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () async {
              double enteredAmount = double.tryParse(amountController.text.trim()) ?? 0.0;
              final String dateId = DateFormat("yyyy-MM-dd").format(_selectedDate);
              final String docId = "${dateId}__${bookerData['userId']}";

              await companyCol('booker_credits').doc(docId).set({
                'dateStr': dateId,
                'userId': bookerData['userId'],
                'username': bookerData['username'],
                'userEmail': bookerData['email'],
                'amountReceived': enteredAmount,
                'updatedAt': FieldValue.serverTimestamp(),
              }, SetOptions(merge: true));

              if (mounted) Navigator.pop(context);
              _generateCreditData();
            },
            child: Text("Save Payment", style: _Tokens.body(w: FontWeight.w600, color: _Tokens.navyDark)),
          ),
        ],
      ),
    );
  }

  // --- PRINT TAB 1 DAILY REPORT ---
  Future<void> _printCreditReport() async {
    final pdf = pw.Document();
    final String dateString = DateFormat("dd-MM-yyyy").format(_selectedDate);

    double totalSummarySales = 0;
    double totalSummaryReceived = 0;
    double totalSummaryBalance = 0;

    for (var b in _bookerReportList) {
      totalSummarySales += b['totalSale'];
      totalSummaryReceived += b['amountReceived'];
      totalSummaryBalance += b['balance'];
    }

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Center(
              child: pw.Column(children: [
                pw.Text(Account.companyName, style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 4),
                pw.Text("Booker Credit Summary Report", style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                pw.Text("Date: $dateString"),
                pw.SizedBox(height: 15),
              ]),
            ),
            pw.Table.fromTextArray(
              headers: const ["Booker Name", "Email", "Total Sale", "Amount Received", "Remaining Balance"],
              data: _bookerReportList.map((b) => [
                b['username'] ?? '',
                b['email'] ?? '',
                _moneyFormat.format(b['totalSale']),
                _moneyFormat.format(b['amountReceived']),
                _moneyFormat.format(b['balance']),
              ]).toList(),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.blueAccent),
              cellPadding: const pw.EdgeInsets.all(6),
              cellStyle: const pw.TextStyle(fontSize: 10),
            ),
            pw.SizedBox(height: 20),
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Container(
                width: 250,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text("Gross Market Sale: Rs. ${_moneyFormat.format(totalSummarySales)}"),
                    pw.Text("Total Recovered Cash: Rs. ${_moneyFormat.format(totalSummaryReceived)}"),
                    pw.Divider(),
                    pw.Text("Net Outstanding Balance: Rs. ${_moneyFormat.format(totalSummaryBalance)}",
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.red800)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );

    await Printing.layoutPdf(onLayout: (format) => pdf.save());
  }

  // ==================== Small styling helpers ====================
  Widget _card({required Widget child, EdgeInsetsGeometry? padding}) {
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _Tokens.border),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: child,
    );
  }

  Widget _balanceTile({
    required String title,
    required String subtitle,
    required double balance,
    required VoidCallback onTap,
  }) {
    final isOwed = balance > 0;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: _card(
        padding: EdgeInsets.zero,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          title: Text(title, style: _Tokens.display(size: 15)),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(subtitle, style: _Tokens.body(color: _Tokens.textSecondary)),
          ),
          isThreeLine: subtitle.contains('\n'),
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: isOwed ? _Tokens.error.withOpacity(0.08) : _Tokens.green.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              "Rs. ${_moneyFormat.format(balance)}",
              style: _Tokens.body(w: FontWeight.w700, color: isOwed ? _Tokens.error : _Tokens.green, size: 13),
            ),
          ),
          onTap: onTap,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _Tokens.bg,
      appBar: AppBar(
        title: Text(
          "Booker Credit Summary & Ledgers",
          style: _Tokens.display(size: 16, color: Colors.white),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        backgroundColor: _Tokens.navyDark,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          indicatorColor: _Tokens.amber,
          indicatorWeight: 3,
          labelStyle: _Tokens.body(w: FontWeight.w600, size: 12.5),
          tabs: const [
            Tab(icon: Icon(Icons.summarize_outlined), text: "Daily Credit Summary"),
            Tab(icon: Icon(Icons.menu_book_outlined), text: "Detailed Customer Ledger"),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // VIEW 1: DAILY CREDIT BALANCES SUMMARY
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: _card(
                  padding: EdgeInsets.zero,
                  child: ListTile(
                    leading: Icon(Icons.calendar_month_outlined, color: _Tokens.navySlate),
                    title: Text(
                      "Target Sheet Date: ${DateFormat("dd-MM-yyyy").format(_selectedDate)}",
                      style: _Tokens.body(color: _Tokens.textPrimary, w: FontWeight.w500),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(Icons.print_outlined, color: _Tokens.navySlate),
                          onPressed: _bookerReportList.isEmpty ? null : _printCreditReport,
                        ),
                        Icon(Icons.arrow_drop_down, color: _Tokens.textSecondary),
                      ],
                    ),
                    onTap: () async {
                      final picked = await showDatePicker(context: context, initialDate: _selectedDate, firstDate: DateTime(2024), lastDate: DateTime(2030));
                      if (picked != null) {
                        setState(() => _selectedDate = picked);
                        _generateCreditData();
                      }
                    },
                  ),
                ),
              ),
              Expanded(
                child: _isLoadingSummary
                    ? Center(child: CircularProgressIndicator(color: _Tokens.amber))
                    : (_bookerReportList.isEmpty
                    ? Center(child: Text("No data found for this date", style: _Tokens.body(color: _Tokens.textSecondary)))
                    : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 12),
                  itemCount: _bookerReportList.length,
                  itemBuilder: (context, index) {
                    final item = _bookerReportList[index];
                    return _balanceTile(
                      title: item['username'],
                      subtitle: "Total Sale: Rs. ${_moneyFormat.format(item['totalSale'])}\nReceived: Rs. ${_moneyFormat.format(item['amountReceived'])}",
                      balance: item['balance'],
                      onTap: () => _showPaymentEntryDialog(item),
                    );
                  },
                )),
              ),
            ],
          ),

          // VIEW 2: DYNAMIC SYMMETRICAL CUSTOMER LEDGER BREAKDOWN
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Symmetrical Dropdown Input Field Component
                    Expanded(
                      flex: 2,
                      child: DropdownButtonFormField<String>(
                        isExpanded: true,
                        style: _Tokens.body(color: _Tokens.textPrimary),
                        icon: Icon(Icons.keyboard_arrow_down, color: _Tokens.textSecondary),
                        decoration: _Tokens.fieldDecoration(label: "Select Booker"),
                        value: _selectedDetailedUserId,
                        items: _userList.map((u) => DropdownMenuItem(value: u['uid'].toString(), child: Text(u['username'], overflow: TextOverflow.ellipsis))).toList(),
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() => _selectedDetailedUserId = v);
                          _generateCustomerLedgerData(v);
                        },
                      ),
                    ),
                    const SizedBox(width: 10),

                    // Symmetrical Date Picker Container
                    Expanded(
                      flex: 2,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _selectedLedgerDate,
                            firstDate: DateTime(2024),
                            lastDate: DateTime(2030),
                          );
                          if (picked != null) {
                            setState(() => _selectedLedgerDate = picked);
                            if (_selectedDetailedUserId != null) {
                              _generateCustomerLedgerData(_selectedDetailedUserId!);
                            }
                          }
                        },
                        child: InputDecorator(
                          decoration: _Tokens.fieldDecoration(label: "Select Date"),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  DateFormat("dd-MM-yyyy").format(_selectedLedgerDate),
                                  style: _Tokens.body(size: 14, color: _Tokens.textPrimary),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Icon(Icons.arrow_drop_down, color: _Tokens.textSecondary),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      decoration: BoxDecoration(
                        color: _customerLedgerList.isEmpty ? _Tokens.border.withOpacity(0.4) : _Tokens.amberBg,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: IconButton(
                        icon: Icon(Icons.picture_as_pdf_outlined, color: _customerLedgerList.isEmpty ? _Tokens.textSecondary : _Tokens.amber, size: 24),
                        onPressed: _customerLedgerList.isEmpty ? null : _showDetailedLedgerPreview,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _isLoadingLedger
                    ? Center(child: CircularProgressIndicator(color: _Tokens.amber))
                    : (_selectedDetailedUserId == null
                    ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Text(
                      "Please select a booker to view customer balances statement",
                      textAlign: TextAlign.center,
                      style: _Tokens.body(color: _Tokens.textSecondary),
                    ),
                  ),
                )
                    : (_customerLedgerList.isEmpty
                    ? Center(child: Text("No transactions recorded on this specific date", style: _Tokens.body(color: _Tokens.textSecondary)))
                    : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 12),
                  itemCount: _customerLedgerList.length,
                  itemBuilder: (context, idx) {
                    final ledgerRow = _customerLedgerList[idx];
                    return _balanceTile(
                      title: ledgerRow['customerName'],
                      subtitle: "Area: ${ledgerRow['area']}\nTotal Order Value: Rs. ${_moneyFormat.format(ledgerRow['totalSales'])}\nRecovered: Rs. ${_moneyFormat.format(ledgerRow['recovered'])}",
                      balance: ledgerRow['balance'],
                      onTap: () => _showCustomerPaymentDialog(ledgerRow),
                    );
                  },
                ))),
              ),
            ],
          ),
        ],
      ),
    );
  }
}