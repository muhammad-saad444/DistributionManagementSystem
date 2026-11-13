import 'package:flutter/material.dart';
import 'package:an_agency/ui/app_theme.dart';
import 'account/account.dart';
import 'audit/audit.dart';
import 'invoices/company_profile.dart';
import 'invoices/invoice_pdf.dart';
import 'invoices/invoice_tax.dart';
import 'print_preview.dart';
import 'inventory/inventory_data.dart';
import 'inventory/schemes.dart';
import 'credit_limits.dart';
import 'khata.dart' show loadKhata;
import 'orders/orders_data.dart';
import 'orders/my_orders_page.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';

// ---------------------------------------------------------------------------
// Same design tokens used across auth_screen.dart, dashboard_screen.dart and
// add_customer_page.dart. Worth pulling into a shared lib/design_tokens.dart
// at some point instead of duplicating this class per file.
// ---------------------------------------------------------------------------
class _Tokens {
  static const navyDark = AppColors.navy;
  static const navySlate = AppColors.navyMid;
  static const amber = AppColors.amber;
  static const bg = AppColors.bg;
  static const surface = Color(0xFFFFFFFF);
  static const textPrimary = AppColors.text;
  static const textSecondary = AppColors.muted;
  static const border = AppColors.border;
  static const error = AppColors.red;

  static TextStyle display({double size = 18, Color? color, FontWeight w = FontWeight.w600}) =>
      GoogleFonts.inter(fontSize: size, fontWeight: w, color: color ?? textPrimary, height: 1.2);

  static TextStyle body({double size = 13, Color? color, FontWeight w = FontWeight.w400}) =>
      GoogleFonts.inter(fontSize: size, fontWeight: w, color: color ?? textPrimary);
}

class SalesPurchaseScreen extends StatefulWidget {
  @override
  _SalesPurchaseScreenState createState() => _SalesPurchaseScreenState();
}

class _SalesPurchaseScreenState extends State<SalesPurchaseScreen> {
  // Field names each row is saved under in Firestore. Keep "BNS": the invoice view, DSR and load sheet read it.
  final List<String> headers = ["Product Name", "Size", "TP", "QTY", "BNS", "Gross Total"];
  // What the booker sees for each column (same order as headers).
  final List<String> headerLabels = ["Product Name", "Size", "TP", "QTY", "FOC", "Gross Total"];
  // Rows the table starts with; bookers can add more with "Add Row".
  static const int _initialRowCount = 10;

  // Modifying invoice number tracking to be dynamic per user session
  String _invoiceNumber = "1";

  late TextEditingController _salesDateController;
  late TextEditingController _creditLimitController;

  String? selectedCustomer;
  String? selectedArea;
  /// The area saved and printed on the invoice: the chosen area, else the shop's own area.
  String get _invoiceArea {
    final a = (selectedArea ?? '').trim();
    return a.isNotEmpty ? a : (_shopArea[(selectedCustomer ?? '').trim()] ?? '');
  }

  List<String> customerList = [];
  Map<String, String> _shopArea = {}; // shop name -> its saved area, for invoices booked with no area chosen
  Map<String, String> _shopTier = {}; // shop name -> the price it pays (b2b, b2r, b2c)
  Map<String, CreditTerms> _shopCredit = {}; // shop name -> credit limit and credit days set by the office
  String get _tier => _shopTier[(selectedCustomer ?? '').trim()] ?? 'b2r';
  bool isLoadingCustomers = true;

  List<String> areaList = [];
  bool isLoadingAreas = true;

  late List<List<TextEditingController>> tableControllers;

  final TextEditingController _discountController = TextEditingController(text: "0");
  String _discountType = 'percent';

  double _total = 0.0;
  double _grandTotal = 0.0;
  double _net = 0.0; // after discount, before any sales tax added on top
  double _tax = 0.0;
  CompanyProfile _profile = const CompanyProfile();
  // The company wants orders approved by the office before they become invoices (Sales orders).
  bool _ordersNeedApproval = false;

  final ScrollController _tableHCtrl = ScrollController();
  final ScrollController _tableVCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _salesDateController = TextEditingController(text: _formatDate(DateTime.now()));
    loadCompanyProfile().then((p) {
      if (!mounted) return;
      _profile = p;
      _recalcSummary();
    });
    _creditLimitController = TextEditingController(text: "100000");

    selectedArea = null;

    tableControllers = List.generate(_initialRowCount, (_) => _newRowControllers());

