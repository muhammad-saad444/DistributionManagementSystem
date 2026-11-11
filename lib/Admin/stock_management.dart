import 'package:an_agency/Admin/products_transaction_screen.dart';
import 'package:an_agency/ui/app_theme.dart';
import '../account/account.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../inventory/inventory_data.dart';
import '../inventory/stock_screens.dart';

// Same tokens used in admin_dashboard_screen.dart and the rest of the Admin
// section. Delete this block and import your shared _Tokens file if you
// already have one.
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

  static TextStyle display({double size = 18, Color? color, FontWeight w = FontWeight.w700}) =>
      GoogleFonts.inter(fontSize: size, fontWeight: w, color: color ?? textDark);

  static TextStyle body({double size = 13, Color? color, FontWeight w = FontWeight.w400}) =>
      GoogleFonts.inter(fontSize: size, fontWeight: w, color: color ?? textDark);
}

class StockAndSalesScreen extends StatefulWidget {
  const StockAndSalesScreen({Key? key}) : super(key: key);

  @override
  State<StockAndSalesScreen> createState() => _StockAndSalesScreenState();
}

class _StockAndSalesScreenState extends State<StockAndSalesScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  DateTime? _selectedDate;
  final DateFormat _dateFormat = DateFormat('yyyy-MM-dd');

  // --- PRODUCTS (paginated, shown as soon as the first page arrives) ---
  static const int _pageSize = 20;
  final ScrollController _scrollController = ScrollController();
  final List<Map<String, dynamic>> _products = [];
  DocumentSnapshot? _lastProductDoc;
  bool _isLoadingFirst = true;
  bool _isLoadingMore = false;
  bool _isSyncingFirstPage = false; // cached first page is showing, server copy still on its way
  bool _hasMore = true;
  Object? _productsError;
  int _productsGen = 0; // bumps on every reload so stale responses are ignored

  // --- SALES (sold qty needs every load sheet, so it's computed in the background) ---
  Map<String, num>? _totalSoldByProduct; // null until load sheets have been read once
  List<Map<String, dynamic>> _userSalesData = [];
  bool _isSyncingSales = false;
  bool _salesError = false;
  int _salesGen = 0;

  // --- STOCK TRACKING (purchases in, invoices out; see inventory_data.dart) ---
  bool _trackingKnown = false;
  bool _tracking = false;
  List<Warehouse> _warehouses = const [];

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _refreshAll();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _refreshAll() async {
    await _checkTracking();
    await Future.wait([_loadFirstPage(), _loadSales()]);
  }

  Future<void> _checkTracking() async {
    try {
      final started = await ensureStockTracking(); // starts by itself for a company that hasn't sold yet
      final warehouses = await loadWarehouses(fresh: true);
      if (mounted) {
        setState(() {
          _tracking = started != null;
          _warehouses = warehouses;
          _trackingKnown = true;
        });
      }
      if (started == null) return;
      // Invoices booked on an older app version (or saved without stock) are taken out now.
      final fixed = await applyUntrackedInvoices();
      if (fixed > 0 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: _Tokens.navyDark,
          content: Text("Took stock out for $fixed invoice(s) that hadn't updated it", style: _Tokens.body(color: Colors.white)),
        ));
        _loadFirstPage();
      }
    } catch (e) {
      debugPrint("Stock tracking check failed: $e");
    }
  }

  Future<void> _openSetup() async {
    final done = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const StockSetupScreen()));
    if (done == true) _refreshAll();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 300) _loadMore();
  }

  void _showOfflineSnack() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: _Tokens.error,
        content: Text("Showing saved data — couldn't reach server", style: _Tokens.body(color: Colors.white)),
      ),
    );
  }

  // --- PAGINATED PRODUCTS FETCH ---
  Query<Map<String, dynamic>> _productsQuery() =>
      companyCol('products').orderBy(FieldPath.documentId);

  Future<void> _loadFirstPage() async {
    final gen = ++_productsGen;
    setState(() {
      _lastProductDoc = null;
      _hasMore = true;
      // Keep the current list on screen during a refresh; only spin when there's nothing yet.
      _isLoadingFirst = _products.isEmpty;
      _isLoadingMore = false;
      _isSyncingFirstPage = false;
      _productsError = null;
    });
    await _fetchProductsPage(gen);
  }

  Future<void> _loadMore() async {
    if (_isLoadingFirst || _isLoadingMore || _isSyncingFirstPage || !_hasMore || _productsError != null) return;
    setState(() => _isLoadingMore = true);
    await _fetchProductsPage(_productsGen);
  }

  Future<void> _fetchProductsPage(int gen) async {
    final isFirstPage = _lastProductDoc == null;
    Query<Map<String, dynamic>> q = _productsQuery().limit(_pageSize);
    if (!isFirstPage) q = q.startAfterDocument(_lastProductDoc!);

    // First page: paint whatever Firestore already has on the device instantly,
    // then replace it with the server result once that arrives.
    var shownFromCache = false;
    if (isFirstPage) {
      try {
        final cached = await q.get(const GetOptions(source: Source.cache));
        if (!mounted || gen != _productsGen) return;
        if (cached.docs.isNotEmpty) {
          shownFromCache = true;
          setState(() {
            _products
              ..clear()
              ..addAll(cached.docs.map(_productFromDoc));
            _lastProductDoc = cached.docs.last;
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
      if (!mounted || gen != _productsGen) return;
      setState(() {
        if (isFirstPage) _products.clear();
        _products.addAll(snap.docs.map(_productFromDoc));
        _lastProductDoc = snap.docs.isNotEmpty ? snap.docs.last : (isFirstPage ? null : _lastProductDoc);
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
      debugPrint("Error loading products: $e");
      if (!mounted || gen != _productsGen) return;
      setState(() {
        _isLoadingFirst = false;
        _isLoadingMore = false;
        _isSyncingFirstPage = false;
        // Offline but cached rows are already on screen: keep them rather than showing an error.
        if (!shownFromCache) _productsError = e;
      });
      if (shownFromCache) _showOfflineSnack();
    }
  }

  Map<String, dynamic> _productFromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    data['id'] = doc.id;
    return data;
  }

  // --- SALES AGGREGATION (background) ---
  Future<void> _loadSales() async {
    final gen = ++_salesGen;
    setState(() {
      _isSyncingSales = true;
      _salesError = false;
    });

    final sheets = companyCol('load_sheets');
    var shownFromCache = false;
    try {
      final cached = await sheets.get(const GetOptions(source: Source.cache));
      if (!mounted || gen != _salesGen) return;
      if (cached.docs.isNotEmpty) {
        shownFromCache = true;
        _applyLoadSheets(cached);
      }
    } catch (_) {
      // Nothing cached — fall through to the server.
    }

    try {
      final fresh = await sheets.get(const GetOptions(source: Source.server));
      if (!mounted || gen != _salesGen) return;
      _applyLoadSheets(fresh);
    } catch (e) {
      debugPrint("Error loading load sheets: $e");
      if (!mounted || gen != _salesGen) return;
      if (shownFromCache) {
        _showOfflineSnack();
      } else if (_totalSoldByProduct == null) {
        setState(() => _salesError = true);
      }
    } finally {
      if (mounted && gen == _salesGen) setState(() => _isSyncingSales = false);
    }
  }

  void _applyLoadSheets(QuerySnapshot<Map<String, dynamic>> loadSheetsSnap) {
    try {
      final loadSheets = loadSheetsSnap.docs.map((d) => d.data()).toList();

      Map<String, num> totalSoldByProduct = {};
      Map<String, Map<String, dynamic>> userSalesMap = {};

      for (var sheet in loadSheets) {
        final userEmail = sheet['userEmail'] ?? 'Unknown User';
        final dateStr = sheet['dateStr'] ?? '';
        if (sheet['items'] != null) {
          for (var item in sheet['items']) {
            final productName = item['productName'] ?? '';
            final qty = (item['qty'] ?? 0).toInt();
            final amount = (item['amount'] ?? 0).toDouble();

            totalSoldByProduct[productName] =
                (totalSoldByProduct[productName] ?? 0) + qty;

            if (!userSalesMap.containsKey(userEmail)) {
              userSalesMap[userEmail] = {
                'username': userEmail,
                'salesQty': 0,
                'totalSalesAmount': 0.0,
                'productsSold': <String, int>{},
                'dateStr': dateStr
              };
            }

            userSalesMap[userEmail]!['salesQty'] += qty;
            userSalesMap[userEmail]!['totalSalesAmount'] += amount;
            userSalesMap[userEmail]!['productsSold'][productName] =
                (userSalesMap[userEmail]!['productsSold'][productName] ?? 0) +
                    qty;
          }
        }
      }

      setState(() {
        _totalSoldByProduct = totalSoldByProduct;
        _userSalesData = userSalesMap.values.toList();
      });
    } catch (e) {
      debugPrint("Error computing sales: $e");
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
    );

    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  List<Map<String, dynamic>> get _filteredUserSales {
    if (_selectedDate == null) return _userSalesData;
    final formattedDate = _dateFormat.format(_selectedDate!);
    return _userSalesData
        .where((sale) => sale['dateStr'] == formattedDate)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final isSyncing = _isSyncingFirstPage || _isSyncingSales;
    final showFooter = _products.isNotEmpty && (_hasMore || _productsError != null);

    return Scaffold(
      backgroundColor: _Tokens.bg,
      appBar: AppBar(
        title: Text("Stock and sales", style: _Tokens.display(size: 17, color: AppColors.text)),
        centerTitle: false,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.text),
            onPressed: _refreshAll,
          ),
        ],
        // Thin bar while data is being refreshed from the server.
        bottom: isSyncing
            ? PreferredSize(
                preferredSize: const Size.fromHeight(2),
                child: LinearProgressIndicator(minHeight: 2, color: _Tokens.amber, backgroundColor: _Tokens.navy),
              )
            : null,
      ),
      body: _isLoadingFirst
          ? Center(child: CircularProgressIndicator(color: _Tokens.navy))
          : RefreshIndicator(
              color: _Tokens.navy,
              onRefresh: _refreshAll,
              child: CustomScrollView(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        children: [
                          if (_trackingKnown && !_tracking) ...[
                            _buildSetupBanner(),
                            const SizedBox(height: 16),
                          ],
                          _buildDatePicker(),
                          const SizedBox(height: 25),
                          // STOCK OVERVIEW
                          _sectionHeader("Stock Overview"),
                          const SizedBox(height: 12),
                        ],
                      ),
                    ),
                  ),
                  if (_products.isEmpty)
                    SliverToBoxAdapter(
                      child: _productsError != null
                          ? _retryButton("Failed to load products", _loadFirstPage)
                          : _emptyState("No stock data found"),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, i) => _buildProductCard(_products[i]),
                          childCount: _products.length,
                        ),
                      ),
                    ),
                  if (showFooter)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Center(
                          child: _productsError != null
                              ? _retryButton("Couldn't load more", () {
                                  setState(() => _productsError = null);
                                  _loadMore();
                                })
                              : SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(strokeWidth: 2.5, color: _Tokens.navy),
                                ),
                        ),
                      ),
                    )
                  else if (!_hasMore)
                    // USER SALES OVERVIEW — appears once all products have been scrolled through.
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 30, 16, 16),
                      sliver: SliverToBoxAdapter(child: _buildUserSalesSection()),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _buildDatePicker() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _Tokens.border),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 3)),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                Icon(Icons.calendar_today_outlined, size: 18, color: _Tokens.muted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _selectedDate == null ? 'Select date' : _dateFormat.format(_selectedDate!),
                    style: _Tokens.body(size: 15, w: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          ElevatedButton.icon(
            icon: const Icon(Icons.calendar_month, color: _Tokens.navyDark, size: 18),
            label: Text("Choose date", style: _Tokens.body(w: FontWeight.w600, color: _Tokens.navyDark, size: 13)),
            style: ElevatedButton.styleFrom(
              backgroundColor: _Tokens.amber,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => _selectDate(context),
          ),
        ],
      ),
    );
  }

  Widget _buildSetupBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.amberBg,
        border: Border.all(color: _Tokens.amber),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.inventory_2_outlined, color: _Tokens.navy),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Stock isn't tracked yet", style: _Tokens.body(size: 14, w: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                  "Enter today's opening stock once. After that purchases add stock and every invoice takes it out.",
                  style: _Tokens.body(color: _Tokens.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _Tokens.amber, elevation: 0),
            onPressed: _openSetup,
            child: Text("Set up stock", style: _Tokens.body(w: FontWeight.w700, color: _Tokens.navyDark)),
          ),
        ],
      ),
    );
  }

  Widget _buildProductCard(Map<String, dynamic> product) {
    if (_tracking) return _buildTrackedProductCard(product);
    final productName = product['productName'] ?? '';
    final baseSize = int.tryParse(product['baseSize']?.toString() ?? '0') ?? 0;

    // Sold / available stay as placeholders until the load sheets have been aggregated.
    final num? soldQty = _totalSoldByProduct == null ? null : (_totalSoldByProduct![productName] ?? 0);
    final num? remainingQty = soldQty == null ? null : ((baseSize - soldQty) < 0 ? 0 : baseSize - soldQty);
    final placeholder = _salesError ? '—' : '…';
    final isLowStock = remainingQty != null && remainingQty < 50;

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: (){
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ProductTransactionsScreen(
              productName: product['productName'],
            ),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: _Tokens.border),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 3)),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      product['productName'] ?? 'Unknown Product',
                      style: _Tokens.display(size: 16),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: remainingQty == null ? _Tokens.bg : (isLowStock ? _Tokens.errorBg : _Tokens.greenBg),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      remainingQty == null ? (_salesError ? "Unavailable" : "Calculating…") : (isLowStock ? "Low Stock" : "In Stock"),
                      style: _Tokens.body(
                        size: 12,
                        w: FontWeight.w700,
                        color: remainingQty == null ? _Tokens.muted : (isLowStock ? _Tokens.error : _Tokens.green),
                      ),
                    ),
                  ),
                ],
              ),
              Divider(height: 22, color: _Tokens.border),
              Text("Category: ${product['productCategory'] ?? 'N/A'}", style: _Tokens.body(color: _Tokens.muted)),
              if ((product['brand'] ?? '').toString().trim().isNotEmpty)
                Text("Brand: ${product['brand']}", style: _Tokens.body(color: _Tokens.muted)),
              const SizedBox(height: 10),
              Text("Base Stock: ${product['baseSize'] ?? '0'} units", style: _Tokens.body(color: _Tokens.muted)),
              Text("Sold: ${soldQty ?? placeholder} units", style: _Tokens.body(color: _Tokens.error, w: FontWeight.w600)),
              Text("Available: ${remainingQty ?? placeholder} units", style: _Tokens.body(color: _Tokens.green, w: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }

  /// Stock on hand from the product's running count (purchases in, invoices out).
  Widget _buildTrackedProductCard(Map<String, dynamic> product) {
    final p = StockProduct.fromMap((product['id'] ?? '').toString(), product);
    final onHand = p.onHand;
    final status = onHand <= 0 ? "Out of stock" : (onHand < 50 ? "Low Stock" : "In Stock");
    final bad = onHand < 50;
    String q(num v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ProductStockScreen(productId: p.id, productName: p.name)),
        );
        _loadFirstPage(); // an adjustment may have changed it
      },
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: _Tokens.border),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 3)),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(p.name, style: _Tokens.display(size: 16), overflow: TextOverflow.ellipsis)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: bad ? _Tokens.errorBg : _Tokens.greenBg,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(status,
                        style: _Tokens.body(size: 12, w: FontWeight.w700, color: bad ? _Tokens.error : _Tokens.green)),
                  ),
                ],
              ),
              Divider(height: 22, color: _Tokens.border),
              Text("Category: ${p.category.isEmpty ? 'N/A' : p.category}", style: _Tokens.body(color: _Tokens.muted)),
              if (p.brand.trim().isNotEmpty) Text("Brand: ${p.brand}", style: _Tokens.body(color: _Tokens.muted)),
              const SizedBox(height: 10),
              Text("In stock: ${q(onHand)} units",
                  style: _Tokens.body(size: 14, color: bad ? _Tokens.error : _Tokens.green, w: FontWeight.w700)),
              if (_warehouses.length > 1)
                Text(
                  [
                    for (final w in _warehouses)
                      if (w.active || p.inWarehouse(w.id) != 0) "${w.name}: ${q(p.inWarehouse(w.id))}",
                  ].join("   ·   "),
                  style: _Tokens.body(color: _Tokens.textDark),
                ),
              Text(
                "Cost: ${p.costPrice > 0 ? 'Rs. ${p.costPrice}' : 'no purchase yet'}   ·   Sells at Rs. ${p.salePrice}"
                "${p.stockValue > 0 ? '   ·   Value Rs. ${NumberFormat('#,##0').format(p.stockValue)}' : ''}",
                style: _Tokens.body(color: _Tokens.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUserSalesSection() {
    Widget content;
    if (_totalSoldByProduct == null) {
      content = _salesError
          ? _retryButton("Failed to load sales data", _loadSales)
          : Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(child: CircularProgressIndicator(color: _Tokens.navy)),
            );
    } else if (_filteredUserSales.isEmpty) {
      content = _emptyState("No sales data available for the selected date.");
    } else {
      content = Column(children: _filteredUserSales.map(_buildUserSalesCard).toList());
    }

    return Column(
      children: [
        _sectionHeader("User Sales Overview"),
        const SizedBox(height: 12),
        content,
      ],
    );
  }

  Widget _buildUserSalesCard(Map<String, dynamic> sales) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _Tokens.border),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 3)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: _Tokens.navy.withOpacity(0.08),
                  child: Icon(Icons.person_outline, color: _Tokens.navy, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    sales['username'] ?? 'Unknown User',
                    style: _Tokens.display(size: 16),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            Divider(height: 22, color: _Tokens.border),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "Total Sales: Rs. ${NumberFormat('#,##0').format(num.tryParse('${sales['totalSalesAmount']}') ?? 0)}",
                  style: _Tokens.body(size: 14, color: _Tokens.green, w: FontWeight.w600),
                ),
                Text(
                  "Qty Sold: ${sales['salesQty']}",
                  style: _Tokens.body(size: 14, color: _Tokens.navy, w: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text("Products Sold", style: _Tokens.body(w: FontWeight.w700, size: 13.5)),
            const SizedBox(height: 6),
            ...sales['productsSold'].entries.map(
                  (entry) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Icon(Icons.check_circle, color: _Tokens.green, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "${entry.key}: ${entry.value} units",
                        style: _Tokens.body(size: 13, color: _Tokens.muted),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _retryButton(String message, VoidCallback onRetry) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, style: _Tokens.body(color: _Tokens.error)),
          TextButton(
            onPressed: onRetry,
            child: Text("Retry", style: _Tokens.body(color: _Tokens.navy, w: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 18,
          decoration: BoxDecoration(color: _Tokens.amber, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 8),
        Text(title, style: _Tokens.display(size: 17, color: _Tokens.navy)),
      ],
    );
  }

  Widget _emptyState(String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        children: [
          Icon(Icons.info_outline, size: 44, color: _Tokens.muted),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: _Tokens.body(size: 14, color: _Tokens.muted),
          ),
        ],
      ),
    );
  }
}
