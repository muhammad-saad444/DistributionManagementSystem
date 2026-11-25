import 'package:flutter/material.dart';
import '../returns/return_sheet.dart';
import '../returns/returns_screen.dart';
import '../ui/excel_export.dart';
import 'package:an_agency/ui/app_theme.dart';
import '../account/account.dart';
import '../audit/audit.dart';
import '../invoices/invoice_pdf.dart';
import '../invoices/company_profile.dart';
import '../invoices/invoice_tax.dart';
import '../invoices/sales_tax_screen.dart';
import '../report_areas.dart';
import '../khata.dart' show loadKhata, KhataBook, KhataLine, KhataStatusPill;
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../inventory/inventory_data.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';

// Same tokens used across the Admin section (admin_dashboard_screen.dart,
// stock_and_sales_screen.dart). Delete this block and import your shared
// _Tokens file if you already have one.
class _Tokens {
  static const navy = AppColors.navy;
  static const navyDark = AppColors.navyDark;
  static const amber = AppColors.amber;
  static const bg = AppColors.bg;
  static const border = AppColors.border;
  static const textDark = AppColors.text;
  static const muted = AppColors.muted;
  static const error = AppColors.red;
  static const errorBg = AppColors.redBg;
  static const green = AppColors.green;
  static const greenBg = AppColors.greenBg;
  static const amberBg = AppColors.amberBg;

  static TextStyle display({double size = 18, Color? color, FontWeight w = FontWeight.w700}) =>
      GoogleFonts.inter(fontSize: size, fontWeight: w, color: color ?? textDark);

  static TextStyle body({double size = 13, Color? color, FontWeight w = FontWeight.w400}) =>
      GoogleFonts.inter(fontSize: size, fontWeight: w, color: color ?? textDark);

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

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({Key? key}) : super(key: key);

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  final _firestore = FirebaseFirestore.instance;

  String? selectedUserId;
  DateTime? selectedDate;
  bool showAllDates = true;

  List<Map<String, dynamic>> userList = [];
  bool isLoadingUsers = true;

  // --- PAGINATION STATE ---
  static const int _pageSize = 20;
  final ScrollController _scrollController = ScrollController();
  final List<DocumentSnapshot> _docs = [];
  DocumentSnapshot? _lastDoc;
  bool _isLoadingFirst = true;
  bool _isLoadingMore = false;
  bool _isSyncingFirstPage = false; // cached first page is showing, server copy still on its way
  bool _hasMore = true;
  Object? _loadError;
  int _loadGen = 0; // bumps on every filter change so stale responses are ignored

  // Each booker's khata, for every invoice's Closed / Open status. Null while loading.
  final Map<String, KhataBook?> _khata = {};

