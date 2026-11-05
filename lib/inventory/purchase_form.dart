// Entering a supplier bill (goods in) or a purchase return (goods sent back).
import 'package:flutter/material.dart';

import '../crm/crm_ui.dart';
import 'inventory_data.dart';
import 'quotations_data.dart';

class PurchaseFormScreen extends StatefulWidget {
  final bool isReturn;
  final Supplier? supplier; // preselected when opened from a supplier's ledger or a quotation
  // Opened from a quotation: its products and prices fill the lines, and the quotation is marked
  // as bought once the bill is saved.
  final Quotation? quotation;
  final List<QuoteLine>? quoteLines; // which of its lines (all when null)
  const PurchaseFormScreen({super.key, this.isReturn = false, this.supplier, this.quotation, this.quoteLines});

  @override
  State<PurchaseFormScreen> createState() => _PurchaseFormScreenState();
}

class _Line {
  StockProduct? product;
  String typed = ''; // what's in the product box, picked or typed
  final qty = TextEditingController();
  final cost = TextEditingController();
  final markup = TextEditingController(); // profit % for products whose TP follows the cost

  num get qtyValue => num.tryParse(qty.text.trim()) ?? 0;
  num get costValue => num.tryParse(cost.text.trim()) ?? 0;
  num get amount => qtyValue * costValue;
  num get markupValue => num.tryParse(markup.text.trim()) ?? product?.markupPct ?? 0;

  void dispose() {
    qty.dispose();
    cost.dispose();
    markup.dispose();
  }
}

class _PurchaseFormScreenState extends State<PurchaseFormScreen> {
  List<Supplier>? _suppliers;
  List<Warehouse> _warehouses = const [];
  String _warehouseId = mainWarehouseId;
  ProductIndex? _products;
  Object? _error;
  String? _supplierId;
  final _billNo = TextEditingController();
  final _discount = TextEditingController();
  final _paid = TextEditingController();
  final _note = TextEditingController();
  DateTime _date = DateTime.now();
  String _method = 'Cash';
  final List<_Line> _lines = [_Line()];
  bool _saving = false;
  bool _tracking = true; // false: an existing business that hasn't set up its opening stock yet

  @override
  void initState() {
    super.initState();
    _supplierId = widget.supplier?.id ?? widget.quotation?.supplierId;
    _load();
  }

