// Purchase orders: what you've asked a supplier for, before the goods come. Receiving opens a
// purchase bill filled with what's still to come.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../account/account.dart';
import '../crm/crm_ui.dart';
import '../inventory/inventory_data.dart';
import '../inventory/purchase_form.dart';
import '../inventory/quotations_data.dart';
import '../print_preview.dart';
import 'orders_data.dart';

String _plain(num v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : '$v';

(String, Color, Color) poStatusLook(PurchaseOrder po) => switch (po.status) {
      'received' => ('Received', CrmTokens.green, CrmTokens.greenBg),
      'partial' => ('Part received', CrmTokens.blue, CrmTokens.blueBg),
      'cancelled' => ('Cancelled', CrmTokens.muted, CrmTokens.bg),
      _ => po.isLate ? ('Late', CrmTokens.red, CrmTokens.redBg) : ('Open', CrmTokens.amber, CrmTokens.amberBg),
    };

/// The Orders tab of Purchases.
class PurchaseOrdersTab extends StatefulWidget {
  final VoidCallback onReceived; // a bill was saved: Bills need reloading
  const PurchaseOrdersTab({super.key, required this.onReceived});

  @override
  State<PurchaseOrdersTab> createState() => _PurchaseOrdersTabState();
}

class _PurchaseOrdersTabState extends State<PurchaseOrdersTab> {
  List<PurchaseOrder>? _orders;
  Map<String, String> _warehouses = const {};
  Object? _error;
  bool _openOnly = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final r = await Future.wait<Object>([loadPurchaseOrders(), warehouseNames()]);
      if (!mounted) return;
      setState(() {
        _orders = r[0] as List<PurchaseOrder>;
        _warehouses = r[1] as Map<String, String>;
      });
    } catch (e) {
      debugPrint('Purchase orders: $e');
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _edit([PurchaseOrder? po]) async {
    final saved = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => PurchaseOrderFormScreen(order: po)));
    if (saved == true) _load();
  }

  Future<void> _receive(PurchaseOrder po) async {
    final saved = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => PurchaseFormScreen(order: po)));
    if (saved == true) {
      _load();
      widget.onReceived();
    }
  }

  @override
  Widget build(BuildContext context) {
    final all = _orders;
    if (all == null) {
      if (_error == null) return const Center(child: CircularProgressIndicator(color: CrmTokens.navy));
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const CrmEmpty(icon: Icons.cloud_off, text: "Couldn't load purchase orders. Check your connection."),
          OutlinedButton(onPressed: _load, child: Text('Try again', style: CrmTokens.body(color: CrmTokens.navy))),
        ]),
      );
    }
    final shown = all.where((o) => !_openOnly || o.isOpen).toList();
    final open = all.where((o) => o.isOpen).toList();
    final onOrder = open.fold<num>(0, (s, o) => s + o.lines.fold<num>(0, (t, l) => t + l.remaining * l.unitCost));
    return RefreshIndicator(
      color: CrmTokens.navy,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 96),
        children: [
          Row(children: [
            Expanded(child: CrmStat(label: 'Open orders', value: '${open.length}')),
            const SizedBox(width: 8),
            Expanded(child: CrmStat(label: 'Still to come (value)', value: crmRs(onOrder))),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Checkbox(value: _openOnly, activeColor: CrmTokens.navy, onChanged: (v) => setState(() => _openOnly = v ?? true)),
            Text('Open only', style: CrmTokens.body(color: CrmTokens.muted)),
            const Spacer(),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: CrmTokens.navy, elevation: 0),
              onPressed: () => _edit(),
              icon: const Icon(Icons.add, color: Colors.white, size: 18),
              label: Text('Purchase order', style: CrmTokens.body(color: Colors.white, w: FontWeight.w600)),
            ),
          ]),
          const SizedBox(height: 6),
          if (all.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 30),
              child: CrmEmpty(
                icon: Icons.assignment_outlined,
                text: 'No purchase orders yet. Order from a supplier here (or from a quotation); when the goods come, '
                    'receive them and the purchase bill is filled in for you.',
              ),
            )
          else if (shown.isEmpty)
            Text('No open orders.', style: CrmTokens.body(color: CrmTokens.muted))
          else
            for (final po in shown) _card(po),
        ],
      ),
    );
  }

  Widget _card(PurchaseOrder po) {
    final (label, color, bg) = poStatusLook(po);
    final units = po.lines.fold<num>(0, (s, l) => s + l.qty);
    final got = po.lines.fold<num>(0, (s, l) => s + (l.received > l.qty ? l.qty : l.received));
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: CrmCard(
        onTap: () => _details(po),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('${po.number}  ·  ${po.supplierName}', style: CrmTokens.display(size: 15))),
            CrmPill(label, color: color, background: bg),
          ]),
          const SizedBox(height: 3),
          Text(
            [
              crmDay.format(po.date),
              if (po.expected != null) 'expected ${crmDay.format(po.expected!)}',
              '${po.lines.length} product${po.lines.length == 1 ? '' : 's'}',
              crmRs(po.total),
            ].join('  ·  '),
            style: CrmTokens.body(size: 12, color: CrmTokens.muted),
          ),
          if (po.status == 'partial') ...[
            const SizedBox(height: 6),
            LinearProgressIndicator(
              value: units == 0 ? 0 : (got / units).toDouble(),
              minHeight: 5,
              color: CrmTokens.blue,
              backgroundColor: CrmTokens.bg,
            ),
            Text('${_plain(got)} of ${_plain(units)} units received', style: CrmTokens.body(size: 11.5, color: CrmTokens.muted)),
          ],
        ]),
      ),
    );
  }

  Future<void> _details(PurchaseOrder po) async {
    final (label, color, bg) = poStatusLook(po);
    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text('${po.number}  ·  ${po.supplierName}', style: CrmTokens.display(size: 17))),
              CrmPill(label, color: color, background: bg),
            ]),
            const SizedBox(height: 4),
            Text(
              [
                crmDay.format(po.date),
                if (po.expected != null) 'expected ${crmDay.format(po.expected!)}',
                'into ${_warehouses[po.warehouseId] ?? 'Main warehouse'}',
              ].join('  ·  '),
              style: CrmTokens.body(color: CrmTokens.muted),
            ),
            const Divider(height: 22),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(sheet).size.height * 0.45),
              child: ListView(shrinkWrap: true, children: [
                for (final l in po.lines)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(l.productName, style: CrmTokens.body(w: FontWeight.w600)),
                          Text('${_plain(l.qty)} × Rs. ${_plain(l.unitCost)}'
                              '${l.received > 0 ? '  ·  ${_plain(l.received)} received' : ''}',
                              style: CrmTokens.body(size: 12, color: CrmTokens.muted)),
                        ]),
                      ),
                      Text(crmRs(l.amount), style: CrmTokens.body(w: FontWeight.w700)),
                    ]),
                  ),
              ]),
            ),
            const Divider(height: 18),
            Row(children: [
              Expanded(child: Text('Total', style: CrmTokens.body(w: FontWeight.w700))),
              Text(crmRs(po.total), style: CrmTokens.display(size: 16, color: CrmTokens.navy)),
            ]),
            if (po.note.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(po.note, style: CrmTokens.body(size: 12, color: CrmTokens.muted)),
            ],
            const SizedBox(height: 14),
            Wrap(spacing: 4, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              IconButton(
                tooltip: 'Print / share with supplier',
                onPressed: () => Navigator.pop(sheet, 'print'),
                icon: const Icon(Icons.print_outlined, color: CrmTokens.navy),
              ),
              if (po.isOpen && po.nothingReceived)
                IconButton(
                  tooltip: 'Edit',
                  onPressed: () => Navigator.pop(sheet, 'edit'),
                  icon: const Icon(Icons.edit_outlined, color: CrmTokens.navy),
                ),
              if (po.isOpen)
                IconButton(
                  tooltip: po.nothingReceived ? 'Cancel order' : 'Close (nothing more is coming)',
                  onPressed: () => Navigator.pop(sheet, 'cancel'),
                  icon: const Icon(Icons.block, color: CrmTokens.red),
                ),
              if (po.isOpen)
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: CrmTokens.amber, elevation: 0),
                  onPressed: () => Navigator.pop(sheet, 'receive'),
                  icon: const Icon(Icons.move_to_inbox_outlined, color: CrmTokens.navyDark, size: 18),
                  label: Text('Receive goods', style: CrmTokens.body(color: CrmTokens.navyDark, w: FontWeight.w700)),
                ),
            ]),
          ]),
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'print':
        showPrintPreview(context,
            title: po.number, buildPdf: () => purchaseOrderPdf(po, _warehouses[po.warehouseId]), fileName: '${po.number}.pdf');
      case 'edit':
        _edit(po);
      case 'receive':
        _receive(po);
      case 'cancel':
        final ok = await showDialog<bool>(
          context: context,
          builder: (d) => AlertDialog(
            title: Text(po.nothingReceived ? 'Cancel ${po.number}?' : 'Close ${po.number}?', style: CrmTokens.display(size: 17)),
            content: Text(
                po.nothingReceived
                    ? 'The supplier order is cancelled. Nothing was received, so stock and payables don\'t change.'
                    : 'Goods already received stay. The rest is no longer expected.',
                style: CrmTokens.body()),
            actions: [
              TextButton(onPressed: () => Navigator.pop(d, false), child: Text('Back', style: CrmTokens.body())),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: CrmTokens.red, elevation: 0),
                onPressed: () => Navigator.pop(d, true),
                child: Text(po.nothingReceived ? 'Cancel order' : 'Close order',
                    style: CrmTokens.body(color: Colors.white, w: FontWeight.w600)),
              ),
            ],
          ),
        );
        if (ok != true) return;
        try {
          await cancelPurchaseOrder(po.id);
          _load();
        } catch (_) {
          if (mounted) crmSnack(context, "Couldn't save. Check your connection.", error: true);
        }
    }
  }
}

