// Stock, purchases and supplier balances.
//
// How stock moves:
//   - Each product has a running `stock` count (units on hand).
//   - Every change to it is written together with a row in `stock_moves`, in one batch, so the
//     count and its history always agree:
//       opening        – the count admin entered when stock tracking started
//       purchase       – goods received from a supplier (+)
//       purchase_return– goods sent back to a supplier (−)
//       sale           – a booker's invoice: QTY + FOC/bonus (−)
//       sale_change    – an invoice edited or a shop return processed (difference, ±)
//       sale_cancel    – an invoice deleted (+)
//       adjust         – a stock count, damage or expiry correction (±)
//   - Each invoice remembers what it took out of stock (`stockApplied`: productId → units), so an
//     edit, return or delete only moves the difference.
//
// Collections:
//   - `settings/stock`: { startedAt } – when stock tracking began. Before that nothing is tracked.
//   - `purchases`: supplier bills and returns, with lines and the cost of each unit.
//   - `supplier_payments`: money paid to suppliers.
//   - `stock_moves`: the history described above.
// Queries filter on a single field and sort on the device, so no composite indexes are needed.
import 'package:cloud_firestore/cloud_firestore.dart';
import '../account/account.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

final _db = FirebaseFirestore.instance;

DateTime? _asDate(dynamic v) {
  if (v is Timestamp) return v.toDate();
  if (v is DateTime) return v;
  return null;
}

num _asNum(dynamic v) => v is num ? v : (num.tryParse('${v ?? ''}'.trim()) ?? 0);

String _who() => FirebaseAuth.instance.currentUser?.email ?? '';

// =============================================================================
// Products
// =============================================================================

class StockProduct {
  final String id;
  final String name;
  final String supplier;
  final String category;
  final String size;
  final num salePrice; // dbPrice: the trade price bookers sell at
  final num costPrice; // last purchase cost per unit (0 until the first purchase)
  final num? stock; // null until stock tracking starts; the total across warehouses
  final num baseSize; // the old "Base Size" field, used to suggest opening stock
  // Units per warehouse id. Stock from before warehouses existed isn't in here: it counts as Main.
  final Map<String, num> stockBy;

  const StockProduct({
    required this.id,
    required this.name,
    required this.supplier,
    required this.category,
    required this.size,
    required this.salePrice,
    required this.costPrice,
    required this.stock,
    required this.baseSize,
    this.stockBy = const {},
  });

  factory StockProduct.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) =>
      StockProduct.fromMap(doc.id, doc.data() ?? const {});

  factory StockProduct.fromMap(String id, Map<String, dynamic> m) {
    return StockProduct(
      id: id,
      name: (m['productName'] ?? '').toString().trim(),
      supplier: (m['productSupplier'] ?? '').toString(),
      category: (m['productCategory'] ?? '').toString(),
      size: (m['productSize'] ?? '').toString(),
      salePrice: _asNum(m['dbPrice'] ?? m['dbPrie']),
      costPrice: _asNum(m['costPrice']),
      stock: m['stock'] is num ? m['stock'] as num : null,
      baseSize: _asNum(m['baseSize']),
      stockBy: m['stockBy'] is Map
          ? {for (final e in (m['stockBy'] as Map).entries) e.key.toString(): _asNum(e.value)}
          : const {},
    );
  }

  num get onHand => stock ?? 0;
  num get stockValue => onHand > 0 ? onHand * costPrice : 0;

  /// Units in one warehouse. Every stock change updates both the total and its warehouse, so
  /// whatever of the total isn't assigned to a warehouse is the stock from before warehouses
  /// existed, which is in Main.
  num inWarehouse(String warehouseId) {
    final assigned = stockBy.values.fold<num>(0, (s, v) => s + v);
    return (stockBy[warehouseId] ?? 0) + (warehouseId == mainWarehouseId ? onHand - assigned : 0);
  }
}

// =============================================================================
// Warehouses
// =============================================================================

/// Every company has Main, even before anyone sets warehouses up (it holds all older stock).
const mainWarehouseId = 'main';

class Warehouse {
  final String id;
  final String name;
  final String address;
  final String inCharge;
  final String phone;
  final bool active;
  const Warehouse({
    required this.id,
    required this.name,
    this.address = '',
    this.inCharge = '',
    this.phone = '',
    this.active = true,
  });

  factory Warehouse.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data() ?? const {};
    return Warehouse(
      id: doc.id,
      name: (m['name'] ?? '').toString().trim(),
      address: (m['address'] ?? '').toString().trim(),
      inCharge: (m['inCharge'] ?? '').toString().trim(),
      phone: (m['phone'] ?? '').toString().trim(),
      active: m['active'] != false,
    );
  }

  Map<String, dynamic> toMap() => {'name': name, 'address': address, 'inCharge': inCharge, 'phone': phone, 'active': active};
}

List<Warehouse>? _warehouseCache;
String? _warehouseCacheCompany;

/// The company's warehouses, Main first ([activeOnly]: leave out switched-off ones).
Future<List<Warehouse>> loadWarehouses({bool activeOnly = false, bool fresh = false}) async {
  if (fresh || _warehouseCache == null || _warehouseCacheCompany != Account.companyId) {
    final snap = await companyCol('warehouses').get();
    final list = snap.docs.map(Warehouse.fromDoc).where((w) => w.name.isNotEmpty).toList();
    if (!list.any((w) => w.id == mainWarehouseId)) list.add(const Warehouse(id: mainWarehouseId, name: 'Main warehouse'));
    list.sort((a, b) => a.id == mainWarehouseId ? -1 : (b.id == mainWarehouseId ? 1 : a.name.toLowerCase().compareTo(b.name.toLowerCase())));
    _warehouseCache = list;
    _warehouseCacheCompany = Account.companyId;
  }
  return [for (final w in _warehouseCache!) if (!activeOnly || w.active || w.id == mainWarehouseId) w];
}

