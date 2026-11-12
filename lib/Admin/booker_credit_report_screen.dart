import 'dart:typed_data';
import 'package:an_agency/ui/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../account/account.dart';
import '../khata.dart' show KhataBook, loadCompanyKhata;
import '../ui/kpi_card.dart';
import '../ui/excel_export.dart';
import '../targets/targets_tab.dart';
import 'dashboard_overview.dart' show dashRs;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

// ---------------------------------------------------------------------------
// Same design tokens used across the rest of the app. Worth pulling into a
// shared lib/design_tokens.dart at some point instead of duplicating this
// class per file.
// ---------------------------------------------------------------------------
class _Tokens {
  static const navyDark = AppColors.navy;
  static const amber = AppColors.amber;
  static const bg = AppColors.bg;
  static const textPrimary = AppColors.text;
  static const textSecondary = AppColors.muted;
  static const border = AppColors.border;
  static const error = AppColors.red;
  static const green = AppColors.green;

  static TextStyle display({double size = 18, Color? color, FontWeight w = FontWeight.w600}) =>
      GoogleFonts.inter(fontSize: size, fontWeight: w, color: color ?? textPrimary, height: 1.2);

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
    _tabController = TabController(length: 3, vsync: this);
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
      // The day's sales come straight from that day's invoices, so a day counts even when nobody
      // computed its DSR.
      final day = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
      Future<QuerySnapshot<Map<String, dynamic>>?> orNull(Future<QuerySnapshot<Map<String, dynamic>>> q) =>
          q.then<QuerySnapshot<Map<String, dynamic>>?>((s) => s, onError: (_) => null);
      final results = await Future.wait<Object?>([
        companyCol('invoices')
            .where('salesDate', isEqualTo: DateFormat("dd-MM-yyyy").format(_selectedDate))
            .get(),
        companyCol('booker_credits')
            .where('dateStr', isEqualTo: formattedTargetDate)
            .get(),
        // Recoveries that day: payments in the khata (by the booker, or the office's Receive
        // Recovery), and older office recoveries.
        orNull(companyCol('khata_entries')
            .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(day))
            .where('date', isLessThan: Timestamp.fromDate(day.add(const Duration(days: 1))))
            .get()),
        orNull(companyCol('customer_recoveries').where('dateStr', isEqualTo: formattedTargetDate).get()),
        // What each booker's shops owe in all (their khata).
        loadCompanyKhata().then<Map<String, KhataBook>?>((k) => k, onError: (_) => null),
      ]);
      final invoiceSnapshot = results[0] as QuerySnapshot<Map<String, dynamic>>;
      final creditSnapshot = results[1] as QuerySnapshot<Map<String, dynamic>>;
      final salesByBooker = <String, double>{};
      for (final d in invoiceSnapshot.docs) {
        final m = d.data();
        final uid = (m['userId'] ?? '').toString();
        salesByBooker[uid] = (salesByBooker[uid] ?? 0) + (num.tryParse('${m['grandTotal'] ?? m['total'] ?? 0}') ?? 0).toDouble();
      }

      Map<String, double> paymentMap = {};
      for (var doc in creditSnapshot.docs) {
        final data = doc.data();
        paymentMap[data['userId']] = (num.tryParse(data['amountReceived']?.toString() ?? "0") ?? 0).toDouble();
      }

      final recoveredBy = <String, double>{};
      for (final d in (results[2] as QuerySnapshot<Map<String, dynamic>>?)?.docs ?? const []) {
        final m = d.data();
        if (m['type'] != 'payment') continue;
        final uid = (m['userId'] ?? '').toString();
        recoveredBy[uid] = (recoveredBy[uid] ?? 0) + (num.tryParse('${m['amount'] ?? 0}') ?? 0).toDouble();
      }
      for (final d in (results[3] as QuerySnapshot<Map<String, dynamic>>?)?.docs ?? const []) {
        final m = d.data();
        final uid = (m['userId'] ?? '').toString();
        recoveredBy[uid] = (recoveredBy[uid] ?? 0) + (num.tryParse('${m['amountPaid'] ?? 0}') ?? 0).toDouble();
      }
      final books = results[4] as Map<String, KhataBook>?;

      List<Map<String, dynamic>> computedList = [];

      for (var booker in bookers) {
        final String uid = booker['uid']!;
        final double totalSalesAmount = salesByBooker[uid] ?? 0.0;

        double amountReceived = paymentMap[uid] ?? 0.0;
        double balanceRemaining = totalSalesAmount - amountReceived;

        computedList.add({
          'userId': uid,
          'username': booker['username'],
          'email': booker['email'],
          'totalSale': totalSalesAmount,
          'recovered': recoveredBy[uid] ?? 0.0,
          'amountReceived': amountReceived,
          'balance': balanceRemaining,
          'marketDue': books?[uid]?.totalDue ?? 0.0,
          'shopsOwing': books?[uid]?.shopsOwing ?? 0,
        });
      }
      // Busiest first: the day's sales, then what the market owes.
      computedList.sort((a, b) {
        final bySale = (b['totalSale'] as double).compareTo(a['totalSale'] as double);
        return bySale != 0 ? bySale : (b['marketDue'] as double).compareTo(a['marketDue'] as double);
      });

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
            Text(
              (ledgerRow['balance'] as double) < -0.5
                  ? "Advance with you: ${_balanceText(ledgerRow['balance']).replaceFirst('Advance ', '')}"
                  : "Current Outstanding: ${_balanceText(ledgerRow['balance'])}",
              style: _Tokens.body(
                  color: (ledgerRow['balance'] as double) < -0.5 ? _Tokens.green : _Tokens.error, w: FontWeight.w700),
            ),
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
              final booker = _userList.where((u) => u['uid'] == _selectedDetailedUserId).firstOrNull ?? const <String, String>{};
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
              _balanceText(l['balance']),
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

  // ==================== Layout helpers (the dashboard's look) ====================

  /// A balance below zero means more was paid than owed: show it as an advance, not a minus.
  String _balanceText(double b) => b < -0.5 ? 'Advance Rs. ${_moneyFormat.format(-b)}' : 'Rs. ${_moneyFormat.format(b)}';

  static final _whole = NumberFormat('#,##0');
  String _n(double v) => v.abs() < 0.5 ? '–' : _whole.format(v.round());

  Widget _panel({required Widget child, EdgeInsets padding = const EdgeInsets.fromLTRB(0, 18, 0, 0)}) =>
      Container(decoration: kpiCardDecoration(), clipBehavior: Clip.antiAlias, padding: padding, child: child);

  Widget _panelTitle(IconData icon, String title, String note) => Row(children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(color: AppColors.brandSoft, borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, size: 15, color: AppColors.navy),
        ),
        const SizedBox(width: 10),
        Text(title, style: GoogleFonts.inter(fontSize: 14.5, fontWeight: FontWeight.w700, color: AppColors.text)),
        const SizedBox(width: 8),
        Expanded(child: Text(note, style: _Tokens.body(size: 11.5, color: AppColors.muted), overflow: TextOverflow.ellipsis)),
      ]);

  /// ‹ Wed, 11 Nov 2026 › — tap the date to pick one.
  Widget _dateSwitcher(DateTime date, void Function(DateTime) onChanged) {
    final today = DateTime.now();
    final isToday = date.year == today.year && date.month == today.month && date.day == today.day;
    return Container(
      decoration: kpiCardDecoration(),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
          tooltip: 'Day before',
          icon: const Icon(Icons.chevron_left),
          onPressed: () => onChanged(date.subtract(const Duration(days: 1))),
        ),
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () async {
            final picked = await showDatePicker(context: context, initialDate: date, firstDate: DateTime(2024), lastDate: today);
            if (picked != null) onChanged(picked);
          },
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 150),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(DateFormat('EEE, d MMM yyyy').format(date),
                    style: GoogleFonts.inter(fontSize: 14.5, fontWeight: FontWeight.w700, color: AppColors.text)),
                Text(isToday ? 'today' : 'tap to choose a date', style: _Tokens.body(size: 11, color: AppColors.muted)),
              ]),
            ),
          ),
        ),
        IconButton(
          tooltip: 'Next day',
          icon: const Icon(Icons.chevron_right),
          onPressed: isToday ? null : () => onChanged(date.add(const Duration(days: 1))),
        ),
      ]),
    );
  }

  Widget _headCell(String t, {int flex = 2, bool right = true}) => Expanded(
        flex: flex,
        child: Text(t, textAlign: right ? TextAlign.right : TextAlign.left,
            style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: AppColors.muted)),
      );

  Widget _numCell(double v, {int flex = 2, Color? color, bool bold = false}) => Expanded(
        flex: flex,
        child: Text(_n(v),
            textAlign: TextAlign.right,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              color: v.abs() < 0.5 ? AppColors.muted : (color ?? AppColors.text),
              fontFeatures: const [FontFeature.tabularFigures()],
            )),
      );

  Widget _empty(IconData icon, String title, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 36, color: AppColors.muted),
          const SizedBox(height: 10),
          Text(title, textAlign: TextAlign.center, style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.text)),
          const SizedBox(height: 4),
          Text(text, textAlign: TextAlign.center, style: _Tokens.body(color: AppColors.muted)),
        ]),
      );

  // ==================== Tab 1: the day, booker by booker ====================

  Widget _dailyTab() {
    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= 860;
      final pad = wide ? 24.0 : 14.0;
      final list = _bookerReportList;
      double sum(String k) => list.fold<double>(0, (s, b) => s + (b[k] as num).toDouble());
      final sales = sum('totalSale');
      final recovered = sum('recovered');
      final received = sum('amountReceived');
      final left = sales - received;
      final due = sum('marketDue');
      return RefreshIndicator(
        onRefresh: _generateCreditData,
        child: ListView(
          padding: EdgeInsets.fromLTRB(pad, 18, pad, 32),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1180),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    _dateSwitcher(_selectedDate, (d) {
                      setState(() => _selectedDate = d);
                      _generateCreditData();
                    }),
                    const Spacer(),
                    ExcelButton(
                      onPressed: list.isEmpty
                          ? null
                          : () => exportToExcel(
                                context,
                                fileName: exportFileName('booker-credits-${DateFormat('yyyy-MM-dd').format(_selectedDate)}'),
                                title: 'Booker credits',
                                subtitle: DateFormat('EEE, d MMM yyyy').format(_selectedDate),
                                sheets: [
                                  ExportSheet(
                                    name: 'Bookers',
                                    headers: ['Booker', 'Sales (Rs)', 'Recovered from shops (Rs)', 'Received at office (Rs)', 'Balance (Rs)',
                                      'Market owes (Rs)', 'Shops owing'],
                                    rows: [
                                      for (final b in list)
                                        [b['username'], b['totalSale'], b['recovered'], b['amountReceived'], b['balance'], b['marketDue'], b['shopsOwing']],
                                    ],
                                    totals: ['Total', sales, recovered, received, left, due],
                                  ),
                                ],
                              ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: list.isEmpty ? null : _printCreditReport,
                      icon: const Icon(Icons.print_outlined, size: 18),
                      label: const Text('Print'),
                    ),
                  ]),
                  const SizedBox(height: 16),
                  if (_isLoadingSummary && list.isEmpty)
                    const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator()))
                  else ...[
                    kpiGrid([
                      KpiCard(
                        label: 'SALES',
                        icon: Icons.point_of_sale_outlined,
                        tint: AppColors.blue,
                        tintBg: AppColors.blueBg,
                        value: dashRs(sales),
                        sub: '${list.where((b) => (b['totalSale'] as double) > 0.5).length} of ${list.length} bookers sold',
                      ),
                      KpiCard(
                        label: 'RECOVERED FROM SHOPS',
                        icon: Icons.storefront_outlined,
                        tint: AppColors.green,
                        tintBg: AppColors.greenBg,
                        value: dashRs(recovered),
                        sub: 'payments on old bills, this day',
                      ),
                      KpiCard(
                        label: 'RECEIVED AT OFFICE',
                        icon: Icons.payments_outlined,
                        tint: AppColors.navy,
                        tintBg: AppColors.brandSoft,
                        value: dashRs(received),
                        sub: sales < 0.5 ? 'cash handed in by bookers' : '${(received / sales * 100).clamp(0, 999).toStringAsFixed(0)}% of the day\'s sales',
                        progress: sales < 0.5 ? null : received / sales,
                      ),
                      KpiCard(
                        label: 'BOOKER BALANCE',
                        icon: Icons.account_balance_wallet_outlined,
                        tint: left > 0.5 ? AppColors.red : AppColors.green,
                        tintBg: left > 0.5 ? AppColors.redBg : AppColors.greenBg,
                        value: dashRs(left),
                        valueColor: left > 0.5 ? AppColors.red : null,
                        sub: 'sales not yet paid in · shops owe ${dashRs(due)} in all',
                      ),
                    ], wide ? 4 : 2),
                    const SizedBox(height: 16),
                    _panel(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: _panelTitle(Icons.people_outline, 'Bookers', 'tap Receive when a booker hands in cash'),
                        ),
                        const SizedBox(height: 12),
                        if (list.isEmpty)
                          _empty(Icons.people_outline, 'No bookers yet', 'Bookers appear here once they have logged in.')
                        else ...[
                          if (wide)
                            Container(
                              color: AppColors.bg,
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
                              child: Row(children: [
                                _headCell('BOOKER', flex: 4, right: false),
                                _headCell('SALES'),
                                _headCell('RECOVERED'),
                                _headCell('RECEIVED'),
                                _headCell('BALANCE'),
                                _headCell('MARKET OWES'),
                                const SizedBox(width: 104),
                              ]),
                            ),
                          for (var i = 0; i < list.length; i++) ...[
                            if (i > 0) const Divider(height: 1),
                            wide ? _bookerRowWide(list[i]) : _bookerRowNarrow(list[i]),
                          ],
                          if (wide) ...[
                            const Divider(height: 1),
                            Container(
                              color: AppColors.bg,
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
                              child: Row(children: [
                                Expanded(flex: 4, child: Text('Total', style: _Tokens.body(w: FontWeight.w700))),
                                _numCell(sales, bold: true),
                                _numCell(recovered, bold: true, color: AppColors.green),
                                _numCell(received, bold: true),
                                _numCell(left, bold: true, color: left > 0.5 ? AppColors.red : AppColors.green),
                                _numCell(due, bold: true, color: AppColors.amberDark),
                                const SizedBox(width: 104),
                              ]),
                            ),
                          ],
                        ],
                      ]),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Recovered: payments from shops on this day (the booker\'s khata and the office\'s Receive Recovery). '
                      'Received: cash the booker paid in at the office. Balance: the day\'s sales less what the booker paid in. '
                      'Market owes: everything the booker\'s shops owe, all days.',
                      style: _Tokens.body(size: 11.5, color: AppColors.muted),
                    ),
                  ],
                ]),
              ),
            ),
          ],
        ),
      );
    });
  }

  Widget _avatar(String name) => CircleAvatar(
        radius: 16,
        backgroundColor: AppColors.brandSoft,
        child: Text(name.isEmpty ? 'B' : name[0].toUpperCase(),
            style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: AppColors.navy, fontSize: 13)),
      );

  Widget _bookerRowWide(Map<String, dynamic> b) {
    final left = b['balance'] as double;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(children: [
        Expanded(
          flex: 4,
          child: Row(children: [
            _avatar((b['username'] ?? '').toString()),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text((b['username'] ?? '').toString(), overflow: TextOverflow.ellipsis, style: _Tokens.body(w: FontWeight.w600, size: 13.5)),
                Text('${b['shopsOwing']} shop${b['shopsOwing'] == 1 ? '' : 's'} owe', style: _Tokens.body(size: 11.5, color: AppColors.muted)),
              ]),
            ),
          ]),
        ),
        _numCell(b['totalSale'] as double),
        _numCell(b['recovered'] as double, color: AppColors.green),
        _numCell(b['amountReceived'] as double),
        _numCell(left, color: left > 0.5 ? AppColors.red : AppColors.green, bold: true),
        _numCell(b['marketDue'] as double, color: AppColors.amberDark),
        SizedBox(
          width: 104,
          child: Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton(
              onPressed: () => _showPaymentEntryDialog(b),
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), visualDensity: VisualDensity.compact),
              child: const Text('Receive'),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _bookerRowNarrow(Map<String, dynamic> b) {
    final left = b['balance'] as double;
    Widget fig(String label, double v, [Color? c]) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: _Tokens.body(size: 10.5, color: AppColors.muted)),
            Text(_n(v), style: _Tokens.body(w: FontWeight.w700, size: 13, color: v.abs() < 0.5 ? AppColors.muted : (c ?? AppColors.text))),
          ]),
        );
    return InkWell(
      onTap: () => _showPaymentEntryDialog(b),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            _avatar((b['username'] ?? '').toString()),
            const SizedBox(width: 10),
            Expanded(child: Text((b['username'] ?? '').toString(), style: _Tokens.body(w: FontWeight.w600, size: 14))),
            Text('owes ${_n(b['marketDue'] as double)}', style: _Tokens.body(size: 12, color: AppColors.amberDark, w: FontWeight.w600)),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            fig('Sales', b['totalSale'] as double),
            fig('Recovered', b['recovered'] as double, AppColors.green),
            fig('Received', b['amountReceived'] as double),
            fig('Balance', left, left > 0.5 ? AppColors.red : AppColors.green),
          ]),
        ]),
      ),
    );
  }

  // ==================== Tab 2: one booker's shops on a day ====================

  Widget _ledgerTab() {
    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= 860;
      final pad = wide ? 24.0 : 14.0;
      final rows = _customerLedgerList;
      double sum(String k) => rows.fold<double>(0, (s, r) => s + (r[k] as num).toDouble());
      final picker = SizedBox(
        width: wide ? 260 : double.infinity,
        child: DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: _selectedDetailedUserId,
          decoration: const InputDecoration(labelText: 'Booker', prefixIcon: Icon(Icons.person_outline, size: 20)),
          items: _userList
              .map((u) => DropdownMenuItem(value: u['uid'].toString(), child: Text(u['username'], overflow: TextOverflow.ellipsis)))
              .toList(),
          onChanged: (v) {
            if (v == null) return;
            setState(() => _selectedDetailedUserId = v);
            _generateCustomerLedgerData(v);
          },
        ),
      );
      final date = _dateSwitcher(_selectedLedgerDate, (d) {
        setState(() => _selectedLedgerDate = d);
        if (_selectedDetailedUserId != null) _generateCustomerLedgerData(_selectedDetailedUserId!);
      });
      final pdf = OutlinedButton.icon(
        onPressed: rows.isEmpty ? null : _showDetailedLedgerPreview,
        icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
        label: const Text('PDF'),
      );
      return ListView(
        padding: EdgeInsets.fromLTRB(pad, 18, pad, 32),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1180),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (wide)
                  Row(children: [picker, const SizedBox(width: 12), date, const Spacer(), pdf])
                else ...[
                  picker,
                  const SizedBox(height: 10),
                  Row(children: [Expanded(child: Center(child: date)), const SizedBox(width: 8), pdf]),
                ],
                const SizedBox(height: 16),
                if (_isLoadingLedger)
                  const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator()))
                else if (_selectedDetailedUserId == null)
                  _panel(
                    padding: EdgeInsets.zero,
                    child: _empty(Icons.person_search_outlined, 'Choose a booker', 'See each shop they sold to on the day, what was recovered, and record a recovery.'),
                  )
                else ...[
                  kpiGrid([
                    KpiCard(
                      label: 'SALES',
                      icon: Icons.point_of_sale_outlined,
                      tint: AppColors.blue,
                      tintBg: AppColors.blueBg,
                      value: dashRs(sum('totalSales')),
                      sub: '${rows.length} shop${rows.length == 1 ? '' : 's'}',
                    ),
                    KpiCard(
                      label: 'RECOVERED',
                      icon: Icons.storefront_outlined,
                      tint: AppColors.green,
                      tintBg: AppColors.greenBg,
                      value: dashRs(sum('recovered')),
                      sub: 'from these shops, this day',
                    ),
                    KpiCard(
                      // Paid more than sold: that's an advance, not a minus.
                      label: sum('balance') < -0.5 ? 'ADVANCE' : 'BALANCE',
                      icon: Icons.account_balance_wallet_outlined,
                      tint: sum('balance') > 0.5 ? AppColors.red : AppColors.green,
                      tintBg: sum('balance') > 0.5 ? AppColors.redBg : AppColors.greenBg,
                      value: dashRs(sum('balance').abs()),
                      valueColor: sum('balance') > 0.5 ? AppColors.red : (sum('balance') < -0.5 ? AppColors.green : null),
                      sub: sum('balance') < -0.5 ? 'shops paid more than this day\'s sales' : 'sales less recovered',
                    ),
                  ], wide ? 3 : 2, height: 132),
                  const SizedBox(height: 16),
                  _panel(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: _panelTitle(Icons.storefront_outlined, 'Shops', 'tap Receive to record a recovery'),
                      ),
                      const SizedBox(height: 12),
                      if (rows.isEmpty)
                        _empty(Icons.event_busy_outlined, 'Nothing on this day', 'This booker has no invoices on the chosen date.')
                      else ...[
                        if (wide)
                          Container(
                            color: AppColors.bg,
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
                            child: Row(children: [
                              _headCell('SHOP', flex: 5, right: false),
                              _headCell('SALES'),
                              _headCell('RECOVERED'),
                              _headCell('BALANCE'),
                              const SizedBox(width: 104),
                            ]),
                          ),
                        for (var i = 0; i < rows.length; i++) ...[
                          if (i > 0) const Divider(height: 1),
                          _shopRow(rows[i], wide),
                        ],
                      ],
                    ]),
                  ),
                ],
              ]),
            ),
          ),
        ],
      );
    });
  }

  Widget _shopRow(Map<String, dynamic> r, bool wide) {
    final bal = r['balance'] as double;
    final balColor = bal > 0.5 ? AppColors.red : AppColors.green;
    final name = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text((r['customerName'] ?? '').toString(), overflow: TextOverflow.ellipsis, style: _Tokens.body(w: FontWeight.w600, size: 13.5)),
      Text('Area: ${r['area']}', overflow: TextOverflow.ellipsis, style: _Tokens.body(size: 11.5, color: AppColors.muted)),
    ]);
    final receive = OutlinedButton(
      onPressed: () => _showCustomerPaymentDialog(r),
      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), visualDensity: VisualDensity.compact),
      child: const Text('Receive'),
    );
    if (wide) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(children: [
          Expanded(flex: 5, child: name),
          _numCell(r['totalSales'] as double),
          _numCell(r['recovered'] as double, color: AppColors.green),
          Expanded(
            flex: 2,
            child: Text(bal < -0.5 ? 'Adv. ${_n(-bal)}' : _n(bal),
                textAlign: TextAlign.right, style: _Tokens.body(w: FontWeight.w700, size: 13, color: bal.abs() < 0.5 ? AppColors.muted : balColor)),
          ),
          SizedBox(width: 104, child: Align(alignment: Alignment.centerRight, child: receive)),
        ]),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(children: [
        Expanded(child: name),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(_balanceText(bal), style: _Tokens.body(w: FontWeight.w700, size: 13, color: balColor)),
          Text('Sale ${_n(r['totalSales'] as double)} · Rec. ${_n(r['recovered'] as double)}', style: _Tokens.body(size: 11, color: AppColors.muted)),
        ]),
        const SizedBox(width: 10),
        receive,
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Booker credits'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(text: 'Daily summary'),
            Tab(text: 'Customer ledger'),
            Tab(text: 'Targets'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_dailyTab(), _ledgerTab(), const TargetsTab()],
      ),
    );
  }
}