  @override
  void dispose() {
    for (final c in [_billNo, _discount, _paid, _note]) {
      c.dispose();
    }
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      // A company that hasn't sold yet starts tracking stock here, so this bill adds stock.
      DateTime? tracking;
      try {
        tracking = await ensureStockTracking();
      } catch (_) {}
      // Inactive suppliers aren't offered, except the one this form was opened for.
      final results = await Future.wait<Object>(
          [loadSuppliers(activeOnly: true), loadProductIndex(fresh: true), loadWarehouses(activeOnly: true, fresh: true)]);
      if (!mounted) return;
      setState(() {
        _tracking = tracking != null;
        final pre = widget.supplier;
        _suppliers = [
          ...results[0] as List<Supplier>,
          if (pre != null && !(results[0] as List<Supplier>).any((s) => s.id == pre.id)) pre,
          if (widget.quotation case final q? when !(results[0] as List<Supplier>).any((s) => s.id == q.supplierId))
            Supplier(id: q.supplierId, name: q.supplierName),
        ];
        _products = results[1] as ProductIndex;
        _warehouses = results[2] as List<Warehouse>;
        _fillFromQuotation();
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  /// Lines from the quotation this form was opened from: product and price, quantity to fill in.
  void _fillFromQuotation() {
    final q = widget.quotation;
    if (q == null || _products == null) return;
    final byId = {for (final p in _products!.all) p.id: p};
    final filled = <_Line>[];
    for (final ql in widget.quoteLines ?? q.lines) {
      final p = byId[ql.productId] ?? _products!.byName(ql.productName);
      final line = _Line()
        ..product = p
        ..typed = p?.name ?? ql.productName;
      line.cost.text = _plain(ql.unitCost);
      if (ql.minQty > 0) line.qty.text = _plain(ql.minQty);
      if (p != null && !p.fixedTp) line.markup.text = _plain(p.markupPct);
      filled.add(line);
    }
    if (filled.isEmpty) return;
    for (final l in _lines) {
      l.dispose();
    }
    _lines
      ..clear()
      ..addAll(filled);
    if (_billNo.text.isEmpty && q.ref.isNotEmpty) _note.text = 'From quotation ${q.ref}';
  }

  static String _plain(num v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : '$v';

  String get _warehouseName => _warehouses.where((w) => w.id == _warehouseId).firstOrNull?.name ?? 'Main warehouse';

  num get _subtotal => _lines.fold<num>(0, (s, l) => s + l.amount);
  num get _discountValue => num.tryParse(_discount.text.trim()) ?? 0;
  num get _total => _subtotal - _discountValue;

  Future<void> _pickDate() async {
    final d = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime(2023), lastDate: DateTime.now());
    if (d != null) setState(() => _date = d);
  }

  Future<void> _save() async {
    final supplier = _suppliers?.where((s) => s.id == _supplierId).firstOrNull;
    if (supplier == null) return crmSnack(context, 'Choose a supplier', error: true);
    final lines = <PurchaseLine>[];
    for (final l in _lines) {
      if (l.product == null && l.typed.trim().isEmpty && l.qtyValue == 0) continue; // empty row
      if (l.product == null) {
        return crmSnack(
            context,
            l.typed.trim().isEmpty
                ? 'Choose a product on every line'
                : '"${l.typed.trim()}" isn\'t in your product list. Pick it from the suggestions, or add it in Products first.',
            error: true);
      }
      if (!widget.isReturn && !l.product!.active) {
        return crmSnack(context, '${l.product!.name} is switched off. Turn it back on in Products to buy it.', error: true);
      }
      if (l.qtyValue <= 0) return crmSnack(context, 'Enter a quantity for ${l.product!.name}', error: true);
      if (l.costValue < 0) return crmSnack(context, 'Cost for ${l.product!.name} can\'t be negative', error: true);
      final p = l.product!;
      // Profit % products: this bill's cost sets the TP. Free goods (cost 0) leave the TP alone.
      final setsTp = !widget.isReturn && !p.fixedTp && l.costValue > 0;
      if (setsTp && (num.tryParse(l.markup.text.trim()) ?? -1) < 0) {
        return crmSnack(context, 'Enter the profit % for ${p.name}', error: true);
      }
      lines.add(PurchaseLine(
        productId: p.id,
        productName: p.name,
        qty: l.qtyValue,
        unitCost: l.costValue,
        newTp: setsTp ? tpFromCost(l.costValue, l.markupValue) : null,
        markupPct: setsTp ? l.markupValue : null,
      ));
    }
    if (lines.isEmpty) return crmSnack(context, 'Add at least one product', error: true);
    if (widget.isReturn) {
      for (final l in lines) {
        final onHand = _products?.byName(l.productName)?.inWarehouse(_warehouseId) ?? 0;
        if (l.qty > onHand) {
          return crmSnack(context, "Can't return ${l.qty} of ${l.productName}: only $onHand in ${_warehouseName}", error: true);
        }
      }
    }

    if (!widget.isReturn && supplier.creditLimit > 0 && !await _withinCreditLimit(supplier, lines)) return;

    setState(() => _saving = true);
    try {
      final purchaseId = await savePurchase(
        Purchase(
          isReturn: widget.isReturn,
          supplierId: supplier.id,
          supplierName: supplier.name,
          billNo: _billNo.text.trim(),
          date: _date,
          lines: lines,
          discount: _discountValue,
          note: _note.text.trim(),
          warehouseId: _warehouseId,
        ),
        paidNow: widget.isReturn ? 0 : (num.tryParse(_paid.text.trim()) ?? 0),
        method: _method,
      );
      final q = widget.quotation;
      if (q != null && !widget.isReturn) {
        // The bill is saved either way; the quotation only gets its "bought" mark.
        await markQuotationUsed(q.id, purchaseId).catchError((Object e) => debugPrint('Marking quotation failed: $e'));
      }
      if (!mounted) return;
      crmSnack(context, widget.isReturn ? 'Return saved. Stock reduced.' : 'Purchase saved. Stock added.');
      Navigator.pop(context, true);
    } catch (e) {
      debugPrint('Saving purchase failed: $e');
      if (!mounted) return;
      setState(() => _saving = false);
      crmSnack(context, "Couldn't save. Check your connection and try again.", error: true);
    }
  }

  /// Warns when this bill would take what we owe the supplier past their credit limit.
  /// Returns false if the admin goes back.
  Future<bool> _withinCreditLimit(Supplier supplier, List<PurchaseLine> lines) async {
    final num balance;
    try {
      balance = (await loadPayables()).balanceOf(supplier.id);
    } catch (_) {
      return true; // can't check right now; don't block the bill
    }
    final bill = lines.fold<num>(0, (s, l) => s + l.amount) - _discountValue - (num.tryParse(_paid.text.trim()) ?? 0);
    if (balance + bill <= supplier.creditLimit || !mounted) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('Over the credit limit', style: CrmTokens.display(size: 17)),
        content: Text(
          'You owe ${supplier.name} ${crmRs(balance)}. With this bill it becomes ${crmRs(balance + bill)}, over their '
          'credit limit of ${crmRs(supplier.creditLimit)}.\n\nSave the bill anyway?',
          style: CrmTokens.body(),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: Text('Go back', style: CrmTokens.body())),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: CrmTokens.amber, elevation: 0),
            onPressed: () => Navigator.pop(d, true),
            child: Text('Save anyway', style: CrmTokens.body(w: FontWeight.w700, color: CrmTokens.navyDark)),
          ),
        ],
      ),
    );
    return ok == true;
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.isReturn ? 'Return to supplier' : 'New purchase';
    Widget body;
    if (_error != null) {
      body = Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const CrmEmpty(icon: Icons.cloud_off, text: "Couldn't load suppliers and products."),
          OutlinedButton(onPressed: _load, child: Text('Try again', style: CrmTokens.body(color: CrmTokens.navy))),
        ]),
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
        title: Text(title, style: CrmTokens.display(size: 18, color: Colors.white, w: FontWeight.w600)),
      ),
      body: body,
    );
  }

  Widget _form() {
    final suppliers = _suppliers!;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 40),
          children: [
            if (widget.isReturn)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text('Goods going back to the supplier. Stock goes down and so does what you owe them.',
                    style: CrmTokens.body(color: CrmTokens.muted)),
              ),
            if (!_tracking)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: CrmTokens.amberBg, borderRadius: BorderRadius.circular(10)),
                child: Text(
                  'Stock isn\'t tracked yet, so this bill is recorded but doesn\'t add stock now. Set up stock in '
                  'Manage Stock: bills saved before that are added to the opening count.',
                  style: CrmTokens.body(color: CrmTokens.textDark),
                ),
              ),
            if (suppliers.isEmpty)
              const CrmEmpty(icon: Icons.local_shipping_outlined, text: 'No suppliers yet. Add one from Add Supplier first.')
            else
              DropdownButtonFormField<String>(
                initialValue: _supplierId,
                isExpanded: true,
                decoration: crmInput('Supplier', icon: Icons.local_shipping_outlined),
                items: [
                  for (final s in suppliers)
                    DropdownMenuItem(value: s.id, child: Text(s.display, style: CrmTokens.body(), overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => setState(() => _supplierId = v),
              ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _billNo,
                  style: CrmTokens.body(),
                  decoration: crmInput(widget.isReturn ? 'Return / debit note no.' : 'Supplier bill no.', icon: Icons.tag),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: InkWell(
                  onTap: _pickDate,
                  child: InputDecorator(
                    decoration: crmInput('Date', icon: Icons.calendar_today_outlined),
                    child: Text(crmDay.format(_date), style: CrmTokens.body()),
                  ),
                ),
              ),
            ]),
            // Always shown, so it's clear where the goods go (with one warehouse it's the only choice).
            if (_warehouses.isNotEmpty) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _warehouseId,
                isExpanded: true,
                decoration: crmInput(widget.isReturn ? 'Goods leave from warehouse' : 'Goods go into warehouse',
                    icon: Icons.warehouse_outlined),
                items: [for (final w in _warehouses) DropdownMenuItem(value: w.id, child: Text(w.name, style: CrmTokens.body()))],
                onChanged: (v) => setState(() => _warehouseId = v ?? mainWarehouseId),
              ),
            ],
            CrmSectionTitle('Products', trailing: Text('${_lines.length} line${_lines.length == 1 ? '' : 's'}',
                style: CrmTokens.body(size: 12, color: CrmTokens.muted))),
            for (var i = 0; i < _lines.length; i++) _lineCard(i),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => _lines.add(_Line())),
                icon: const Icon(Icons.add, color: CrmTokens.navy),
                label: Text('Add product', style: CrmTokens.body(color: CrmTokens.navy, w: FontWeight.w600)),
              ),
            ),
            const SizedBox(height: 8),
            CrmCard(
              child: Column(children: [
                _sumRow('Subtotal', crmRs(_subtotal)),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: Text('Discount', style: CrmTokens.body(color: CrmTokens.muted))),
                  SizedBox(
                    width: 160,
                    child: TextField(
                      controller: _discount,
                      onChanged: (_) => setState(() {}),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: CrmTokens.body(),
                      decoration: crmInput('Rs.'),
                    ),
                  ),
                ]),
                const Divider(height: 22),
                _sumRow(widget.isReturn ? 'Credit from supplier' : 'Bill total', crmRs(_total), bold: true),
                if (!widget.isReturn) ...[
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: _paid,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        style: CrmTokens.body(),
                        decoration: crmInput('Paid now (optional)', icon: Icons.payments_outlined),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 150,
                      child: DropdownButtonFormField<String>(
                        initialValue: _method,
                        decoration: crmInput('Method'),
                        items: [
                          for (final m in paymentMethods) DropdownMenuItem(value: m, child: Text(m, style: CrmTokens.body())),
                        ],
                        onChanged: (v) => setState(() => _method = v ?? 'Cash'),
                      ),
                    ),
                  ]),
                ],
              ]),
            ),
            const SizedBox(height: 12),
            TextField(controller: _note, style: CrmTokens.body(), maxLines: 2, decoration: crmInput('Note (optional)')),
            const SizedBox(height: 18),
            SizedBox(
              height: 48,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: CrmTokens.amber,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: _saving || suppliers.isEmpty ? null : _save,
                icon: _saving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: CrmTokens.navyDark))
                    : Icon(widget.isReturn ? Icons.assignment_return_outlined : Icons.inventory_2_outlined, color: CrmTokens.navyDark),
                label: Text(widget.isReturn ? 'Save return (stock out)' : 'Save purchase (stock in)',
                    style: CrmTokens.body(size: 14, color: CrmTokens.navyDark, w: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sumRow(String label, String value, {bool bold = false}) => Row(children: [
        Expanded(child: Text(label, style: CrmTokens.body(color: bold ? CrmTokens.textDark : CrmTokens.muted, w: bold ? FontWeight.w700 : FontWeight.w400))),
        Text(value, style: bold ? CrmTokens.display(size: 16, color: CrmTokens.navy) : CrmTokens.body(w: FontWeight.w600)),
      ]);

  void _setProduct(_Line line, StockProduct? o, String typed) {
    line.typed = typed;
    if (o?.id == line.product?.id) return;
    setState(() {
      line.product = o;
      if (o != null && line.cost.text.trim().isEmpty && o.costPrice > 0) line.cost.text = _plain(o.costPrice);
      if (o != null && !o.fixedTp && line.markup.text.trim().isEmpty) line.markup.text = _plain(o.markupPct);
    });
  }

  Widget _lineCard(int i) {
    final line = _lines[i];
    final products = _products!;
    final p = line.product;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: CrmCard(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Autocomplete<StockProduct>(
                  key: ObjectKey(line),
                  initialValue: TextEditingValue(text: p?.name ?? ''),
                  displayStringForOption: (o) => o.name,
                  optionsBuilder: (v) {
                    final q = v.text.trim().toLowerCase();
                    if (q.isEmpty) return const Iterable.empty();
                    return products.all.where((x) => (x.active || widget.isReturn) && x.name.toLowerCase().contains(q)).take(20);
                  },
                  onSelected: (o) => _setProduct(line, o, o.name),
                  fieldViewBuilder: (context, c, focus, onSubmit) => TextField(
                    controller: c,
                    focusNode: focus,
                    // A name typed out in full counts the same as picking it from the list.
                    onChanged: (v) => _setProduct(line, products.byName(v), v),
                    style: CrmTokens.body(),
                    decoration: crmInput('Product', icon: Icons.inventory_2_outlined, hint: 'Type to search'),
                  ),
                ),
              ),
              if (_lines.length > 1)
                IconButton(
                  tooltip: 'Remove line',
                  onPressed: () => setState(() => _lines.removeAt(i).dispose()),
                  icon: const Icon(Icons.close, color: CrmTokens.muted),
                ),
            ]),
            if (p != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
                child: Text(
                  'In stock: ${p.stock == null ? '—' : p.inWarehouse(_warehouseId)}'
                  '${_warehouses.length > 1 ? ' in $_warehouseName' : ''}   ·   Sells at ${crmRs(p.salePrice)}   ·   Last cost ${p.costPrice > 0 ? crmRs(p.costPrice) : '—'}',
                  style: CrmTokens.body(size: 11.5, color: CrmTokens.muted),
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
                  decoration: crmInput('Quantity (units)'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: line.cost,
                  onChanged: (_) => setState(() {}),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: CrmTokens.body(),
                  decoration: crmInput('Cost per unit (Rs.)'),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 120,
                child: Text(crmRs(line.amount), textAlign: TextAlign.right, style: CrmTokens.body(w: FontWeight.w700)),
              ),
            ]),
            if (p != null && !widget.isReturn) _pricing(line, p),
          ],
        ),
      ),
    );
  }

  /// Under each line: where the cost came from, and what bookers will sell at after this bill.
  Widget _pricing(_Line line, StockProduct p) {
    final cost = line.costValue;
    final unit = p.size.isEmpty ? 'unit' : p.size.toLowerCase();
    String rs(num v) => 'Rs. ${_plain(v)}';
    Widget note(String text, Color color, {IconData? icon}) => Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon ?? Icons.info_outline, size: 15, color: color),
            const SizedBox(width: 6),
            Expanded(child: Text(text, style: CrmTokens.body(size: 12, color: color, w: FontWeight.w500))),
          ]),
        );

    final costNote = cost <= 0
        ? note('No cost: free goods. The product\'s cost and TP stay as they are.', CrmTokens.muted)
        : p.costPrice <= 0
            ? note('First purchase: ${rs(cost)} becomes this product\'s cost.', CrmTokens.muted)
            : cost == p.costPrice
                ? note('Same cost as last time (${rs(cost)}).', CrmTokens.muted)
                : note('Product cost changes from ${rs(p.costPrice)} to ${rs(cost)}.', CrmTokens.amber,
                    icon: Icons.swap_horiz);

    Widget tpNote;
    if (cost <= 0) {
      tpNote = const SizedBox.shrink();
    } else if (p.fixedTp) {
      final profit = p.salePrice - cost;
      tpNote = p.salePrice <= 0
          ? note('Fixed TP not set yet. Set it in Products before bookers can sell this.', CrmTokens.red)
          : note(
              'Fixed TP ${rs(p.salePrice)}  ·  ${profit > 0 ? 'profit' : 'loss'} ${rs(profit.abs())} per $unit'
              ' (${(profit / cost * 100).toStringAsFixed(1)}%)',
              profit > 0 ? CrmTokens.green : CrmTokens.red,
              icon: profit > 0 ? Icons.trending_up : Icons.trending_down);
    } else {
      final newTp = tpFromCost(cost, line.markupValue);
      final old = p.salePrice;
      final lower = old > 0 && newTp < old;
      final text = old <= 0 || old == newTp
          ? 'Bookers will sell at ${rs(newTp)}  ·  profit ${rs(newTp - cost)} per $unit'
          : 'TP changes from ${rs(old)} to ${rs(newTp)}'
              '${lower && p.onHand > 0 && p.costPrice > cost ? '. The ${_plain(p.onHand)} already in stock cost ${rs(p.costPrice)} each.' : ''}';
      tpNote = Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(children: [
          SizedBox(
            width: 120,
            child: TextField(
              controller: line.markup,
              onChanged: (_) => setState(() {}),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: CrmTokens.body(),
              decoration: crmInput('Profit %'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: CrmTokens.body(size: 12, color: lower ? CrmTokens.amber : CrmTokens.green, w: FontWeight.w600)),
          ),
        ]),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [costNote, tpNote]);
  }
}

const paymentMethods = ['Cash', 'Bank transfer', 'Cheque', 'Other'];