/// Warehouse names by id, for labels (unknown ids show as the id).
Future<Map<String, String>> warehouseNames() async => {for (final w in await loadWarehouses()) w.id: w.name};

/// Adds a warehouse (empty [Warehouse.id]) or saves changes to one. Main can't be switched off.
Future<void> saveWarehouse(Warehouse w) async {
  final data = {...w.toMap(), if (w.id == mainWarehouseId) 'active': true};
  if (w.id.isEmpty) {
    await companyCol('warehouses').add({...data, 'createdAt': FieldValue.serverTimestamp()});
  } else {
    await companyCol('warehouses').doc(w.id).set(data, SetOptions(merge: true));
  }
  _warehouseCache = null;
}

/// The warehouse a booker's sales come from (their assigned one, else Main).
Future<String> warehouseForBooker(String? assigned) async {
  if (assigned == null || assigned.isEmpty) return mainWarehouseId;
  final all = await loadWarehouses();
  return all.any((w) => w.id == assigned && w.active) ? assigned : mainWarehouseId;
}

/// The signed-in booker's warehouse.
Future<String> myWarehouseId() => warehouseForBooker(Account.user?.warehouseId);

/// Sets the warehouse a booker sells from.
Future<void> assignBookerWarehouse(String uid, String warehouseId) =>
    _db.collection('users').doc(uid).update({'warehouseId': warehouseId});

/// Products by lower-case name. Invoices refer to products by name, so this is how a sale finds
/// the product it takes stock from.
class ProductIndex {
  final List<StockProduct> all;
  final Map<String, StockProduct> _byName;
  ProductIndex(this.all) : _byName = {for (final p in all) p.name.toLowerCase(): p};

  StockProduct? byName(String name) => _byName[name.trim().toLowerCase()];
}

ProductIndex? _productCache;
DateTime? _productCacheAt;
String? _productCacheCompany;

/// Every product, cached for a few minutes ([fresh] forces a reload).
Future<ProductIndex> loadProductIndex({bool fresh = false}) async {
  final at = _productCacheCompany == Account.companyId ? _productCacheAt : null;
  if (!fresh && _productCache != null && at != null && DateTime.now().difference(at).inMinutes < 5) {
    return _productCache!;
  }
  final snap = await companyCol('products').get();
  final list = snap.docs.map(StockProduct.fromDoc).where((p) => p.name.isNotEmpty).toList()
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  _productCache = ProductIndex(list);
  _productCacheAt = DateTime.now();
  _productCacheCompany = Account.companyId;
  return _productCache!;
}

/// The last loaded products, without waiting (for showing stock next to search results).
ProductIndex? get cachedProductIndex => _productCacheCompany == Account.companyId ? _productCache : null;

void _forgetProducts() => _productCacheAt = null;

// =============================================================================
// Tracking start
// =============================================================================

// A getter, not a final: it must follow whichever company is open.
DocumentReference<Map<String, dynamic>> get _settingsRef => companyCol('settings').doc('stock');
DateTime? _startedAt;
bool _startedKnown = false;
String? _startedCompany; // the company _startedAt belongs to

/// When stock tracking began, or null if admin hasn't set up opening stock yet.
Future<DateTime?> stockStartedAt({bool fresh = false}) async {
  // Once started it never goes back, so only the "not started" answer needs re-checking.
  if (_startedCompany != Account.companyId) _startedKnown = false;
  if (_startedKnown && (_startedAt != null || !fresh)) return _startedAt;
  final snap = await _settingsRef.get();
  _startedAt = _asDate(snap.data()?['startedAt']);
  _startedKnown = true;
  _startedCompany = Account.companyId;
  return _startedAt;
}

// =============================================================================
// Stock moves
// =============================================================================

class StockMove {
  final String id;
  final String productId;
  final String productName;
  final String type;
  final num qty; // + in, − out
  final num unitCost;
  final DateTime date;
  final String ref; // invoice or bill number
  final String party; // shop or supplier
  final String note;
  final String by;
  final String warehouseId; // moves from before warehouses existed were all Main

  const StockMove({
    required this.id,
    required this.productId,
    required this.productName,
    required this.type,
    required this.qty,
    required this.unitCost,
    required this.date,
    required this.ref,
    required this.party,
    required this.note,
    required this.by,
    this.warehouseId = mainWarehouseId,
  });

  factory StockMove.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data() ?? const {};
    return StockMove(
      id: doc.id,
      productId: (m['productId'] ?? '').toString(),
      productName: (m['productName'] ?? '').toString(),
      type: (m['type'] ?? '').toString(),
      qty: _asNum(m['qty']),
      unitCost: _asNum(m['unitCost']),
      date: _asDate(m['date']) ?? _asDate(m['createdAt']) ?? DateTime(2000),
      ref: (m['ref'] ?? '').toString(),
      party: (m['party'] ?? '').toString(),
      note: (m['note'] ?? '').toString(),
      by: (m['by'] ?? '').toString(),
      warehouseId: (m['warehouseId'] ?? '').toString().isEmpty ? mainWarehouseId : m['warehouseId'].toString(),
    );
  }

  String get label => switch (type) {
        'opening' => 'Opening stock',
        'purchase' => 'Purchase',
        'purchase_return' => 'Returned to supplier',
        'sale' => 'Sale',
        'sale_change' => 'Invoice changed',
        'sale_cancel' => 'Invoice deleted',
        'adjust' => 'Adjustment',
        'transfer_out' => 'Transferred out',
        'transfer_in' => 'Transferred in',
        _ => type,
      };
}