  /// Where the invoice is on its way to the shop (Deliveries page), once it is on a trip.
  Widget? _deliveryPill(Map<String, dynamic> data) {
    if ((data['dispatchId'] ?? '').toString().isEmpty) return null;
    final (String text, Color fg, Color bg) = switch ((data['deliveryStatus'] ?? '').toString()) {
      'out' => ('Out for delivery', AppColors.blue, AppColors.blueBg),
      'delivered' => ('Delivered', AppColors.green, AppColors.greenBg),
      'partial' => ('Partly delivered', AppColors.amberDark, AppColors.amberBg),
      'returned' => ('Not delivered', AppColors.red, AppColors.redBg),
      _ => ('On a trip', AppColors.navy, AppColors.brandSoft),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.local_shipping_outlined, size: 12, color: fg),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg)),
      ]),
    );
  }

  KhataLine? _payStatus(Map<String, dynamic> data, String invoiceId) {
    final uid = (data['userId'] ?? '').toString();
    if (uid.isEmpty) return null;
    if (!_khata.containsKey(uid)) {
      _khata[uid] = null;
      loadKhata(uid).then((b) {
        if (mounted) setState(() => _khata[uid] = b);
      }).catchError((Object e) {
        debugPrint('Khata for invoice status: $e');
      });
    }
    return _khata[uid]?.invoiceLine(invoiceId);
  }

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
    _khata.clear(); // payments may have come in: work the statuses out again
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
      if (shownFromCache) _toast("Showing saved data — couldn't reach server", err: true);
    }
  }

  // The list is no longer a live stream, so re-read a single invoice after it's edited/returned.
  Future<void> _refreshDoc(String docId) async {
    try {
      final fresh = await companyCol('invoices').doc(docId).get();
      if (!mounted) return;
      setState(() {
        final i = _docs.indexWhere((d) => d.id == docId);
        if (i == -1) return;
        if (fresh.exists) {
          _docs[i] = fresh;
        } else {
          _docs.removeAt(i);
        }
      });
    } catch (e) {
      debugPrint("Error refreshing invoice $docId: $e");
    }
  }

  Future<void> _fetchUsers() async {
    try {
      final snapshot = await companyCol('sessions').get();
      final users = snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'uid': data['uid']?.toString() ?? '',
          'username': data['username']?.toString() ?? '',
          'email': data['email']?.toString() ?? '',
        };
      }).toList();
      setState(() {
        userList = users;
        isLoadingUsers = false;
      });
    } catch (e) {
      debugPrint("Error fetching sessions users: $e");
      setState(() => isLoadingUsers = false);
    }
  }

  /// Goods back from the shop on this invoice (lib/returns): refund after discount, good units back
  /// in stock, damaged or expired written off, and a record kept. Then the day's reports are rebuilt.
  Future<void> _showReturnInvoicePopup(String docId, Map<String, dynamic> data) async {
    final ts = data['salesDateTs'];
    if (!await ensureOpenPeriod(context, ts is Timestamp ? ts.toDate() : null) || !mounted) return;
    final refund = await showReturnSheet(context, invoiceId: docId, invoice: data);
    if (refund == null) return;
    try {
      await _refreshDoc(docId);
      await _adminComputeDsrAndLoadsheet(
        data['userId']?.toString() ?? '',
        data['userEmail']?.toString() ?? '',
        data['salesDate']?.toString() ?? '',
      );
      _toast("Return saved: Rs ${NumberFormat('#,##0').format(refund.round())} off the shop's bill, reports recalculated");
    } catch (e) {
      _toast("Return saved, but the reports couldn't be recalculated: $e", err: true);
    }
  }

  /// Rebuilds the booker's DSR and load sheet for one Sales Date (dd-MM-yyyy).
  /// Reports are grouped by the invoices' Sales Date, the same way the booker's "Compute Today" does,
  /// so an invoice dated the 25th never lands in the 24th's reports.
  Future<void> _adminComputeDsrAndLoadsheet(String userId, String? userEmail, String salesDate) async {
    setState(() => isLoadingUsers = true);
    try {
      DateTime day;
      try {
        day = DateFormat("dd-MM-yyyy").parseStrict(salesDate.trim());
      } catch (_) {
        _toast("This invoice has no valid Sales Date to compute reports for", err: true);
        return;
      }
      final String dateId = DateFormat("yyyy-MM-dd").format(day);

      final snap = await companyCol('invoices')
          .where('userId', isEqualTo: userId)
          .where('salesDate', isEqualTo: salesDate.trim())
          .get();

      if (snap.docs.isEmpty) {
        _toast("No invoices found for $salesDate", err: true);
        return;
      }

      final areaOf = await invoiceAreas(snap.docs);
      final List<Map<String, dynamic>> dsrRows = [];
      final Map<String, Map<String, dynamic>> productAggregation = {};
      int totalSumQty = 0;
      int totalSumAmount = 0;
      double totalInvoiceDiscounts = 0; // load sheet total is saved after invoice discounts, as in the booker app

      for (var doc in snap.docs) {
        final data = doc.data();
        final items = List.from(data['items'] ?? []);
        double tSale = (num.tryParse(data['total']?.toString() ?? "0") ?? 0).toDouble();
        double nSale = (num.tryParse(data['grandTotal']?.toString() ?? "0") ?? 0).toDouble();
        totalInvoiceDiscounts += tSale - nSale;

        final Map<String, int> prodQtyMap = {};
        final Map<String, double> prodBnsMap = {}; // bonus units (free goods), shown on the DSR's BONUS row

        for (var it in items) {
          final String name = it['Product Name'] ?? 'Unknown';
          int qty = (num.tryParse(it['QTY']?.toString() ?? "0") ?? 0).toInt();
          int ret = (num.tryParse(it['returnQty']?.toString() ?? "0") ?? 0).toInt();
          int actualQty = qty - ret;

          double bns = (num.tryParse((it['BNS'] ?? it['FOC'])?.toString() ?? "0") ?? 0).toDouble(); // bonus can be fractional
          double tp = (num.tryParse(it['TP']?.toString() ?? "0") ?? 0).toDouble();
          int actualGross = (actualQty * tp).toInt();

          if (name.isNotEmpty) {
            prodQtyMap[name] = (prodQtyMap[name] ?? 0) + actualQty;
            prodBnsMap[name] = (prodBnsMap[name] ?? 0) + bns;

            if (!productAggregation.containsKey(name)) {
              productAggregation[name] = {"productName": name, "qty": 0, "bns": 0.0, "amount": 0};
            }
            productAggregation[name]!["qty"] += actualQty;
            productAggregation[name]!["bns"] += bns;
            productAggregation[name]!["amount"] += actualGross;

            totalSumQty += actualQty;
            totalSumAmount += actualGross;
          }
        }

        dsrRows.add({
          "invoiceNumber": data['invoiceNumber']?.toString() ?? '',
          "customer": data['customer'] ?? 'Unknown',
          "area": areaOf[doc.id] ?? '',
          "totalSale": tSale,
          "discount": tSale - nSale,
          "netSale": nSale,
          "productQty": prodQtyMap,
          "productBns": prodBnsMap,
        });
      }

      // DSR rows in invoice order, same as the booker's report.
      int invNum(dynamic v) => int.tryParse(v?.toString() ?? '') ?? 0;
      dsrRows.sort((a, b) => invNum(a['invoiceNumber']).compareTo(invNum(b['invoiceNumber'])));

      final String docId = "${dateId}__$userId";

      WriteBatch batch = _firestore.batch();
      batch.set(companyCol('dsr_reports').doc(docId), {
        "dateStr": dateId,
        "generatedAt": FieldValue.serverTimestamp(),
        "userId": userId,
        "userEmail": userEmail,
        "rows": dsrRows,
      });

      batch.set(companyCol('load_sheets').doc(docId), {
        "dateStr": dateId,
        "generatedAt": FieldValue.serverTimestamp(),
        "userId": userId,
        "userEmail": userEmail,
        "items": productAggregation.values.toList(),
        "areas": areaOf.values.where((a) => a.isNotEmpty).toSet().join(", "),
        "totals": {
          "sumQty": totalSumQty,
          "sumAmount": totalSumAmount - totalInvoiceDiscounts,
          "uniqueProducts": productAggregation.length,
        }
      });

      await batch.commit();
      _toast("Reports Updated Successfully");
    } catch (e) {
      _toast("Compute Error: $e", err: true);
    } finally {
      setState(() => isLoadingUsers = false);
    }
  }

  void _toast(String msg, {bool err = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: err ? _Tokens.error : _Tokens.green,
        content: Text(msg, style: _Tokens.body(color: Colors.white)),
      ),
    );
  }

  /// The list is a cached page, so returns/edits made elsewhere (e.g. by the booker) aren't in it.
  /// Re-read the invoice from Firestore before showing or changing it, and update the cached row.
  Future<Map<String, dynamic>> _freshInvoiceData(String docId, Map<String, dynamic> cached) async {
    try {
      final fresh = await companyCol('invoices').doc(docId).get(const GetOptions(source: Source.server));
      if (fresh.exists && fresh.data() != null) {
        if (mounted) {
          setState(() {
            final i = _docs.indexWhere((d) => d.id == docId);
            if (i != -1) _docs[i] = fresh;
          });
        }
        return fresh.data()!;
      }
    } catch (e) {
      debugPrint("Couldn't refresh invoice $docId: $e");
    }
    return cached;
  }

  Future<void> _openInvoiceDetails(String docId, Map<String, dynamic> cached) async {
    final data = await _freshInvoiceData(docId, cached);
    if (!mounted) return;
    _showInvoiceDetails(docId, data);
  }

  Future<void> _openEditInvoice(String docId, Map<String, dynamic> cached) async {
    final data = await _freshInvoiceData(docId, cached);
    if (!mounted) return;
    final reason = await _unlock(docId, data, doing: 'change');
    if (reason == null || !mounted) return;
    final profile = await loadCompanyProfile();
    if (!mounted) return;
    _showEditInvoicePopup(docId, data, reason: reason, profile: profile);
  }

  /// Paid, delivered and closed-books invoices are locked. Returns the reason given to change a
  /// paid or delivered one ('' if it isn't locked), or null when it can't or shouldn't be changed.
  Future<String?> _unlock(String docId, Map<String, dynamic> data, {required String doing}) async {
    final lock = invoiceLock(data,
        paid: _payStatus(data, docId)?.isClosed ?? false, closedUntil: await booksClosedUntil(fresh: true));
    if (!mounted) return null;
    if (lock == InvoiceLock.closedPeriod) {
      final ts = data['salesDateTs'];
      await ensureOpenPeriod(context, ts is Timestamp ? ts.toDate() : null);
      return null;
    }
    return askLockReason(context, lock, doing: doing);
  }

  String _invoiceTitle(Map<String, dynamic> data) => 'Invoice #${data['invoiceNumber'] ?? '-'} · ${data['customer'] ?? '-'}';

  void _showInvoiceDetails(String docId, Map<String, dynamic> data) {
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
              Text('Invoice #${data['invoiceNumber']}', style: _Tokens.display(size: 17)),
              Divider(height: 20, color: _Tokens.border),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: PdfPreview(
                    build: (format) async {
                      final pdf = pw.Document();
                      final withArea = {...data, 'area': await invoiceAreaOf(data)};
                      pdf.addPage(await _invoicePage(withArea));
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
                    _sheetAction(
                      icon: Icons.print_outlined,
                      color: _Tokens.navy,
                      label: "Print",
                      onTap: () => _printReport(data),
                    ),
                    _sheetAction(
                      icon: Icons.assignment_return_outlined,
                      color: _Tokens.amber,
                      label: "Return",
                      onTap: () async {
                        Navigator.pop(context);
                        final fresh = await _freshInvoiceData(docId, data);
                        if (mounted) _showReturnInvoicePopup(docId, fresh);
                      },
                    ),
                    _sheetAction(
                      icon: Icons.refresh,
                      color: _Tokens.green,
                      label: "Compute",
                      onTap: () => _adminComputeDsrAndLoadsheet(data['userId'], data['userEmail'], data['salesDate']?.toString() ?? ''),
                    ),
                    _sheetAction(
                      icon: Icons.delete_outline,
                      color: _Tokens.error,
                      label: "Delete",
                      onTap: () { Navigator.pop(context); _deleteInvoice(docId, data); },
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

  Widget _sheetAction({required IconData icon, required Color color, required String label, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 26),
            const SizedBox(height: 4),
            Text(label, style: _Tokens.body(size: 12, w: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteInvoice(String docId, Map<String, dynamic> data) async {
    final reason = await _unlock(docId, data, doing: 'delete');
    if (reason == null || !mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text("Delete Invoice", style: _Tokens.display(size: 18)),
        content: Text("Are you sure you want to delete this invoice?", style: _Tokens.body(color: _Tokens.muted)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text("Cancel", style: _Tokens.body(color: _Tokens.muted, w: FontWeight.w600)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _Tokens.error,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text("Delete", style: _Tokens.body(color: Colors.white, w: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await deleteInvoiceWithStock(docId); // puts its units back into stock
        logAudit(
          area: AuditArea.invoice,
          action: AuditAction.delete,
          refId: docId,
          title: _invoiceTitle(data),
          amount: (num.tryParse('${data['grandTotal'] ?? data['total'] ?? 0}') ?? 0).toDouble(),
          changes: [
            AuditChange('Sales date', auditValue(data['salesDate']), ''),
            AuditChange('Booker', (data['userEmail'] ?? '').toString(), ''),
            for (final it in (data['items'] as List? ?? const []))
              if (it is Map) AuditChange((it['Product Name'] ?? '').toString(), 'qty ${auditValue(it['QTY'] ?? 0)} at ${auditValue(it['TP'] ?? 0)}', ''),
          ],
          reason: reason,
        );
        if (mounted) setState(() => _docs.removeWhere((d) => d.id == docId));
        _toast("Invoice deleted successfully");
      } catch (e) {
        _toast("Error deleting invoice: $e", err: true);
      }
    }
  }

  Future<void> _printReport(Map<String, dynamic> invoice) async {
    final pdf = pw.Document();
    final withArea = {...invoice, 'area': await invoiceAreaOf(invoice)};
    pdf.addPage(await _invoicePage(withArea));
    await Printing.layoutPdf(onLayout: (format) => pdf.save());
  }

  Future<void> _printAllReports(List<QueryDocumentSnapshot> invoices) async {
    if (invoices.isEmpty) {
      _toast("No invoices found for the current filter.", err: true);
      return;
    }
    final pdf = pw.Document();
    for (var doc in invoices) {
      final data = doc.data() as Map<String, dynamic>;
      final withArea = {...data, 'area': await invoiceAreaOf(data)};
      pdf.addPage(await _invoicePage(withArea));
    }
    await Printing.layoutPdf(onLayout: (format) => pdf.save());
  }

  /// One invoice for printing: the shared layout (lib/invoices/invoice_pdf.dart).
  Future<pw.Page> _invoicePage(Map<String, dynamic> data) async {
    final (profile, buyer) = await invoicePrintDetails(data);
    return invoicePdfPage(data, profile: profile, buyer: buyer, booker: (data['userEmail'] ?? '').toString(), area: (data['area'] ?? '').toString());
  }

  void _showEditInvoicePopup(String docId, Map<String, dynamic> data,
      {String reason = '', CompanyProfile profile = const CompanyProfile()}) {
    final customerCtrl = TextEditingController(text: data['customer'] ?? '');
    final areaCtrl = TextEditingController(text: data['area'] ?? '');
    final dateCtrl = TextEditingController(text: data['salesDate'] ?? '');

    // a deep copy: the invoice's own lines stay as they were (for Cancel and for the audit log)
    List<Map<String, dynamic>> items = [for (final it in (data["items"] as List? ?? const [])) if (it is Map) Map<String, dynamic>.from(it)];

    int discountPercent = int.tryParse(data['discountPercent']?.toString() ?? "0") ?? 0;
    int discountValue = int.tryParse(data['discountValue']?.toString() ?? "0") ?? 0;
    String discountType = data['discountType']?.toString() ?? "flat";

    int calculateTotal() {
      int total = 0;
      for (var item in items) {
        total += (num.tryParse(item["Gross Total"]?.toString() ?? "0") ?? 0).toInt();
      }
      return total;
    }

    int calculateGrandTotal() {
      final total = calculateTotal();
      return discountType == "percent"
          ? total - ((total * discountPercent) ~/ 100)
          : total - discountValue;
    }

    // Sales tax on this invoice: on if it was made with it. The office can add it (when the company
    // works on sales tax) or take it off; an invoice keeps the rate it was made with.
    final saved = taxOf(data);
    var taxOn = saved != null;
    final canTax = saved != null || profile.taxEnabled;
    final taxRate = saved?.rate ?? profile.taxRate;
    final taxInclusive = saved?.inclusive ?? profile.taxInclusive;
    Map<String, dynamic> taxNow() =>
        taxFieldsSwitched(items, calculateGrandTotal().toDouble(), on: taxOn, rate: taxRate, inclusive: taxInclusive);

    /// What the shop pays: the total after discount, plus sales tax if it is added on top.
    double withTax() => ((taxNow()['grandTotal'] as num?) ?? calculateGrandTotal()).toDouble();

    void recalcRow(int i) {
      int tp = (num.tryParse(items[i]["TP"]?.toString() ?? "0") ?? 0).toInt();
      int qty = (num.tryParse(items[i]["QTY"]?.toString() ?? "0") ?? 0).toInt();
      items[i]["Gross Total"] = (tp * qty).toString();
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            title: Text("Edit Invoice", style: _Tokens.display(size: 18)),
            content: SizedBox(
              width: double.maxFinite,
              height: 550,
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    TextField(controller: customerCtrl, style: _Tokens.body(), decoration: _Tokens.fieldDecoration(label: "Customer")),
                    const SizedBox(height: 12),
                    TextField(controller: areaCtrl, style: _Tokens.body(), decoration: _Tokens.fieldDecoration(label: "Area")),
                    const SizedBox(height: 12),
                    TextField(
                      controller: dateCtrl,
                      readOnly: true,
                      style: _Tokens.body(),
                      decoration: _Tokens.fieldDecoration(label: "Sales Date", suffixIcon: Icon(Icons.date_range, color: _Tokens.muted)),
                      onTap: () async {
                        final picked = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(2023), lastDate: DateTime(2030));
                        if (picked != null) dateCtrl.text = DateFormat("dd-MM-yyyy").format(picked);
                      },
                    ),
                    const SizedBox(height: 15),
                    Divider(color: _Tokens.border),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text("Invoice Items", style: _Tokens.display(size: 15)),
                    ),
                    const SizedBox(height: 10),
                    Column(
                      children: List.generate(items.length, (i) {
                        return Container(
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          decoration: BoxDecoration(
                            color: _Tokens.bg,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: _Tokens.border),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Column(
                              children: [
                                TextField(
                                  style: _Tokens.body(),
                                  decoration: _Tokens.fieldDecoration(label: "Product Name"),
                                  controller: TextEditingController(text: items[i]["Product Name"]?.toString() ?? ""),
                                  onChanged: (v) => items[i]["Product Name"] = v,
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        style: _Tokens.body(),
                                        decoration: _Tokens.fieldDecoration(label: "TP"),
                                        keyboardType: TextInputType.number,
                                        controller: TextEditingController(text: items[i]["TP"]?.toString() ?? "0"),
                                        onChanged: (v) {
                                          items[i]["TP"] = v;
                                          recalcRow(i);
                                          setState(() {});
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: TextField(
                                        style: _Tokens.body(),
                                        decoration: _Tokens.fieldDecoration(label: "QTY"),
                                        keyboardType: TextInputType.number,
                                        controller: TextEditingController(text: items[i]["QTY"]?.toString() ?? "0"),
                                        onChanged: (v) {
                                          items[i]["QTY"] = v;
                                          recalcRow(i);
                                          setState(() {});
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text("Gross: ${items[i]["Gross Total"]}", style: _Tokens.body(color: _Tokens.green, w: FontWeight.w700)),
                                ),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: IconButton(
                                    icon: Icon(Icons.delete_outline, color: _Tokens.error),
                                    onPressed: () { items.removeAt(i); setState(() {}); },
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                    ),
                    OutlinedButton.icon(
                      icon: Icon(Icons.add, color: _Tokens.navy),
                      label: Text("Add Product", style: _Tokens.body(color: _Tokens.navy, w: FontWeight.w600)),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: _Tokens.border),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () { setState(() { items.add({"Product Name": "", "TP": "0", "QTY": "0", "BNS": "0", "Gross Total": "0"}); }); },
                    ),
                    Divider(color: _Tokens.border),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("Total: ${calculateTotal()}", style: _Tokens.body()),
                          Text("Discount: ${discountType == 'percent' ? '$discountPercent%' : discountValue}", style: _Tokens.body(color: _Tokens.muted)),
                          if (canTax)
                            Row(children: [
                              Text("Sales tax", style: _Tokens.body()),
                              Switch(value: taxOn, onChanged: (v) => setState(() => taxOn = v)),
                              Expanded(
                                child: Text(
                                  taxOn
                                      ? "${taxRate.toStringAsFixed(taxRate % 1 == 0 ? 0 : 1)}%${taxInclusive ? " (included)" : ""}: "
                                          "${((taxNow()['taxAmount'] as num?) ?? 0).round()}"
                                      : "not on this invoice",
                                  style: _Tokens.body(color: _Tokens.muted),
                                ),
                              ),
                            ]),
                          Text("Grand Total: ${withTax().round()}", style: _Tokens.body(color: _Tokens.green, w: FontWeight.w700, size: 15)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text("Cancel", style: _Tokens.body(color: _Tokens.muted, w: FontWeight.w600)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _Tokens.amber,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () async {
                  final salesDate = DateFormat("dd-MM-yyyy").tryParse(dateCtrl.text.trim());
                  // A new Sales Date can't move it into the closed books either.
                  if (salesDate != null && !await ensureOpenPeriod(context, salesDate)) return;
                  final changes = <String, dynamic>{
                    "customer": customerCtrl.text.trim(),
                    "area": areaCtrl.text.trim(),
                    "salesDate": dateCtrl.text.trim(),
                    if (salesDate != null) "salesDateTs": Timestamp.fromDate(salesDate),
                    "items": items,
                    "total": calculateTotal(),
                    "discountType": discountType,
                    "discountPercent": discountPercent,
                    "discountValue": discountValue,
                    "grandTotal": calculateGrandTotal(),
                    // sales tax again at the rate the invoice was made with (sets grandTotal too)
                    ...taxNow(),
                    "updatedAt": DateTime.now(),
                  };
                  try {
                    // moves stock by however much the quantities changed
                    await updateInvoiceWithStock(docId, changes);
                  } catch (e) {
                    _toast("Couldn't save the invoice: $e", err: true);
                    return;
                  }
                  final diff = [
                    ...fieldChanges(data, changes, const {
                      'customer': 'Shop',
                      'area': 'Area',
                      'salesDate': 'Sales date',
                      'discountPercent': 'Discount %',
                      'discountValue': 'Discount',
                      'grandTotal': 'Bill',
                    }),
                    ...itemChanges(data['items'] as List?, items),
                  ];
                  if (diff.isNotEmpty || reason.isNotEmpty) {
                    logAudit(
                      area: AuditArea.invoice,
                      action: AuditAction.edit,
                      refId: docId,
                      title: _invoiceTitle({...data, ...changes}),
                      amount: withTax(),
                      changes: diff,
                      reason: reason,
                    );
                  }
                  _refreshDoc(docId);
                  if (context.mounted) Navigator.pop(context);
                },
                child: Text("Save", style: _Tokens.body(w: FontWeight.w700, color: _Tokens.navyDark)),
              ),
            ],
          ),
        );
      },
    );
  }

  Query _buildQuery() {
    final dateFormat = DateFormat('dd-MM-yyyy');
    Query query = companyCol('invoices');
    if (selectedUserId != null && selectedUserId!.isNotEmpty) {
      query = query.where('userId', isEqualTo: selectedUserId);
    }
    if (!showAllDates && selectedDate != null) {
      final formattedDate = dateFormat.format(selectedDate!).trim();
      query = query.where('salesDate', isEqualTo: formattedDate);
    }
    return query.orderBy('createdAt', descending: true);
  }

  /// Every invoice matching the filters (not just the loaded pages) as an Excel file: one tab of
  /// invoices and one of their items.
  Future<void> _exportInvoices() async {
    double n(dynamic v) => (num.tryParse('${v ?? 0}') ?? 0).toDouble();
    try {
      final docs = (await _buildQuery().get()).docs;
      if (!mounted) return;
      if (docs.isEmpty) return _toast('No invoices to export', err: true);
      final invoices = <List<Object?>>[];
      final items = <List<Object?>>[];
      double sumTotal = 0, sumGrand = 0, sumReturned = 0;
      for (final d in docs) {
        final m = d.data() as Map<String, dynamic>;
        final lines = [for (final it in (m['items'] as List? ?? const [])) if (it is Map) it];
        final returned = lines.fold<double>(0, (s, it) => s + n(it['returnAmount']));
        final total = n(m['total']);
        final grand = n(m['grandTotal']);
        sumTotal += total;
        sumGrand += grand;
        sumReturned += returned;
        invoices.add([
          (m['invoiceNumber'] ?? '').toString(),
          (m['salesDate'] ?? '').toString(),
          (m['customer'] ?? '').toString(),
          (m['area'] ?? '').toString(),
          (m['userEmail'] ?? '').toString(),
          lines.length,
          total,
          total - grand,
          returned,
          grand,
        ]);
        for (final it in lines) {
          items.add([
            (m['invoiceNumber'] ?? '').toString(),
            (m['salesDate'] ?? '').toString(),
            (m['customer'] ?? '').toString(),
            (it['Product Name'] ?? '').toString(),
            (it['Size'] ?? '').toString(),
            n(it['TP']),
            n(it['QTY']),
            n(it['BNS'] ?? it['FOC']),
            n(it['returnQty']),
            n(it['Gross Total']),
          ]);
        }
      }
      await exportToExcel(
        context,
        fileName: exportFileName('invoices'),
        title: 'Invoices',
        subtitle: [
          if (selectedUserId != null && selectedUserId!.isNotEmpty) 'One booker',
          if (!showAllDates && selectedDate != null) 'Sales date ${DateFormat('dd-MM-yyyy').format(selectedDate!)}',
          '${docs.length} invoices',
        ].join(' · '),
        sheets: [
          ExportSheet(
            name: 'Invoices',
            headers: ['Invoice #', 'Sales date', 'Shop', 'Area', 'Booker', 'Items', 'Total (Rs)', 'Discount (Rs)', 'Returned (Rs)', 'Net (Rs)'],
            rows: invoices,
            totals: ['Total', null, null, null, null, null, sumTotal, sumTotal - sumGrand, sumReturned, sumGrand],
          ),
          ExportSheet(
            name: 'Items',
            headers: ['Invoice #', 'Sales date', 'Shop', 'Product', 'Size', 'TP', 'Qty', 'FOC', 'Returned qty', 'Gross (Rs)'],
            rows: items,
          ),
        ],
      );
    } catch (e) {
      _toast("Couldn't export: $e", err: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd-MM-yyyy');

    return Scaffold(
      backgroundColor: _Tokens.bg,
      appBar: AppBar(
        title: Text('Invoices', style: _Tokens.display(size: 17, color: AppColors.text)),
        elevation: 0,
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ReturnsScreen())),
            icon: const Icon(Icons.assignment_return_outlined, size: 18),
            label: const Text('Returns'),
          ),
          TextButton.icon(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SalesTaxScreen())),
            icon: const Icon(Icons.percent, size: 18),
            label: const Text('Sales tax'),
          ),
          ExcelButton(onPressed: _exportInvoices),
          IconButton(
            tooltip: 'Print',
            icon: const Icon(Icons.print_outlined),
            onPressed: () async {
              // Print still covers every invoice matching the filters, not just loaded pages.
              final snapshot = await _buildQuery().get();
              await _printAllReports(snapshot.docs);
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: _Tokens.border),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2)),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: Icon(Icons.date_range, color: _Tokens.navy, size: 18),
                    label: Text(
                      selectedDate == null ? "Select Sales Date" : dateFormat.format(selectedDate!),
                      style: _Tokens.body(color: _Tokens.navy, w: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: _Tokens.border),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () async {
                      final picked = await showDatePicker(context: context, initialDate: selectedDate ?? DateTime.now(), firstDate: DateTime(2023), lastDate: DateTime(2030));
                      if (picked != null) {
                        selectedDate = picked;
                        showAllDates = false;
                        _loadFirstPage();
                      }
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Switch(
                  value: showAllDates,
                  onChanged: (val) {
                    showAllDates = val;
                    _loadFirstPage();
                  },
                ),
                Text("Show All", style: _Tokens.body(size: 12, color: _Tokens.muted)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: isLoadingUsers
                ? Center(child: CircularProgressIndicator(color: _Tokens.navy))
                : DropdownButtonFormField<String>(
              value: selectedUserId,
              isExpanded: true,
              style: _Tokens.body(color: _Tokens.textDark),
              icon: Icon(Icons.keyboard_arrow_down, color: _Tokens.muted),
              decoration: _Tokens.fieldDecoration(label: "Filter by User"),
              items: [
                DropdownMenuItem<String>(value: null, child: Text("All Users", style: _Tokens.body())),
                ...userList.map((u) => DropdownMenuItem<String>(
                  value: u['uid']?.toString() ?? '',
                  child: Text("${u['username']} (${u['email']})", overflow: TextOverflow.ellipsis, style: _Tokens.body()),
                )).toList(),
              ],
              onChanged: (val) {
                selectedUserId = val == null || val.isEmpty ? null : val;
                _loadFirstPage();
              },
            ),
          ),
          const SizedBox(height: 10),
          Expanded(child: _buildInvoiceList()),
        ],
      ),
    );
  }

  // --- PAGINATED INVOICE LIST ---
  Widget _buildInvoiceList() {
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
                  ? _retryButton("Failed to load invoices", _loadFirstPage)
                  : Text('No invoices found.', style: _Tokens.body(color: _Tokens.muted)),
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
        itemBuilder: (context, index) {
          if (index == _docs.length) {
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
          return _buildInvoiceTile(_docs[index]);
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

  Widget _buildInvoiceTile(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final total = (num.tryParse(data['grandTotal']?.toString() ?? "0") ?? 0).toInt();

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
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: CircleAvatar(
          backgroundColor: _Tokens.navy,
          child: Text(
            data['invoiceNumber'] ?? '',
            style: _Tokens.body(color: Colors.white, size: 12, w: FontWeight.w700),
          ),
        ),
        title: Text(data['customer'] ?? '-', style: _Tokens.display(size: 15)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Area: ${(data['area'] ?? '').toString().isEmpty ? '-' : data['area']}\nDate: ${data['salesDate']}',
              style: _Tokens.body(color: _Tokens.muted, size: 12),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Wrap(spacing: 6, runSpacing: 4, children: [
                if (_payStatus(data, doc.id) case final line?) KhataStatusPill(line),
                if (_deliveryPill(data) case final pill?) pill,
              ]),
            ),
          ],
        ),
        isThreeLine: true,
        onTap: () => _openInvoiceDetails(doc.id, data),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Rs. $total',
              style: _Tokens.body(color: _Tokens.green, w: FontWeight.w700, size: 13),
            ),
            const SizedBox(width: 6),
            IconButton(
              icon: Icon(Icons.edit_outlined, color: _Tokens.amber, size: 20),
              onPressed: () => _openEditInvoice(doc.id, data),
            ),
          ],
        ),
      ),
    );
  }
}