    _initInvoiceAndData();
    loadProductIndex().ignore(); // so product search can show what's in stock
    _discountController.addListener(_recalcSummary);
  }

  @override
  void dispose() {
    _salesDateController.dispose();
    _creditLimitController.dispose();
    _discountController.dispose();
    _tableHCtrl.dispose();
    _tableVCtrl.dispose();
    for (var row in tableControllers) {
      for (var controller in row) {
        controller.dispose();
      }
    }
    super.dispose();
  }

  List<TextEditingController> _newRowControllers() =>
      List.generate(headers.length, (_) => TextEditingController());

  void _addRow() {
    setState(() => tableControllers.add(_newRowControllers()));
    // Bring the new row into view.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_tableVCtrl.hasClients) {
        _tableVCtrl.animateTo(
          _tableVCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String _formatDate(DateTime date) =>
      "${date.day.toString().padLeft(2, '0')}-${date.month.toString().padLeft(2, '0')}-${date.year}";

  // Combined initialization to fetch next sequence safely
  Future<void> _initInvoiceAndData() async {
    ordersNeedApproval().then((v) {
      if (mounted) setState(() => _ordersNeedApproval = v);
    }).catchError((Object e) => debugPrint('Order approval setting: $e'));
    await _fetchNextInvoiceNumber();
    await _fetchAreasForCurrentUser();
  }

  // ⭐ Fetches the last invoice for the user and increments it
  Future<void> _fetchNextInvoiceNumber() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final snap = await companyCol('invoices')
          .where('userId', isEqualTo: user.uid)
          .orderBy('createdAt', descending: true)
          .limit(1)
          .get();

      final lastInvoiceNum = snap.docs.isEmpty
          ? 0
          : int.tryParse(snap.docs.first.data()['invoiceNumber']?.toString() ?? "0") ?? 0;
      final current = int.tryParse(_invoiceNumber) ?? 1;
      if (!mounted) return;
      setState(() {
        _invoiceNumber = (lastInvoiceNum + 1 > current ? lastInvoiceNum + 1 : current).toString();
      });
    } catch (e) {
      debugPrint("Error fetching last invoice number: $e");
    }
  }

  Future<void> _fetchCustomersFromFirebase() async {
    try {
      setState(() => isLoadingCustomers = true);

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        debugPrint("User not logged in — cannot fetch customers.");
        setState(() => isLoadingCustomers = false);
        return;
      }

      // 1. Get the salesman username from the session collection
      final sessionSnap = await companyCol('sessions')
          .doc(user.uid)
          .get();

      // No name in the session: the shops saved with this login are still found below.
      final username = (sessionSnap.data()?['username'] ?? '').toString().trim();

      // 2. The booker's shops: by their name, and by their login for shops saved with it (so a
      // renamed booker still sees their shops).
      final snaps = await Future.wait([
        if (username.isNotEmpty) companyCol('customers').where('salesman', isEqualTo: username).get(),
        companyCol('customers').where('salesmanUid', isEqualTo: user.uid).get(),
      ]);
      final docs = {for (final s in snaps) for (final d in s.docs) d.id: d.data()};

      // 3. Only the chosen area's shops, plus shops saved without an area. With no area chosen
      // (none assigned yet), all of the booker's shops.
      final area = (selectedArea ?? '').trim().toLowerCase();
      final List<String> fetchedCustomerNames = docs.values
          .where((m) {
            final a = (m['area'] ?? '').toString().trim().toLowerCase();
            return area.isEmpty || a.isEmpty || a == area;
          })
          .map((m) => (m['name'] ?? '').toString().trim())
          .where((name) => name.isNotEmpty)
          .toSet()
          .toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

      setState(() {
        customerList = fetchedCustomerNames;
        _shopTier = {for (final m in docs.values) (m['name'] ?? '').toString().trim(): customerTier(m)};
        _shopCredit = {for (final m in docs.values) (m['name'] ?? '').toString().trim(): CreditTerms.fromCustomer(m)};
        _shopArea = {
          for (final m in docs.values)
            if ((m['area'] ?? '').toString().trim().isNotEmpty)
              (m['name'] ?? '').toString().trim(): (m['area'] ?? '').toString().trim(),
        };
        isLoadingCustomers = false;
        // Automatically default to the first customer if matches exist, or null
        selectedCustomer = customerList.isNotEmpty ? customerList.first : null;
      });

      debugPrint("✔ Loaded ${customerList.length} customer nodes successfully from the customers collection for salesman '$username'");
    } catch (e) {
      debugPrint("❌ Error fetching salesman customers: $e");
      setState(() => isLoadingCustomers = false);
    }
  }

  Future<void> _pickSalesDate() async {
    final now = DateTime.now();

    final picked = await showDatePicker(
      context: context,
      initialDate: _parseDate(_salesDateController.text) ?? now,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );

    if (picked != null) {
      setState(() {
        _salesDateController.text = _formatDate(picked);
      });
    }
  }

  DateTime? _parseDate(String value) {
    try {
      final parts = value.split('-');
      if (parts.length != 3) return null;
      return DateTime(
        int.parse(parts[2]),
        int.parse(parts[1]),
        int.parse(parts[0]),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _fetchAreasForCurrentUser() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        debugPrint("User not logged in — cannot fetch areas.");
        setState(() => isLoadingAreas = false);
        return;
      }

      final sessionSnap = await companyCol('sessions')
          .doc(user.uid)
          .get();

      if (!sessionSnap.exists) {
        debugPrint("No session found for user ${user.uid}");
        setState(() => isLoadingAreas = false);
        return;
      }

      final username = (sessionSnap.data()?['username'] ?? '').toString().trim();
      if (username.isEmpty) {
        debugPrint("Username not found in session document");
        setState(() => isLoadingAreas = false);
        return;
      }

      final areaSnap = await companyCol('user_areas')
          .where('username', isEqualTo: username)
          .limit(1)
          .get();

      if (areaSnap.docs.isEmpty) {
        debugPrint("No areas found for username: $username");
        setState(() => isLoadingAreas = false);
        _fetchCustomersFromFirebase(); // still show their shops
        return;
      }

      final data = areaSnap.docs.first.data();
      final fetchedAreas = List<String>.from(data['areas'] ?? []);

      setState(() {
        areaList = fetchedAreas;
        isLoadingAreas = false;
        if (areaList.isNotEmpty) selectedArea = areaList.first;
      });

      _fetchCustomersFromFirebase();
    } catch (e) {
      debugPrint("Error fetching areas: $e");
      setState(() => isLoadingAreas = false);
    }
  }

  /// Gets the form ready for the next invoice after one is saved: the product table, discount and
  /// credit limit are reset; only the sales date, area and customer stay as the booker left them.
  void _generateNewInvoice({bool keepNumber = false}) {
    setState(() {
      // Next invoice number straight away; _fetchNextInvoiceNumber() then double-checks the server.
      if (!keepNumber) _invoiceNumber = ((int.tryParse(_invoiceNumber) ?? 0) + 1).toString();
      _schemes.clear();
      _taxRates.clear();
      // Drop any rows added for the previous invoice, then clear the rest.
      while (tableControllers.length > _initialRowCount) {
        for (var controller in tableControllers.removeLast()) {
          controller.dispose();
        }
      }
      for (var row in tableControllers) {
        for (var controller in row) {
          controller.clear();
        }
      }
      // Discount belongs to the previous invoice: empty field, back to the default type.
      _discountType = 'percent';
      _discountController.text = '';
      _creditLimitController.text = "100000";
      _total = 0.0;
      _grandTotal = 0.0;
      _net = 0.0;
      _tax = 0.0;
    });
    // Dynamically retrieve the next value sequence asynchronously after a creation
    _fetchNextInvoiceNumber();
  }

  Future<String> _getUsernameFromSession() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return '';
    try {
      final snap = await companyCol('sessions')
          .doc(uid)
          .get(const GetOptions(source: Source.server));
      final data = snap.data();
      final username = (data?['username'] ?? '').toString().trim();
      if (username.isNotEmpty) return username;
      return (FirebaseAuth.instance.currentUser?.displayName ?? '').trim();
    } catch (_) {
      return (FirebaseAuth.instance.currentUser?.displayName ?? '').trim();
    }
  }

  /// The shop's credit limit and credit days (set by the office on its CRM profile): stops the
  /// booker, with the reason, when this invoice would break them.
  Future<bool> _creditOk() async {
    final shop = (selectedCustomer ?? '').trim();
    final terms = _shopCredit[shop] ?? const CreditTerms();
    if (terms.none) return true;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return true;
    String? problem;
    try {
      final book = await loadKhata(uid);
      problem = creditProblem(terms, book.shop(shop), _grandTotal.toDouble(), DateTime.now());
    } catch (e) {
      debugPrint('Credit check skipped: $e'); // no khata access: don't block the sale
      return true;
    }
    if (problem == null) return true;
    if (!mounted) return false;
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Over the credit terms', style: _Tokens.body(size: 16, w: FontWeight.w700)),
        content: Text(problem!, style: _Tokens.body()),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: Text('OK', style: _Tokens.body(w: FontWeight.w700)))],
      ),
    );
    return false;
  }

  /// Saves the invoice; returns false (and keeps the form) if it couldn't be saved.
  Future<bool> _storeInvoiceInDatabase() async {
    final rows = <Map<String, String>>[];
    final bnsIndex = headers.indexOf('BNS');

    for (var rowControllers in tableControllers) {
      final rowData = <String, String>{};
      bool anyNonBnsFilled = false;

      for (int i = 0; i < headers.length; i++) {
        final raw = rowControllers[i].text.trim();

        if (i != bnsIndex && raw.isNotEmpty) anyNonBnsFilled = true;

        if (i == bnsIndex) {
          // Bonus may be fractional (e.g. 0.5 of a carton); keep it exact, drop a trailing ".0".
          final cleanVal = double.tryParse(raw) ?? 0.0;
          rowData[headers[i]] = cleanVal == cleanVal.roundToDouble()
              ? cleanVal.toInt().toString()
              : cleanVal.toString();
        } else {
          if (raw.isNotEmpty) rowData[headers[i]] = raw;
        }
      }

      if (!anyNonBnsFilled) continue;
      if (_taxRates[rowControllers[0]] case final r?) rowData['GST'] = r; // the product's own tax rate
      rows.add(rowData);
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      debugPrint("User not logged in. Invoice will not be saved.");
      _showSnack("Please log in to save invoice", error: true);
      return false;
    }
    if (!await ensureOpenPeriod(context, _salesDateToTimestamp(_salesDateController.text).toDate())) return false;

    final invoiceData = {
      'invoiceNumber': _invoiceNumber,
      'salesDate': _salesDateController.text,
      'salesDateTs': _salesDateToTimestamp(_salesDateController.text),
      'customer': selectedCustomer,
      'area': _invoiceArea,
      'priceTier': _tier,
      'items': rows,
      'discountPercent': _discountController.text.trim().isEmpty ? '0' : _discountController.text.trim(),
      'discountType': _discountType,
      'discountValue': _discountController.text.trim().isEmpty ? '0' : _discountController.text.trim(),
      'total': _total,
      'grandTotal': _grandTotal,
      // sales tax at today's settings, kept on the invoice (sets grandTotal the same way)
      ..._profile.taxFieldsFor(rows, _net),
      'createdAt': DateTime.now(),
      'userId': user.uid,
      'userEmail': user.email ?? "",
    };

    // Stock comes out of the warehouse this booker is assigned to (Main if none).
    try {
      invoiceData['warehouseId'] = await myWarehouseId();
    } catch (_) {
      invoiceData['warehouseId'] = mainWarehouseId;
    }
    if (!await _confirmStock(rows, invoiceData['warehouseId'] as String)) return false;
    if (!await _creditOk()) return false;

    if (_ordersNeedApproval) {
      // The office approves it first; the invoice (and the stock move) is made then.
      try {
        final number = await placeSalesOrder(invoiceData, bookerName: await _getUsernameFromSession());
        _showSnack("Order $number sent for approval");
        return true;
      } catch (e) {
        debugPrint("Sending order failed: $e");
        _showSnack("Couldn't send the order. Check your connection.", error: true);
        return false;
      }
    }

    final ref = companyCol('invoices').doc();
    try {
      // Save the invoice and take its QTY + FOC out of stock together.
      final batch = FirebaseFirestore.instance.batch();
      final stock = await addInvoiceStockMoves(
        batch,
        afterItems: rows,
        deleting: false,
        invoiceId: ref.id,
        invoiceNo: _invoiceNumber,
        shop: selectedCustomer ?? '',
        warehouseId: invoiceData['warehouseId'] as String,
      );
      batch.set(ref, {...invoiceData, ...?stock?.fields});
      await batch.commit();
      _showSnack("Invoice saved successfully");
      return true;
    } catch (e) {
      debugPrint("Saving invoice with stock failed, saving it alone: $e");
    }
    try {
      // Stock couldn't be updated (e.g. offline product list): save the invoice anyway; the
      // admin's Stock screen takes its stock out later.
      await ref.set(invoiceData);
      _showSnack("Invoice saved successfully");
      return true;
    } catch (e) {
      debugPrint("Error saving invoice: $e");
      _showSnack("Error saving invoice", error: true);
      return false;
    }
  }

  /// Warns when a line asks for more than is in stock. Returns false if the booker cancels.
  Future<bool> _confirmStock(List<Map<String, String>> rows, String warehouseId) async {
    final ProductIndex products;
    try {
      if (await stockStartedAt() == null) return true;
      products = await loadProductIndex(fresh: true);
    } catch (_) {
      return true; // can't check right now; don't block the order
    }
    final need = <String, num>{};
    for (final r in rows) {
      final p = products.byName(r['Product Name'] ?? '');
      if (p == null) continue;
      need[p.name] = (need[p.name] ?? 0) + (num.tryParse(r['QTY'] ?? '') ?? 0) + (num.tryParse(r['BNS'] ?? '') ?? 0);
    }
    final short = [
      for (final e in need.entries)
        if (e.value > (products.byName(e.key)?.inWarehouse(warehouseId) ?? 0))
          '${e.key}: ordered ${e.value}, in your warehouse ${products.byName(e.key)?.inWarehouse(warehouseId) ?? 0}',
    ];
    if (short.isEmpty || !mounted) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Not enough stock", style: _Tokens.display(size: 17)),
        content: Text("${short.join('\n')}\n\nSave the invoice anyway?", style: _Tokens.body()),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text("Go back", style: _Tokens.body())),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _Tokens.amber, elevation: 0),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text("Save anyway", style: _Tokens.body(w: FontWeight.w700, color: _Tokens.navyDark)),
          ),
        ],
      ),
    );
    return ok == true;
  }

  void _showSnack(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: error ? _Tokens.error : _Tokens.navyDark,
        content: Text(message, style: _Tokens.body(color: Colors.white)),
      ),
    );
  }

  Future<void> _previewInvoice() async {
    final username = await _getUsernameFromSession();
    final disc = _toDouble(_discountController.text.trim());
    final items = [
      for (final row in tableControllers)
        if (row[0].text.trim().isNotEmpty)
          {
            'Product Name': row[0].text.trim(),
            'Size': row[1].text.trim(),
            'TP': row[2].text.trim(),
            'QTY': row[3].text.trim(),
            'BNS': row[4].text.trim(),
            if (_taxRates[row[0]] case final r?) 'GST': r,
          },
    ];
    final invoice = <String, dynamic>{
      'invoiceNumber': _invoiceNumber,
      'salesDate': _salesDateController.text,
      'customer': selectedCustomer,
      'area': _invoiceArea,
      'items': items,
      'discountType': _discountType,
      'discountPercent': disc,
      'discountValue': disc,
      'total': _total,
      'grandTotal': _grandTotal,
      ..._profile.taxFieldsFor(items, _net),
    };
    final buyer = await loadBuyer(selectedCustomer ?? '');
    if (!mounted) return;
    await showPrintPreview(
      context,
      title: 'Invoice #$_invoiceNumber',
      buildPdf: () {
        final pdf = pw.Document();
        pdf.addPage(invoicePdfPage(invoice, profile: _profile, buyer: buyer, booker: username, area: _invoiceArea));
        return pdf.save();
      },
      fileName: 'Invoice_$_invoiceNumber.pdf',
    );
  }

  Future<List<String>> _searchProductNames(String query) async {
    final q = query.trim();
    if (q.isEmpty) return [];
    try {
      final lowerSnap = await companyCol('products')
          .orderBy('productName_lower')
          .startAt([q.toLowerCase()])
          .endAt([q.toLowerCase() + '\uf8ff'])
          .limit(20)
          .get();
      if (lowerSnap.docs.isNotEmpty) {
        return lowerSnap.docs.where((d) => d.data()['active'] != false).map((d) => (d.data()['productName'] as String)).toList();
      }
    } catch (_) {}
    final snap = await companyCol('products')
        .orderBy('productName')
        .startAt([q])
        .endAt([q + '\uf8ff'])
        .limit(20)
        .get();
    return snap.docs.where((d) => d.data()['active'] != false).map((d) => (d.data()['productName'] as String)).toList();
  }

  Future<Map<String, dynamic>?> _getProductByExactName(String name) async {
    try {
      final lower = await companyCol('products')
          .where('productName_lower', isEqualTo: name.toLowerCase())
          .limit(1)
          .get();
      if (lower.docs.isNotEmpty) return lower.docs.first.data();

      final snap = await companyCol('products')
          .where('productName', isEqualTo: name)
          .limit(1)
          .get();
      if (snap.docs.isNotEmpty) return snap.docs.first.data();
    } catch (e) {
      debugPrint('getProductByExactName error: $e');
    }
    return null;
  }

  double _toDouble(String s) {
    if (s.isEmpty) return 0.0;
    return double.tryParse(s) ?? 0.0;
  }

  String _formatMoney(double v) => v.toStringAsFixed(2);

  /// A different shop can pay a different price (B2B, B2R, B2C): re-price the lines already entered.
  /// Its kind of shop can also change which trade schemes apply.
  Future<void> _repriceRows() async {
    for (var i = 0; i < tableControllers.length; i++) {
      final name = tableControllers[i][0].text.trim();
      if (name.isEmpty) continue;
      final doc = await _getProductByExactName(name);
      final p = tierPrice(doc, _tier);
      if (p <= 0 || !mounted) continue;
      tableControllers[i][2].text = p.toDouble().toStringAsFixed(2);
      _setScheme(i, doc);
      _recalcRow(i);
    }
  }

  // ---------------------------------------------------------------------------
  // Trade schemes (inventory/schemes.dart): free goods filled from the quantity
  // ---------------------------------------------------------------------------

  /// The scheme each line gets, by the line's product box (rows can be added and removed).
  final Map<TextEditingController, TradeScheme> _schemes = {};

  TradeScheme? _schemeOf(int row) => _schemes[tableControllers[row][0]];

  /// Each line's own sales tax rate, when its product isn't at the company rate.
  final Map<TextEditingController, String> _taxRates = {};

  /// The lines as the invoice keeps them, for working out tax.
  List<Map<String, String>> _taxLines() => [
        for (final row in tableControllers)
          if (row[0].text.trim().isNotEmpty)
            {'QTY': row[3].text.trim(), 'TP': row[2].text.trim(), if (_taxRates[row[0]] case final r?) 'GST': r},
      ];

  /// Picks up the product's scheme for this line, if it runs on the sales date for this kind of shop.
  void _setScheme(int row, Map<String, dynamic>? product) {
    // and its own sales tax rate (exempt, or a special rate), if it has one
    final rate = product == null ? null : productTaxRate(product);
    if (rate == null) {
      _taxRates.remove(tableControllers[row][0]);
    } else {
      _taxRates[tableControllers[row][0]] = rate;
    }
    final s = TradeScheme.of(product);
    final day = _parseDate(_salesDateController.text) ?? DateTime.now();
    final key = tableControllers[row][0];
    if (s != null && s.appliesTo(_tier, day)) {
      _schemes[key] = s;
      _fillFree(row);
    } else if (_schemes.remove(key) != null) {
      tableControllers[row][4].clear(); // the scheme no longer applies: the booker types FOC again
    }
    if (mounted) setState(() {});
  }

  /// FOC = what the scheme gives for the quantity.
  void _fillFree(int row) {
    final s = _schemeOf(row);
    if (s == null) return;
    final qty = double.tryParse(tableControllers[row][3].text.trim()) ?? 0;
    final free = s.freeFor(qty);
    tableControllers[row][4].text = free > 0 ? '$free' : '';
  }

  /// A booker may give fewer free goods than the scheme, never more.
  void _capFree(int row) {
    final s = _schemeOf(row);
    if (s == null) return;
    final qty = double.tryParse(tableControllers[row][3].text.trim()) ?? 0;
    final allowed = s.freeFor(qty);
    final typed = double.tryParse(tableControllers[row][4].text.trim()) ?? 0;
    if (typed > allowed) {
      tableControllers[row][4].text = allowed > 0 ? '$allowed' : '';
      tableControllers[row][4].selection = TextSelection.collapsed(offset: tableControllers[row][4].text.length);
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Scheme ${s.label}: ${qty.toStringAsFixed(0)} sold allows $allowed free.'),
      ));
    }
  }

  void _recalcRow(int rowIndex) {
    final tp = double.tryParse(tableControllers[rowIndex][2].text.trim()) ?? 0.0;
    final qty = double.tryParse(tableControllers[rowIndex][3].text.trim()) ?? 0.0;

    double gross = tp * qty;

    tableControllers[rowIndex][5].text = gross == 0 ? '' : gross.toStringAsFixed(2);

    _recalcSummary();
  }

  void _recalcSummary() {
    double sum = 0.0;
    for (var i = 0; i < tableControllers.length; i++) {
      final val = tableControllers[i][5].text.trim();
      sum += double.tryParse(val) ?? 0.0;
    }

    _total = sum;

    double disc = double.tryParse(_discountController.text.trim()) ?? 0.0;
    double calculatedGrandTotal = 0.0;

    if (_discountType == 'percent') {
      calculatedGrandTotal = _total - (_total * (disc / 100.0));
    } else {
      calculatedGrandTotal = _total - disc;
    }

    _net = calculatedGrandTotal;
    if (_profile.taxEnabled) {
      final t = computeTax(_taxLines(), _net, rate: _profile.taxRate, inclusive: _profile.taxInclusive);
      _tax = t.tax;
      _grandTotal = t.grandTotal;
    } else {
      _tax = 0;
      _grandTotal = _net;
    }
    setState(() {});
  }

  static const double _baseWidth = 430.0;
  static const double _baseHeight = 900.0;

  double _scaleW(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    return (w / _baseWidth).clamp(0.75, 1.2);
  }

  double _scaleH(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    return (h / _baseHeight).clamp(0.75, 1.2);
  }

  Timestamp _salesDateToTimestamp(String ddMMyyyy) {
    final parts = ddMMyyyy.split('-');
    final d = int.parse(parts[0]);
    final m = int.parse(parts[1]);
    final y = int.parse(parts[2]);
    return Timestamp.fromDate(DateTime(y, m, d));
  }

  InputDecoration _fieldDecoration({String? hint, Widget? suffixIcon}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: _Tokens.body(color: _Tokens.textSecondary),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: _Tokens.bg,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _Tokens.border),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _Tokens.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _Tokens.amber, width: 1.5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.of(context).size;
    final sw = _scaleW(context);
    final sh = _scaleH(context);

    final cellWidth = 150.0 * sw;
    final cellHeight = 50.0 * sh;
    final cellPad = EdgeInsets.all(4.0 * sw);
    final labelFont = 12.0 * sw;
    final summaryFont = 16.0 * sw;

    return Scaffold(
      backgroundColor: _Tokens.bg,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: Text(
          'Book Order',
          style: _Tokens.display(size: 18, color: AppColors.text),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.only(
            top: 20.0 * sh,
            left: 12.0 * sw,
            right: 12.0 * sw,
            bottom: 16.0 * sh,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ---------------- Invoice header card ----------------
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(16 * sw),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _Tokens.border),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2)),
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _buildDropdownField(
                            _ordersNeedApproval ? "Order" : "Invoice#",
                            TextFormField(
                              key: ValueKey('$_invoiceNumber$_ordersNeedApproval'),
                              // An order gets its number when sent; the invoice number comes on approval.
                              initialValue: _ordersNeedApproval ? 'Needs approval' : _invoiceNumber,
                              enabled: false,
                              style: _Tokens.body(color: _Tokens.textSecondary),
                              decoration: _fieldDecoration().copyWith(
                                fillColor: _Tokens.border.withOpacity(0.5),
                                prefixIcon: Icon(Icons.tag, color: _Tokens.textSecondary, size: 18),
                              ),
                            ),
                            labelFont,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildDropdownField(
                            "Sales Date",
                            TextFormField(
                              controller: _salesDateController,
                              readOnly: true,
                              onTap: _pickSalesDate,
                              style: _Tokens.body(),
                              decoration: _fieldDecoration(
                                suffixIcon: Icon(Icons.calendar_today_outlined, color: _Tokens.textSecondary, size: 18),
                              ),
                            ),
                            labelFont,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildDropdownField(
                      "Select Area",
                      SizedBox(
                        width: double.infinity,
                        child: isLoadingAreas
                            ? Center(child: CircularProgressIndicator(color: _Tokens.amber))
                            : (areaList.isEmpty
                            ? Text("No areas assigned", style: _Tokens.body(color: _Tokens.error))
                            : _dropdown(areaList, selectedArea, (val) {
                          setState(() {
                            selectedArea = val;
                            _fetchCustomersFromFirebase();
                          });
                        })),
                      ),
                      labelFont,
                    ),
                    const SizedBox(height: 16),
                    _buildDropdownField(
                      "Select Customer",
                      SizedBox(
                        width: double.infinity,
                        child: isLoadingCustomers
                            ? Center(child: CircularProgressIndicator(color: _Tokens.amber))
                            : (customerList.isEmpty
                            ? Text("No customers found", style: _Tokens.body(color: _Tokens.error))
                            : _dropdown(customerList, selectedCustomer,
                                (val) {
                                  setState(() => selectedCustomer = val);
                                  _repriceRows();
                                })),
                      ),
                      labelFont,
                    ),
                    if (selectedCustomer != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6, left: 2),
                        child: Text('Pays: ${tierLabel(_tier)} price',
                            style: _Tokens.body(size: 12, color: _Tokens.textSecondary)),
                      ),
                  ],
                ),
              ),
              SizedBox(height: 16 * sh),
              if (_ordersNeedApproval)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MySalesOrdersPage())),
                    icon: const Icon(Icons.assignment_outlined, color: _Tokens.navyDark, size: 18),
                    label: Text('My sales orders', style: _Tokens.body(color: _Tokens.navyDark, w: FontWeight.w600)),
                  ),
                ),
              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    final asOrder = _ordersNeedApproval;
                    if (!await _storeInvoiceInDatabase()) return; // not saved: keep the form as it is
                    if (asOrder) {
                      _generateNewInvoice(keepNumber: true); // no invoice was made, so no number used
                      return;
                    }
                    await _previewInvoice(); // check it, then print from the preview
                    _generateNewInvoice();
                  },
                  icon: const Icon(Icons.receipt_long_outlined, color: _Tokens.navyDark, size: 18),
                  label: Text(_ordersNeedApproval ? "Send order for approval" : "Generate Invoice", style: _Tokens.body(w: FontWeight.w600, color: _Tokens.navyDark, size: 14 * sw)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _Tokens.amber,
                    elevation: 0,
                    padding: EdgeInsets.symmetric(vertical: 14 * sh, horizontal: 20 * sw),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              SizedBox(height: 16 * sh),
              // ---------------- Items table ----------------
              Container(
                padding: EdgeInsets.all(4 * sw),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _Tokens.border),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2)),
                  ],
                ),
                child: SizedBox(
                  height: (screen.height * 0.45).clamp(260.0, 520.0),
                  child: Scrollbar(
                    controller: _tableHCtrl,
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      controller: _tableHCtrl,
                      scrollDirection: Axis.horizontal,
                      primary: false,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minWidth: screen.width),
                        child: Scrollbar(
                          controller: _tableVCtrl,
                          thumbVisibility: true,
                          child: SingleChildScrollView(
                            controller: _tableVCtrl,
                            scrollDirection: Axis.vertical,
                            primary: false,
                            child: Container(
                              decoration: BoxDecoration(
                                border: Border.all(color: _Tokens.border),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: Column(
                                children: [
                                  Row(
                                    children: headerLabels
                                        .map((t) => _tableCell(
                                      t,
                                      isHeader: true,
                                      width: cellWidth,
                                      height: cellHeight,
                                      pad: cellPad,
                                      fontSize: 13 * sw,
                                    ))
                                        .toList(),
                                  ),
                                  ...List.generate(tableControllers.length, (rowIndex) {
                                    return Row(
                                      children: List.generate(headers.length, (colIndex) {
                                        return _tableCell(
                                          "",
                                          rowIndex: rowIndex,
                                          controller: tableControllers[rowIndex][colIndex],
                                          colIndex: colIndex,
                                          width: cellWidth,
                                          height: cellHeight,
                                          pad: cellPad,
                                          fontSize: 14 * sw,
                                        );
                                      }),
                                    );
                                  }),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(height: 10 * sh),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: _addRow,
                  icon: const Icon(Icons.add, color: _Tokens.navyDark, size: 18),
                  label: Text("Add Row", style: _Tokens.body(w: FontWeight.w600, color: _Tokens.navyDark, size: 14 * sw)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: _Tokens.border),
                    backgroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(vertical: 12 * sh, horizontal: 16 * sw),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              SizedBox(height: 16 * sh),
              // ---------------- Summary card ----------------
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(16 * sw),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _Tokens.border),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2)),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Wrap(
                      alignment: WrapAlignment.end,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 12 * sw,
                      runSpacing: 8 * sh,
                      children: [
                        Text("Total", style: _Tokens.body(color: _Tokens.textSecondary, size: summaryFont, w: FontWeight.w500)),
                        Text(_formatMoney(_total), style: _Tokens.display(size: summaryFont)),
                        SizedBox(width: 24 * sw),
                        Text("Discount", style: _Tokens.body(color: _Tokens.textSecondary, size: summaryFont, w: FontWeight.w500)),
                        SizedBox(
                          width: 130 * sw,
                          child: DropdownButtonFormField<String>(
                            value: _discountType,
                            isExpanded: true,
                            style: _Tokens.body(color: _Tokens.textPrimary),
                            icon: Icon(Icons.keyboard_arrow_down, color: _Tokens.textSecondary, size: 18),
                            decoration: _fieldDecoration(),
                            items: const [
                              DropdownMenuItem(value: 'percent', child: Text('percent')),
                              DropdownMenuItem(value: 'pkr', child: Text('pkr')),
                            ],
                            onChanged: (v) {
                              if (v == null) return;
                              setState(() => _discountType = v);
                              _recalcSummary();
                            },
                          ),
                        ),
                        SizedBox(
                          width: 110 * sw,
                          child: TextField(
                            controller: _discountController,
                            textAlign: TextAlign.right,
                            style: _Tokens.body(),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: _fieldDecoration(hint: '0'),
                            onChanged: (_) => _recalcSummary(),
                          ),
                        ),
                      ],
                    ),
                    if (_profile.taxEnabled) ...[
                      SizedBox(height: 10 * sh),
                      Text(
                        'Sales tax ${_profile.taxRate.toStringAsFixed(_profile.taxRate % 1 == 0 ? 0 : 1)}%'
                        '${_profile.taxInclusive ? ' (included)' : ''}:  ${_formatMoney(_tax)}',
                        style: _Tokens.body(color: _Tokens.textSecondary),
                      ),
                    ],
                    SizedBox(height: 14 * sh),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 16 * sw, vertical: 10 * sh),
                      decoration: BoxDecoration(
                        color: _Tokens.navyDark,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text("GRAND TOTAL", style: _Tokens.body(size: summaryFont - 2, color: Colors.white70, w: FontWeight.w500)),
                          SizedBox(width: 12 * sw),
                          Text(
                            _formatMoney(_grandTotal),
                            style: _Tokens.display(size: summaryFont + 2, color: _Tokens.amber),
                          ),
                        ],
                      ),
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

  Widget _buildDropdownField(String label, Widget child, double labelFont) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: _Tokens.body(size: labelFont + 1, w: FontWeight.w600, color: _Tokens.textPrimary)),
        const SizedBox(height: 6),
        child,
      ],
    );
  }

  Widget _dropdown(
      List<String> items,
      String? selectedValue,
      Function(String?) onChanged,
      ) {
    final safeValue = items.contains(selectedValue) ? selectedValue : null;
    final uniqueItems = items.toSet().toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        return ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: constraints.maxWidth,
            maxWidth: constraints.maxWidth,
          ),
          child: DropdownButtonFormField<String>(
            isExpanded: true,
            value: safeValue,
            style: _Tokens.body(color: _Tokens.textPrimary),
            icon: Icon(Icons.keyboard_arrow_down, color: _Tokens.textSecondary),
            decoration: _fieldDecoration(),
            items: uniqueItems
                .map((item) => DropdownMenuItem(
              value: item,
              child: Text(
                item,
                overflow: TextOverflow.ellipsis,
              ),
            ))
                .toList(),
            onChanged: onChanged,
          ),
        );
      },
    );
  }

  Widget _tableCell(
      String value, {
        bool isHeader = false,
        TextEditingController? controller,
        int? colIndex,
        int? rowIndex,
        required double width,
        required double height,
        required EdgeInsets pad,
        required double fontSize,
      }) {
    final isAlternateRow = rowIndex != null && rowIndex % 2 == 1;
    return Container(
      width: width,
      height: height,
      padding: pad,
      decoration: BoxDecoration(
        border: Border.all(color: _Tokens.border),
        color: isHeader ? _Tokens.navyDark : (isAlternateRow ? _Tokens.bg : Colors.white),
      ),
      child: isHeader
          ? Align(
        alignment: Alignment.centerLeft,
        child: Text(
          value,
          style: _Tokens.body(w: FontWeight.w700, color: Colors.white, size: fontSize),
        ),
      )
          : (colIndex == 0
          ? TypeAheadField<String>(
        debounceDuration: const Duration(milliseconds: 200),
        suggestionsCallback: (pattern) => _searchProductNames(pattern),
        builder: (context, taController, focusNode) {
          if (controller != null && taController.text != controller.text) {
            taController.text = controller.text;
            taController.selection = TextSelection.fromPosition(
              TextPosition(offset: taController.text.length),
            );
          }
          return TextField(
            controller: taController,
            focusNode: focusNode,
            onChanged: (v) => controller?.text = v,
            style: _Tokens.body(size: fontSize),
            decoration: const InputDecoration(
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            ),
          );
        },
        itemBuilder: (context, name) {
          // What's in this booker's own warehouse (Main if they have none).
          final product = cachedProductIndex?.byName(name);
          final stock = product?.stock == null ? null : product!.inWarehouse(Account.user?.warehouseId ?? mainWarehouseId);
          return ListTile(
            title: Text(name, style: _Tokens.body(size: fontSize)),
            subtitle: stock == null
                ? null
                : Text('In stock: $stock',
                    style: _Tokens.body(size: fontSize * 0.85, color: stock > 0 ? _Tokens.textSecondary : _Tokens.error)),
          );
        },
        onSelected: (name) async {
          if (rowIndex == null) return;
          tableControllers[rowIndex][0].text = name;

          final doc = await _getProductByExactName(name);
          final boxSize = (doc?['productSize'] ?? '').toString();

          // ⭐ FIX: Explicitly parse as a double first to safeguard decimal values, then format to 2 decimal places
          double tpValue = tierPrice(doc, _tier).toDouble(); // the shop's price: B2B, B2R (TP) or B2C
          if (tpValue <= 0) {
            // No selling price yet (e.g. a new product before its first purchase): don't sell at Rs 0.
            tableControllers[rowIndex][0].clear();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('$name has no price yet. Ask the office to set its TP.'),
                backgroundColor: _Tokens.error,
              ));
            }
            return;
          }
          final tpPrice = tpValue.toStringAsFixed(2);

          tableControllers[rowIndex][1].text = boxSize;
          tableControllers[rowIndex][2].text = tpPrice; // Displays exactly as "13.75"
          _setScheme(rowIndex, doc);
          _recalcRow(rowIndex);
        },
        emptyBuilder: (context) => Padding(
          padding: const EdgeInsets.all(8.0),
          child: Text('No products found', style: _Tokens.body(color: _Tokens.textSecondary)),
        ),
        loadingBuilder: (context) => Padding(
          padding: const EdgeInsets.all(8.0),
          child: CircularProgressIndicator(color: _Tokens.amber),
        ),
      )
          : TextFormField(
        controller: controller,
        style: _Tokens.body(size: fontSize),
        readOnly: (colIndex == 1 || colIndex == 2),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onChanged: (v) {
          if (rowIndex == null) return;
          if (colIndex == 3) _fillFree(rowIndex!); // quantity sets the scheme's free goods
          if (colIndex == 4) _capFree(rowIndex!);
          if (colIndex == 2 || colIndex == 3) {
            _recalcRow(rowIndex!);
          }
        },
        decoration: InputDecoration(
          border: InputBorder.none,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          // The FOC box names the scheme it follows.
          suffixText: colIndex == 4 && rowIndex != null ? _schemeOf(rowIndex!)?.label : null,
          suffixStyle: _Tokens.body(size: fontSize * 0.8, color: AppColors.green, w: FontWeight.w700),
        ),
      )),
    );
  }
}