/// Adds one product's stock change in one warehouse, and its history row, to [batch]. The total
/// and the warehouse's own count always change together.
void _move(
  WriteBatch batch, {
  required StockProduct product,
  required String type,
  required num qty,
  String warehouseId = mainWarehouseId,
  bool changesTotal = true, // false for transfers: the company total stays the same
  num? unitCost,
  DateTime? date,
  String ref = '',
  String party = '',
  String note = '',
  String sourceId = '',
}) {
  if (qty == 0) return;
  batch.update(companyCol('products').doc(product.id), {
    if (changesTotal) 'stock': FieldValue.increment(qty),
    'stockBy.$warehouseId': FieldValue.increment(qty),
  });
  batch.set(companyCol('stock_moves').doc(), {
    'productId': product.id,
    'productName': product.name,
    'warehouseId': warehouseId,
    'type': type,
    'qty': qty,
    'unitCost': unitCost ?? product.costPrice,
    'date': Timestamp.fromDate(date ?? DateTime.now()),
    'ref': ref,
    'party': party,
    'note': note,
    'sourceId': sourceId,
    'by': _who(),
    'createdAt': FieldValue.serverTimestamp(),
  });
}

/// One product's history, newest first.
Future<List<StockMove>> loadStockMoves(String productId) async {
  final snap = await companyCol('stock_moves').where('productId', isEqualTo: productId).get();
  return snap.docs.map(StockMove.fromDoc).toList()..sort((a, b) => b.date.compareTo(a.date));
}

// =============================================================================
// Sales (booker invoices)
// =============================================================================

/// Units an invoice takes out of stock per product id: QTY − returned + FOC/bonus.
Map<String, num> invoiceUnits(List? items, ProductIndex products) {
  final out = <String, num>{};
  for (final it in items ?? const []) {
    if (it is! Map) continue;
    final p = products.byName((it['Product Name'] ?? '').toString());
    if (p == null) continue;
    final units = _asNum(it['QTY']) - _asNum(it['returnQty']) + _asNum(it['BNS'] ?? it['FOC']);
    if (units != 0) out[p.id] = (out[p.id] ?? 0) + units;
  }
  return out;
}

/// What an invoice as stored has already taken out of stock.
Map<String, num> _appliedUnits(Map<String, dynamic>? invoice, DateTime startedAt, ProductIndex products) {
  if (invoice == null) return {};
  final applied = invoice['stockApplied'];
  if (applied is Map) return {for (final e in applied.entries) e.key.toString(): _asNum(e.value)};
  // Invoices from before tracking started are already counted in the opening stock.
  final created = _asDate(invoice['createdAt']);
  if (created == null || created.isBefore(startedAt)) return invoiceUnits(invoice['items'] as List?, products);
  return {}; // made after tracking started by an older app version: not applied yet
}

/// What an invoice took out of stock, and from which warehouse. Saved on the invoice as
/// `stockApplied` and `stockWarehouse` (see [InvoiceStock.fields]).
class InvoiceStock {
  final Map<String, num> applied;
  final String warehouseId;
  const InvoiceStock(this.applied, this.warehouseId);

  Map<String, dynamic> get fields => {'stockApplied': applied, 'stockWarehouse': warehouseId};
}

/// The warehouse an invoice already took its stock from (older invoices: Main).
String _invoiceWarehouse(Map<String, dynamic>? invoice) {
  final w = (invoice?['stockWarehouse'] ?? invoice?['warehouseId'] ?? '').toString();
  return w.isEmpty ? mainWarehouseId : w;
}

/// Adds the stock changes for creating, changing or deleting one invoice to [batch].
/// [before] is the invoice as stored now (null when new); [afterItems] its new items (null when
/// deleted); [warehouseId] where the stock comes from (default: where it came from before, or
/// Main). Returns what to save on the invoice, or null if stock tracking is off.
Future<InvoiceStock?> addInvoiceStockMoves(
  WriteBatch batch, {
  Map<String, dynamic>? before,
  List? afterItems,
  required bool deleting,
  required String invoiceId,
  required String invoiceNo,
  required String shop,
  String? warehouseId,
}) async {
  final started = await stockStartedAt();
  if (started == null) return null;
  final products = await loadProductIndex();
  final byId = {for (final p in products.all) p.id: p};
  final had = _appliedUnits(before, started, products);
  final want = deleting ? <String, num>{} : invoiceUnits(afterItems, products);
  final hadIn = _invoiceWarehouse(before);
  final wantIn = warehouseId ?? hadIn;
  final type = before == null ? 'sale' : (deleting ? 'sale_cancel' : 'sale_change');
  void move(StockProduct p, num qty, String w) =>
      _move(batch, product: p, type: type, qty: qty, warehouseId: w, ref: 'Invoice #$invoiceNo', party: shop, sourceId: invoiceId);
  for (final id in {...had.keys, ...want.keys}) {
    final p = byId[id];
    if (p == null) continue;
    if (hadIn == wantIn) {
      move(p, -((want[id] ?? 0) - (had[id] ?? 0)), wantIn);
    } else {
      // The invoice moved to another warehouse: give it all back to the old one, take from the new.
      move(p, had[id] ?? 0, hadIn);
      move(p, -(want[id] ?? 0), wantIn);
    }
  }
  if (want.isNotEmpty || had.isNotEmpty) _forgetProducts();
  return InvoiceStock(want, wantIn);
}