// -----------------------------------------------------------------------------
// Form
// -----------------------------------------------------------------------------

class _Line {
  StockProduct? product;
  String typed = '';
  final qty = TextEditingController();
  final cost = TextEditingController();
  num get qtyValue => num.tryParse(qty.text.trim()) ?? 0;
  num get costValue => num.tryParse(cost.text.trim()) ?? 0;
  void dispose() {
    qty.dispose();
    cost.dispose();
  }
}

class PurchaseOrderFormScreen extends StatefulWidget {
  final PurchaseOrder? order; // editing
  final Quotation? quotation; // ordering from a quotation
  final List<QuoteLine>? quoteLines;
  const PurchaseOrderFormScreen({super.key, this.order, this.quotation, this.quoteLines});

  @override
  State<PurchaseOrderFormScreen> createState() => _PurchaseOrderFormScreenState();
}

class _PurchaseOrderFormScreenState extends State<PurchaseOrderFormScreen> {
  List<Supplier>? _suppliers;
  ProductIndex? _products;
  List<Warehouse> _warehouses = const [];
  Object? _error;
  String? _supplierId;
  String _warehouseId = mainWarehouseId;
  DateTime _date = DateTime.now();
  DateTime? _expected;
  final _note = TextEditingController();
  final List<_Line> _lines = [_Line()];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final po = widget.order;
    _supplierId = po?.supplierId ?? widget.quotation?.supplierId;
    if (po != null) {
      _warehouseId = po.warehouseId;
      _date = po.date;
      _expected = po.expected;
      _note.text = po.note;
    } else if (widget.quotation != null && widget.quotation!.ref.isNotEmpty) {
      _note.text = 'From quotation ${widget.quotation!.ref}';
    }
    _load();
  }

  @override
  void dispose() {
    _note.dispose();
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final r = await Future.wait<Object>(
          [loadSuppliers(activeOnly: true), loadProductIndex(fresh: true), loadWarehouses(activeOnly: true, fresh: true)]);
      if (!mounted) return;
      final suppliers = r[0] as List<Supplier>;
      final products = r[1] as ProductIndex;
      final byId = {for (final p in products.all) p.id: p};
      setState(() {
        final keepId = widget.order?.supplierId ?? widget.quotation?.supplierId;
        final keepName = widget.order?.supplierName ?? widget.quotation?.supplierName ?? '';
        _suppliers = [
          ...suppliers,
          if (keepId != null && !suppliers.any((s) => s.id == keepId)) Supplier(id: keepId, name: keepName),
        ];
        _products = products;
        _warehouses = r[2] as List<Warehouse>;
        final seed = widget.order?.lines.map((l) => (l.productId, l.productName, l.qty, l.unitCost)) ??
            (widget.quoteLines ?? widget.quotation?.lines)?.map((l) => (l.productId, l.productName, l.minQty, l.unitCost));
        if (seed != null && seed.isNotEmpty) {
          for (final l in _lines) {
            l.dispose();
          }
          _lines
            ..clear()
            ..addAll([
              for (final (id, name, qty, cost) in seed)
                _Line()
                  ..product = byId[id] ?? products.byName(name)
                  ..typed = name
                  ..qty.text = qty > 0 ? _plain(qty) : ''
                  ..cost.text = cost > 0 ? _plain(cost) : '',
            ]);
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  num get _total => _lines.fold<num>(0, (s, l) => s + l.qtyValue * l.costValue);

  Future<void> _save() async {
    final supplier = _suppliers?.where((s) => s.id == _supplierId).firstOrNull;
    if (supplier == null) return crmSnack(context, 'Choose the supplier', error: true);
    final lines = <PoLine>[];
    final seen = <String>{};
    for (final l in _lines) {
      if (l.product == null && l.typed.trim().isEmpty && l.qtyValue == 0) continue;
      final p = l.product;
      if (p == null) {
        return crmSnack(context,
            l.typed.trim().isEmpty ? 'Choose a product on every line' : '"${l.typed.trim()}" isn\'t in your product list.',
            error: true);
      }
      if (l.qtyValue <= 0) return crmSnack(context, 'Enter a quantity for ${p.name}', error: true);
      if (!seen.add(p.id)) return crmSnack(context, '${p.name} is on two lines. Keep one.', error: true);
      lines.add(PoLine(productId: p.id, productName: p.name, qty: l.qtyValue, unitCost: l.costValue));
    }
    if (lines.isEmpty) return crmSnack(context, 'Add at least one product', error: true);
    setState(() => _saving = true);
    try {
      final old = widget.order;
      await savePurchaseOrder(PurchaseOrder(
        id: old?.id ?? '',
        number: old?.number ?? '',
        supplierId: supplier.id,
        supplierName: supplier.name,
        date: _date,
        expected: _expected,
        warehouseId: _warehouseId,
        lines: lines,
        note: _note.text.trim(),
        quotationId: widget.quotation?.id ?? old?.quotationId ?? '',
      ));
      if (!mounted) return;
      crmSnack(context, old == null ? 'Purchase order saved. Print or share it with the supplier from the list.' : 'Saved');
      Navigator.pop(context, true);
    } catch (e) {
      debugPrint('Saving PO failed: $e');
      if (!mounted) return;
      setState(() => _saving = false);
      crmSnack(context, "Couldn't save. Check your connection and try again.", error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (_error != null) {
      body = Center(
        child: OutlinedButton(onPressed: _load, child: Text('Try again', style: CrmTokens.body(color: CrmTokens.navy))),
      );
    } else if (_suppliers == null || _products == null) {
      body = const Center(child: CircularProgressIndicator(color: CrmTokens.navy));
    } else {
      body = _form();
    }
    return Scaffold(
      backgroundColor: CrmTokens.bg,
      appBar: AppBar(
        backgroundColor: CrmTokens.navy,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(widget.order == null ? 'New purchase order' : 'Edit ${widget.order!.number}',
            style: CrmTokens.display(size: 18, color: Colors.white, w: FontWeight.w600)),
      ),
      body: body,
    );
  }

  Future<DateTime?> _pick(DateTime? initial, {DateTime? first, DateTime? last}) => showDatePicker(
        context: context,
        initialDate: initial ?? DateTime.now(),
        firstDate: first ?? DateTime(2023),
        lastDate: last ?? DateTime(DateTime.now().year + 2),
      );

  Widget _form() {
    final suppliers = _suppliers!;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 40),
          children: [
            Text('What you\'re ordering from a supplier. Stock and what you owe only change when you receive the goods.',
                style: CrmTokens.body(color: CrmTokens.muted)),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _supplierId,
              isExpanded: true,
              decoration: crmInput('Supplier', icon: Icons.local_shipping_outlined),
              items: [
                for (final s in suppliers)
                  DropdownMenuItem(value: s.id, child: Text(s.name, style: CrmTokens.body(), overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => setState(() => _supplierId = v),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: InkWell(
                  onTap: () async {
                    final d = await _pick(_date, last: DateTime.now());
                    if (d != null) setState(() => _date = d);
                  },
                  child: InputDecorator(
                    decoration: crmInput('Order date', icon: Icons.calendar_today_outlined),
                    child: Text(crmDay.format(_date), style: CrmTokens.body()),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: InkWell(
                  onTap: () async {
                    final d = await _pick(_expected ?? _date.add(const Duration(days: 3)), first: _date);
                    if (d != null) setState(() => _expected = d);
                  },
                  child: InputDecorator(
                    decoration: crmInput('Expected delivery', icon: Icons.local_shipping_outlined),
                    child: Text(_expected == null ? 'Not set' : crmDay.format(_expected!),
                        style: CrmTokens.body(color: _expected == null ? CrmTokens.muted : CrmTokens.textDark)),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _warehouses.any((w) => w.id == _warehouseId) ? _warehouseId : mainWarehouseId,
              isExpanded: true,
              decoration: crmInput('Deliver to warehouse', icon: Icons.warehouse_outlined),
              items: [for (final w in _warehouses) DropdownMenuItem(value: w.id, child: Text(w.name, style: CrmTokens.body()))],
              onChanged: (v) => setState(() => _warehouseId = v ?? mainWarehouseId),
            ),
            CrmSectionTitle('Products', trailing: Text(crmRs(_total), style: CrmTokens.body(w: FontWeight.w700))),
            for (final l in _lines) _lineCard(l),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => _lines.add(_Line())),
                icon: const Icon(Icons.add, color: CrmTokens.navy),
                label: Text('Add product', style: CrmTokens.body(color: CrmTokens.navy, w: FontWeight.w600)),
              ),
            ),
            const SizedBox(height: 8),
            TextField(controller: _note, style: CrmTokens.body(), maxLines: 2, decoration: crmInput('Note for the supplier (optional)')),
            const SizedBox(height: 18),
            SizedBox(
              height: 48,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: CrmTokens.amber, elevation: 0),
                onPressed: _saving || suppliers.isEmpty ? null : _save,
                icon: const Icon(Icons.check, color: CrmTokens.navyDark),
                label: Text('Save purchase order', style: CrmTokens.body(size: 14, color: CrmTokens.navyDark, w: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _lineCard(_Line line) {
    final products = _products!;
    final p = line.product;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: CrmCard(
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Autocomplete<StockProduct>(
                key: ObjectKey(line),
                initialValue: TextEditingValue(text: line.typed),
                displayStringForOption: (o) => o.name,
                optionsBuilder: (v) {
                  final q = v.text.trim().toLowerCase();
                  if (q.isEmpty) return const Iterable.empty();
                  return products.all.where((x) => x.active && x.name.toLowerCase().contains(q)).take(20);
                },
                onSelected: (o) => _setProduct(line, o, o.name),
                fieldViewBuilder: (context, c, focus, onSubmit) => TextField(
                  controller: c,
                  focusNode: focus,
                  onChanged: (v) => _setProduct(line, products.byName(v), v),
                  style: CrmTokens.body(),
                  decoration: crmInput('Product', icon: Icons.inventory_2_outlined, hint: 'Type to search'),
                ),
              ),
            ),
            if (_lines.length > 1)
              IconButton(
                  icon: const Icon(Icons.close, color: CrmTokens.muted), onPressed: () => setState(() => _lines.remove(line))),
          ]),
          if (p != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
              child: Text(
                'In stock: ${p.stock == null ? '—' : _plain(p.onHand)}'
                '${p.reorderLevel > 0 ? '  ·  reorder at ${_plain(p.reorderLevel)}' : ''}'
                '  ·  last cost ${p.costPrice > 0 ? crmRs(p.costPrice) : '—'}',
                style: CrmTokens.body(size: 11.5, color: p.isLow ? CrmTokens.red : CrmTokens.muted),
              ),
            ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextField(
                controller: line.qty,
                onChanged: (_) => setState(() {}),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: CrmTokens.body(),
                decoration: crmInput('Quantity'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: line.cost,
                onChanged: (_) => setState(() {}),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: CrmTokens.body(),
                decoration: crmInput('Agreed price per unit (Rs.)'),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 110,
              child: Text(crmRs(line.qtyValue * line.costValue),
                  textAlign: TextAlign.right, style: CrmTokens.body(w: FontWeight.w700)),
            ),
          ]),
        ]),
      ),
    );
  }

  void _setProduct(_Line line, StockProduct? o, String typed) {
    line.typed = typed;
    if (o?.id == line.product?.id) return;
    setState(() {
      line.product = o;
      if (o != null && line.cost.text.trim().isEmpty && o.costPrice > 0) line.cost.text = _plain(o.costPrice);
    });
  }
}

// -----------------------------------------------------------------------------
// PDF for the supplier
// -----------------------------------------------------------------------------

Future<Uint8List> purchaseOrderPdf(PurchaseOrder po, String? warehouseName) async {
  final money = NumberFormat('#,##0.##');
  final day = DateFormat('dd MMM yyyy');
  final doc = pw.Document();
  pw.Widget cell(String t, {bool bold = false, pw.TextAlign align = pw.TextAlign.left}) => pw.Padding(
        padding: const pw.EdgeInsets.all(5),
        child: pw.Text(t, textAlign: align, style: pw.TextStyle(fontSize: 10, fontWeight: bold ? pw.FontWeight.bold : null)),
      );
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(32),
    build: (_) => [
      pw.Center(child: pw.Text(Account.companyName, style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold))),
      pw.SizedBox(height: 4),
      pw.Center(child: pw.Text('PURCHASE ORDER', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold))),
      pw.SizedBox(height: 14),
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Expanded(
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('To:', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
            pw.Text(po.supplierName, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
          ]),
        ),
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
          pw.Text('PO no.: ${po.number}', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
          pw.Text('Date: ${day.format(po.date)}', style: const pw.TextStyle(fontSize: 10)),
          if (po.expected != null) pw.Text('Deliver by: ${day.format(po.expected!)}', style: const pw.TextStyle(fontSize: 10)),
          if (warehouseName != null) pw.Text('Deliver to: $warehouseName', style: const pw.TextStyle(fontSize: 10)),
        ]),
      ]),
      pw.SizedBox(height: 14),
      pw.Table(
        border: pw.TableBorder.all(color: PdfColors.grey500, width: 0.6),
        columnWidths: const {
          0: pw.FixedColumnWidth(28),
          1: pw.FlexColumnWidth(4),
          2: pw.FlexColumnWidth(1.2),
          3: pw.FlexColumnWidth(1.4),
          4: pw.FlexColumnWidth(1.6),
        },
        children: [
          pw.TableRow(decoration: const pw.BoxDecoration(color: PdfColors.grey200), children: [
            cell('#', bold: true),
            cell('Product', bold: true),
            cell('Qty', bold: true, align: pw.TextAlign.right),
            cell('Rate', bold: true, align: pw.TextAlign.right),
            cell('Amount', bold: true, align: pw.TextAlign.right),
          ]),
          for (var i = 0; i < po.lines.length; i++)
            pw.TableRow(children: [
              cell('${i + 1}'),
              cell(po.lines[i].productName),
              cell(money.format(po.lines[i].qty), align: pw.TextAlign.right),
              cell(po.lines[i].unitCost > 0 ? money.format(po.lines[i].unitCost) : '-', align: pw.TextAlign.right),
              cell(po.lines[i].amount > 0 ? money.format(po.lines[i].amount) : '-', align: pw.TextAlign.right),
            ]),
        ],
      ),
      pw.SizedBox(height: 8),
      pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text('TOTAL: Rs. ${money.format(po.total)}', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
      ),
      if (po.note.isNotEmpty) ...[pw.SizedBox(height: 12), pw.Text('Note: ${po.note}', style: const pw.TextStyle(fontSize: 10))],
      pw.SizedBox(height: 40),
      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, children: [
        pw.Text('Authorised by: ____________________', style: const pw.TextStyle(fontSize: 10)),
      ]),
    ],
  ));
  return doc.save();
}