/// Saves a change to an existing invoice (edit or shop return) and moves stock by the difference.
Future<void> updateInvoiceWithStock(String invoiceId, Map<String, dynamic> changes) async {
  final ref = companyCol('invoices').doc(invoiceId);
  final before = (await ref.get()).data();
  final batch = _db.batch();
  final items = changes.containsKey('items') ? changes['items'] as List? : before?['items'] as List?;
  final stock = await addInvoiceStockMoves(
    batch,
    before: before,
    afterItems: items,
    deleting: false,
    invoiceId: invoiceId,
    invoiceNo: (before?['invoiceNumber'] ?? '').toString(),
    shop: (changes['customer'] ?? before?['customer'] ?? '').toString(),
  );
  batch.update(ref, {...changes, ...?stock?.fields});
  await batch.commit();
}

/// Deletes an invoice and puts what it took back into stock.
Future<void> deleteInvoiceWithStock(String invoiceId) async {
  final ref = companyCol('invoices').doc(invoiceId);
  final before = (await ref.get()).data();
  final batch = _db.batch();
  await addInvoiceStockMoves(
    batch,
    before: before,
    deleting: true,
    invoiceId: invoiceId,
    invoiceNo: (before?['invoiceNumber'] ?? '').toString(),
    shop: (before?['customer'] ?? '').toString(),
  );
  batch.delete(ref);
  await batch.commit();
}

/// Takes stock for invoices made after tracking started that didn't (e.g. booked on an older
/// app version, or the booker's save couldn't update stock). Returns how many it fixed.
Future<int> applyUntrackedInvoices() async {
  final started = await stockStartedAt(fresh: true);
  if (started == null) return 0;
  final snap = await companyCol('invoices').where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(started)).get();
  final todo = snap.docs.where((d) => d.data()['stockApplied'] is! Map).toList();
  if (todo.isEmpty) return 0;
  // Older app versions don't say which warehouse: use the booker's assigned one.
  final assigned = {
    for (final u in await _db.collection('users').where('companyId', isEqualTo: Account.companyId).get().then((s) => s.docs))
      u.id: (u.data()['warehouseId'] ?? '').toString(),
  };
  var done = 0;
  for (final doc in todo) {
    final data = doc.data();
    final batch = _db.batch();
    final stock = await addInvoiceStockMoves(
      batch,
      before: null,
      afterItems: data['items'] as List?,
      deleting: false,
      invoiceId: doc.id,
      invoiceNo: (data['invoiceNumber'] ?? '').toString(),
      shop: (data['customer'] ?? '').toString(),
      warehouseId: (data['warehouseId'] ?? '').toString().isNotEmpty
          ? data['warehouseId'].toString()
          : await warehouseForBooker(assigned[(data['userId'] ?? '').toString()]),
    );
    batch.update(doc.reference, stock?.fields ?? {'stockApplied': {}});
    await batch.commit();
    done++;
  }
  if (done > 0) debugPrint('Stock: applied $done untracked invoice(s)');
  return done;
}

// =============================================================================
// Opening stock
// =============================================================================

class OpeningRow {
  final StockProduct product;
  final num soldBefore; // QTY + FOC on invoices so far, minus returns
  const OpeningRow(this.product, this.soldBefore);

  /// Base Size minus what was sold — the old screen's "Available" figure, never below 0.
  num get suggested => (product.baseSize - soldBefore) < 0 ? 0 : product.baseSize - soldBefore;
}

/// Works out a suggested opening count for every product, and the moment it was worked out
/// (invoices after that moment are taken out of stock once tracking starts).
Future<(List<OpeningRow>, DateTime)> computeOpeningStock() async {
  final at = DateTime.now();
  final products = await loadProductIndex(fresh: true);
  final invoices = await companyCol('invoices').get();
  final sold = <String, num>{};
  for (final d in invoices.docs) {
    invoiceUnits(d.data()['items'] as List?, products).forEach((id, u) => sold[id] = (sold[id] ?? 0) + u);
  }
  return ([for (final p in products.all) OpeningRow(p, sold[p.id] ?? 0)], at);
}

/// Sets every product's opening count and starts tracking from [startedAt].
Future<void> startStockTracking(Map<StockProduct, num> counts, DateTime startedAt) async {
  final entries = counts.entries.toList();
  // A batch holds 500 writes; each product needs two (count + history row).
  for (var i = 0; i < entries.length; i += 200) {
    final batch = _db.batch();
    for (final e in entries.skip(i).take(200)) {
      batch.update(companyCol('products').doc(e.key.id), {'stock': e.value});
      batch.set(companyCol('stock_moves').doc(), {
        'productId': e.key.id,
        'productName': e.key.name,
        'type': 'opening',
        'qty': e.value,
        'unitCost': e.key.costPrice,
        'date': Timestamp.fromDate(startedAt),
        'ref': '',
        'party': '',
        'note': 'Opening stock',
        'sourceId': '',
        'by': _who(),
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }
  await _settingsRef.set({'startedAt': Timestamp.fromDate(startedAt), 'startedBy': _who()});
  _startedAt = startedAt;
  _startedKnown = true;
  _startedCompany = Account.companyId;
  _forgetProducts();
}

/// Gives a product added after tracking started its first stock count.
Future<void> setNewProductStock(String productId, String name, num qty) async {
  if (await stockStartedAt() == null) return;
  final batch = _db.batch();
  final p = StockProduct(
      id: productId, name: name, supplier: '', category: '', size: '', salePrice: 0, costPrice: 0, stock: 0, baseSize: 0);
  batch.set(companyCol('products').doc(productId), {'stock': 0}, SetOptions(merge: true));
  _move(batch, product: p, type: 'opening', qty: qty, note: 'Opening stock (new product)');
  await batch.commit();
  _forgetProducts();
}

/// Corrects a product's count in one warehouse (stock take, damage, expiry). [qty] is + to add,
/// − to remove.
Future<void> adjustStock(StockProduct product, num qty, String reason, {String warehouseId = mainWarehouseId}) async {
  final batch = _db.batch();
  _move(batch, product: product, type: 'adjust', qty: qty, warehouseId: warehouseId, note: reason);
  await batch.commit();
  _forgetProducts();
}

/// Moves [qty] units of a product from one warehouse to another. The company total stays the same.
Future<void> transferStock(StockProduct product, {required String from, required String to, required num qty, String note = ''}) async {
  if (from == to || qty <= 0) return;
  final names = await warehouseNames();
  final batch = _db.batch();
  final ref = 'Transfer ${names[from] ?? from} → ${names[to] ?? to}';
  _move(batch, product: product, type: 'transfer_out', qty: -qty, warehouseId: from, changesTotal: false, ref: ref, note: note);
  _move(batch, product: product, type: 'transfer_in', qty: qty, warehouseId: to, changesTotal: false, ref: ref, note: note);
  await batch.commit();
  _forgetProducts();
}

// =============================================================================
// Suppliers, purchases and payments
// =============================================================================

/// Product categories (the same list the product form uses), for what a supplier supplies.
const supplierCategories = ['Stationery', 'Cosmetics', 'Consumer', 'Electronics', 'Others'];

class Supplier {
  final String id;
  final String name; // the supplier / firm name used everywhere (products link to it by name)
  final String company; // legal or parent company, if different
  final String contact; // main phone
  final String whatsapp;
  final String email;
  final String contactPerson;
  final String contactCnic;
  final String address;
  final String city;
  final String ntn;
  final String strn; // sales tax registration number
  final String category;
  final String brands; // brands / products supplied
  final int paymentTermsDays; // 0 = cash on delivery
  final num creditLimit; // 0 = no limit
  final num openingBalance; // owed to them when they were added (negative: they owe us)
  final DateTime? openingDate;
  final String bankName;
  final String accountTitle;
  final String iban;
  final bool active;
  final String notes;
  final DateTime? createdAt;

  const Supplier({
    required this.id,
    required this.name,
    this.company = '',
    this.contact = '',
    this.whatsapp = '',
    this.email = '',
    this.contactPerson = '',
    this.contactCnic = '',
    this.address = '',
    this.city = '',
    this.ntn = '',
    this.strn = '',
    this.category = '',
    this.brands = '',
    this.paymentTermsDays = 0,
    this.creditLimit = 0,
    this.openingBalance = 0,
    this.openingDate,
    this.bankName = '',
    this.accountTitle = '',
    this.iban = '',
    this.active = true,
    this.notes = '',
    this.createdAt,
  });

  factory Supplier.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data() ?? const {};
    String s(String k) => (m[k] ?? '').toString().trim();
    return Supplier(
      id: doc.id,
      name: s('name'),
      company: s('company'),
      contact: s('contact'),
      whatsapp: s('whatsapp'),
      email: s('email'),
      contactPerson: s('contactPerson'),
      contactCnic: s('contactCnic'),
      address: s('address'),
      city: s('city'),
      ntn: s('ntn'),
      strn: s('strn'),
      category: s('category'),
      brands: s('brands'),
      paymentTermsDays: _asNum(m['paymentTermsDays']).toInt(),
      creditLimit: _asNum(m['creditLimit']),
      openingBalance: _asNum(m['openingBalance']),
      openingDate: _asDate(m['openingDate']) ?? _asDate(m['createdAt']),
      bankName: s('bankName'),
      accountTitle: s('accountTitle'),
      iban: s('iban'),
      active: m['active'] != false, // suppliers saved before this field existed are active
      notes: s('notes'),
      createdAt: _asDate(m['createdAt']),
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'company': company,
        'contact': contact,
        'whatsapp': whatsapp,
        'email': email,
        'contactPerson': contactPerson,
        'contactCnic': contactCnic,
        'address': address,
        'city': city,
        'ntn': ntn,
        'strn': strn,
        'category': category,
        'brands': brands,
        'paymentTermsDays': paymentTermsDays,
        'creditLimit': creditLimit,
        'openingBalance': openingBalance,
        'openingDate': openingDate == null ? null : Timestamp.fromDate(openingDate!),
        'bankName': bankName,
        'accountTitle': accountTitle,
        'iban': iban,
        'active': active,
        'notes': notes,
      };

  String get display => company.isEmpty || company == name ? name : '$name ($company)';
  String get termsLabel => paymentTermsDays <= 0 ? 'Cash' : '$paymentTermsDays days credit';
}

/// Every supplier ([activeOnly]: leave out ones switched to inactive), by name.
Future<List<Supplier>> loadSuppliers({bool activeOnly = false}) async {
  final snap = await companyCol('suppliers').get();
  return snap.docs
      .map(Supplier.fromDoc)
      .where((s) => s.name.isNotEmpty && (!activeOnly || s.active))
      .toList()
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
}

/// Another supplier already using this name or NTN, if any (to warn before saving a duplicate).
Future<Supplier?> findDuplicateSupplier({required String name, required String ntn, String? exceptId}) async {
  final all = await loadSuppliers();
  final n = name.trim().toLowerCase();
  final t = ntn.replaceAll(RegExp(r'[^0-9A-Za-z]'), '').toLowerCase();
  for (final s in all) {
    if (s.id == exceptId) continue;
    if (s.name.toLowerCase() == n) return s;
    if (t.isNotEmpty && s.ntn.replaceAll(RegExp(r'[^0-9A-Za-z]'), '').toLowerCase() == t) return s;
  }
  return null;
}

/// Adds a supplier, or saves changes to one. A renamed supplier's products follow the new name
/// (products link to their supplier by name).
Future<void> saveSupplier(Supplier s, {String? oldName}) async {
  final col = companyCol('suppliers');
  if (s.id.isEmpty) {
    await col.add({...s.toMap(), 'createdAt': FieldValue.serverTimestamp()});
    return;
  }
  final batch = _db.batch();
  batch.update(col.doc(s.id), {...s.toMap(), 'updatedAt': FieldValue.serverTimestamp()});
  if (oldName != null && oldName.isNotEmpty && oldName != s.name) {
    final products = await companyCol('products').where('productSupplier', isEqualTo: oldName).get();
    for (final p in products.docs) {
      batch.update(p.reference, {'productSupplier': s.name});
    }
  }
  await batch.commit();
  _forgetProducts();
}

/// Why a supplier can't be deleted (it has history), or null if it can.
Future<String?> supplierDeleteBlocker(Supplier s) async {
  final results = await Future.wait([
    companyCol('purchases').where('supplierId', isEqualTo: s.id).limit(1).get(),
    companyCol('supplier_payments').where('supplierId', isEqualTo: s.id).limit(1).get(),
    companyCol('products').where('productSupplier', isEqualTo: s.name).limit(1).get(),
  ]);
  if (results[0].docs.isNotEmpty) return 'It has purchase bills.';
  if (results[1].docs.isNotEmpty) return 'It has payments.';
  if (results[2].docs.isNotEmpty) return 'Products are linked to it.';
  if (s.openingBalance != 0) return 'It has an opening balance.';
  return null;
}

Future<void> deleteSupplier(Supplier s) => companyCol('suppliers').doc(s.id).delete();

class PurchaseLine {
  final String productId;
  final String productName;
  final num qty;
  final num unitCost;
  const PurchaseLine({required this.productId, required this.productName, required this.qty, required this.unitCost});

  num get amount => qty * unitCost;

  Map<String, dynamic> toMap() =>
      {'productId': productId, 'productName': productName, 'qty': qty, 'unitCost': unitCost, 'amount': amount};

  factory PurchaseLine.fromMap(Map m) => PurchaseLine(
        productId: (m['productId'] ?? '').toString(),
        productName: (m['productName'] ?? '').toString(),
        qty: _asNum(m['qty']),
        unitCost: _asNum(m['unitCost']),
      );
}

/// A supplier bill (goods in) or a purchase return (goods sent back).
class Purchase {
  final String id;
  final bool isReturn;
  final String supplierId;
  final String supplierName;
  final String billNo;
  final DateTime date;
  final List<PurchaseLine> lines;
  final num discount;
  final String note;
  final String by;
  final String warehouseId; // where the goods went in (or, for a return, came out)

  const Purchase({
    this.id = '',
    required this.isReturn,
    this.warehouseId = mainWarehouseId,
    required this.supplierId,
    required this.supplierName,
    required this.billNo,
    required this.date,
    required this.lines,
    this.discount = 0,
    this.note = '',
    this.by = '',
  });

  num get subtotal => lines.fold<num>(0, (s, l) => s + l.amount);
  num get total => subtotal - discount;
  num get units => lines.fold<num>(0, (s, l) => s + l.qty);

  /// What this changes the amount owed to the supplier by.
  num get payableEffect => isReturn ? -total : total;

  factory Purchase.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data() ?? const {};
    return Purchase(
      id: doc.id,
      isReturn: m['type'] == 'return',
      supplierId: (m['supplierId'] ?? '').toString(),
      supplierName: (m['supplierName'] ?? '').toString(),
      billNo: (m['billNo'] ?? '').toString(),
      date: _asDate(m['date']) ?? DateTime(2000),
      lines: [for (final l in (m['lines'] as List? ?? const [])) if (l is Map) PurchaseLine.fromMap(l)],
      discount: _asNum(m['discount']),
      note: (m['note'] ?? '').toString(),
      by: (m['by'] ?? '').toString(),
      warehouseId: (m['warehouseId'] ?? '').toString().isEmpty ? mainWarehouseId : m['warehouseId'].toString(),
    );
  }
}

class SupplierPayment {
  final String id;
  final String supplierId;
  final String supplierName;
  final num amount;
  final DateTime date;
  final String method;
  final String note;
  const SupplierPayment(this.id, this.supplierId, this.supplierName, this.amount, this.date, this.method, this.note);

  factory SupplierPayment.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data() ?? const {};
    return SupplierPayment(
      doc.id,
      (m['supplierId'] ?? '').toString(),
      (m['supplierName'] ?? '').toString(),
      _asNum(m['amount']),
      _asDate(m['date']) ?? DateTime(2000),
      (m['method'] ?? '').toString(),
      (m['note'] ?? '').toString(),
    );
  }
}

/// Saves a bill or return, moves stock, and (for a bill) records the new cost price. [paidNow]
/// is cash handed over with the bill and is saved as a payment.
Future<void> savePurchase(Purchase p, {num paidNow = 0, String method = 'Cash'}) async {
  final products = await loadProductIndex(fresh: true);
  final byId = {for (final x in products.all) x.id: x};
  final tracking = await stockStartedAt() != null;
  final batch = _db.batch();
  final ref = companyCol('purchases').doc();
  batch.set(ref, {
    'type': p.isReturn ? 'return' : 'purchase',
    'supplierId': p.supplierId,
    'supplierName': p.supplierName,
    'billNo': p.billNo,
    'warehouseId': p.warehouseId,
    'date': Timestamp.fromDate(p.date),
    'lines': p.lines.map((l) => l.toMap()).toList(),
    'subtotal': p.subtotal,
    'discount': p.discount,
    'total': p.total,
    'note': p.note,
    'by': _who(),
    'createdAt': FieldValue.serverTimestamp(),
  });
  final party = p.supplierName;
  final ref0 = p.billNo.isEmpty ? (p.isReturn ? 'Purchase return' : 'Purchase') : 'Bill ${p.billNo}';
  for (final l in p.lines) {
    final product = byId[l.productId];
    if (product == null) continue;
    if (!p.isReturn && l.unitCost > 0) {
      batch.update(companyCol('products').doc(product.id), {'costPrice': l.unitCost});
    }
    if (tracking) {
      _move(batch,
          product: product,
          type: p.isReturn ? 'purchase_return' : 'purchase',
          qty: p.isReturn ? -l.qty : l.qty,
          warehouseId: p.warehouseId,
          unitCost: l.unitCost,
          date: p.date,
          ref: ref0,
          party: party,
          sourceId: ref.id);
    }
  }
  if (paidNow > 0) {
    batch.set(companyCol('supplier_payments').doc(), {
      'supplierId': p.supplierId,
      'supplierName': p.supplierName,
      'amount': paidNow,
      'date': Timestamp.fromDate(p.date),
      'method': method,
      'note': p.billNo.isEmpty ? 'Paid with purchase' : 'Paid with bill ${p.billNo}',
      'purchaseId': ref.id,
      'by': _who(),
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
  await batch.commit();
  _forgetProducts();
}

/// Deletes a bill or return and undoes its stock change (cost prices are left as they are).
Future<void> deletePurchase(Purchase p) async {
  final products = await loadProductIndex(fresh: true);
  final byId = {for (final x in products.all) x.id: x};
  final batch = _db.batch();
  // Only undo stock this bill actually moved (it may predate tracking).
  final moves = await companyCol('stock_moves').where('sourceId', isEqualTo: p.id).get();
  for (final m in moves.docs) {
    final mv = StockMove.fromDoc(m);
    final product = byId[mv.productId];
    if (product == null) continue;
    _move(batch,
        product: product,
        type: mv.type,
        qty: -mv.qty,
        unitCost: mv.unitCost,
        ref: '${mv.ref} (deleted)',
        party: mv.party,
        note: 'Bill deleted',
        warehouseId: mv.warehouseId);
  }
  batch.delete(companyCol('purchases').doc(p.id));
  await batch.commit();
  _forgetProducts();
}

Future<void> addSupplierPayment(Supplier s, num amount, DateTime date, String method, String note) =>
    companyCol('supplier_payments').add({
      'supplierId': s.id,
      'supplierName': s.name,
      'amount': amount,
      'date': Timestamp.fromDate(date),
      'method': method,
      'note': note,
      'by': _who(),
      'createdAt': FieldValue.serverTimestamp(),
    });

Future<void> deleteSupplierPayment(String id) => companyCol('supplier_payments').doc(id).delete();

/// All suppliers with their bills, returns and payments.
class PayablesBook {
  final List<Supplier> suppliers;
  final List<Purchase> purchases; // newest first, bills and returns
  final List<SupplierPayment> payments; // newest first

  PayablesBook(this.suppliers, this.purchases, this.payments);

  List<Purchase> purchasesOf(String supplierId) => purchases.where((p) => p.supplierId == supplierId).toList();
  List<SupplierPayment> paymentsOf(String supplierId) => payments.where((p) => p.supplierId == supplierId).toList();

  Supplier? supplier(String supplierId) => suppliers.where((s) => s.id == supplierId).firstOrNull;
  num openingOf(String supplierId) => supplier(supplierId)?.openingBalance ?? 0;

  num purchasedFrom(String supplierId) =>
      purchasesOf(supplierId).fold<num>(0, (s, p) => s + p.payableEffect);
  num paidTo(String supplierId) => paymentsOf(supplierId).fold<num>(0, (s, p) => s + p.amount);

  /// What we owe the supplier, opening balance included (negative = they owe us).
  num balanceOf(String supplierId) => openingOf(supplierId) + purchasedFrom(supplierId) - paidTo(supplierId);

  /// The part of the balance that is past the supplier's payment terms. Payments and returns pay
  /// off the oldest amounts first (the opening balance, then bills by date). Cash suppliers
  /// (no credit days) are due on the bill date.
  num overdueOf(String supplierId, {DateTime? today}) {
    final s = supplier(supplierId);
    final now = today ?? DateTime.now();
    final terms = s?.paymentTermsDays ?? 0;
    final owed = <(DateTime, num)>[
      if ((s?.openingBalance ?? 0) > 0) (s!.openingDate ?? DateTime(2000), s.openingBalance),
      for (final p in purchasesOf(supplierId).where((p) => !p.isReturn)) (p.date, p.total),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    var credit = paidTo(supplierId) +
        purchasesOf(supplierId).where((p) => p.isReturn).fold<num>(0, (t, p) => t + p.total) +
        ((s?.openingBalance ?? 0) < 0 ? -(s!.openingBalance) : 0);
    num overdue = 0;
    for (final (date, amount) in owed) {
      final unpaid = amount - (credit > amount ? amount : credit);
      credit = credit > amount ? credit - amount : 0;
      if (unpaid > 0 && now.difference(date).inDays > terms) overdue += unpaid;
    }
    return overdue;
  }

  num get totalPayable => suppliers.fold<num>(0, (s, x) {
        final b = balanceOf(x.id);
        return s + (b > 0 ? b : 0);
      });
}

Future<PayablesBook> loadPayables() async {
  final results = await Future.wait<Object>([
    loadSuppliers(),
    companyCol('purchases').get(),
    companyCol('supplier_payments').get(),
  ]);
  final purchases = (results[1] as QuerySnapshot<Map<String, dynamic>>).docs.map(Purchase.fromDoc).toList()
    ..sort((a, b) => b.date.compareTo(a.date));
  final payments = (results[2] as QuerySnapshot<Map<String, dynamic>>).docs.map(SupplierPayment.fromDoc).toList()
    ..sort((a, b) => b.date.compareTo(a.date));
  return PayablesBook(results[0] as List<Supplier>, purchases, payments);
}

// =============================================================================
// Profit
// =============================================================================

class ProductProfit {
  final String name;
  num units = 0; // sold + bonus, after returns
  num sales = 0; // net of returns and invoice discounts
  num cost = 0;
  ProductProfit(this.name);
  num get profit => sales - cost;
}

class ProfitReport {
  final List<ProductProfit> products; // highest sales first
  final num purchases;
  final num paidToSuppliers;
  final int invoices;
  final int productsWithoutCost; // sold, but no purchase recorded yet, so cost is unknown (0)
  ProfitReport(this.products, this.purchases, this.paidToSuppliers, this.invoices, this.productsWithoutCost);

  num get sales => products.fold<num>(0, (s, p) => s + p.sales);
  num get cost => products.fold<num>(0, (s, p) => s + p.cost);
  num get profit => sales - cost;
}

/// Sales, cost of goods and gross profit for invoices whose Sales Date is in [from]..[to].
/// Cost uses each product's latest purchase cost.
Future<ProfitReport> loadProfitReport(DateTime from, DateTime to) async {
  final start = DateTime(from.year, from.month, from.day);
  final end = DateTime(to.year, to.month, to.day).add(const Duration(days: 1));
  final results = await Future.wait<Object>([
    loadProductIndex(fresh: true),
    companyCol('invoices')
        .where('salesDateTs', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('salesDateTs', isLessThan: Timestamp.fromDate(end))
        .get(),
    loadPayables(),
  ]);
  final products = results[0] as ProductIndex;
  final invoices = (results[1] as QuerySnapshot<Map<String, dynamic>>).docs;
  final payables = results[2] as PayablesBook;

  final rows = <String, ProductProfit>{};
  for (final doc in invoices) {
    final m = doc.data();
    final items = (m['items'] as List? ?? const []).whereType<Map>().toList();
    final gross = items.fold<num>(0, (s, it) => s + _asNum(it['Gross Total']) - _asNum(it['returnAmount']));
    final total = _asNum(m['grandTotal'] ?? m['total']);
    // Share the invoice discount across its lines by value.
    final factor = gross > 0 ? (total / gross).clamp(0, 1) : 1;
    for (final it in items) {
      final name = (it['Product Name'] ?? '').toString().trim();
      if (name.isEmpty) continue;
      final p = products.byName(name);
      final row = rows.putIfAbsent(p?.name ?? name, () => ProductProfit(p?.name ?? name));
      final units = _asNum(it['QTY']) - _asNum(it['returnQty']) + _asNum(it['BNS'] ?? it['FOC']);
      row.units += units;
      row.sales += (_asNum(it['Gross Total']) - _asNum(it['returnAmount'])) * factor;
      row.cost += units * (p?.costPrice ?? 0);
    }
  }
  final noCost = rows.values.where((r) => r.units > 0 && (products.byName(r.name)?.costPrice ?? 0) == 0).length;
  bool inRange(DateTime d) => !d.isBefore(start) && d.isBefore(end);
  return ProfitReport(
    rows.values.toList()..sort((a, b) => b.sales.compareTo(a.sales)),
    payables.purchases.where((p) => inRange(p.date)).fold<num>(0, (s, p) => s + p.payableEffect),
    payables.payments.where((p) => inRange(p.date)).fold<num>(0, (s, p) => s + p.amount),
    invoices.length,
    noCost,
  );
}
