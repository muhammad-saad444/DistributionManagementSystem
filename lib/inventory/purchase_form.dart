// Entering a supplier bill (goods in) or a purchase return (goods sent back).
import 'package:flutter/material.dart';

import '../crm/crm_ui.dart';
import 'inventory_data.dart';

class PurchaseFormScreen extends StatefulWidget {
  final bool isReturn;
  final Supplier? supplier; // preselected when opened from a supplier's ledger
  const PurchaseFormScreen({super.key, this.isReturn = false, this.supplier});

  @override
  State<PurchaseFormScreen> createState() => _PurchaseFormScreenState();
}

class _Line {
  StockProduct? product;
  final qty = TextEditingController();
  final cost = TextEditingController();

  num get qtyValue => num.tryParse(qty.text.trim()) ?? 0;
  num get costValue => num.tryParse(cost.text.trim()) ?? 0;
  num get amount => qtyValue * costValue;

  void dispose() {
    qty.dispose();
    cost.dispose();
  }
}

class _PurchaseFormScreenState extends State<PurchaseFormScreen> {
  List<Supplier>? _suppliers;
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

  @override
  void initState() {
    super.initState();
    _supplierId = widget.supplier?.id;
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
      // Inactive suppliers aren't offered, except the one this form was opened for.
      final results = await Future.wait<Object>([loadSuppliers(activeOnly: true), loadProductIndex(fresh: true)]);
      if (!mounted) return;
      setState(() {
        final pre = widget.supplier;
        _suppliers = [
          ...results[0] as List<Supplier>,
          if (pre != null && !(results[0] as List<Supplier>).any((s) => s.id == pre.id)) pre,
        ];
        _products = results[1] as ProductIndex;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

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
      if (l.product == null && l.qtyValue == 0) continue; // empty row
      if (l.product == null) return crmSnack(context, 'Choose a product on every line', error: true);
      if (l.qtyValue <= 0) return crmSnack(context, 'Enter a quantity for ${l.product!.name}', error: true);
      if (l.costValue < 0) return crmSnack(context, 'Cost for ${l.product!.name} can\'t be negative', error: true);
      lines.add(PurchaseLine(productId: l.product!.id, productName: l.product!.name, qty: l.qtyValue, unitCost: l.costValue));
    }
    if (lines.isEmpty) return crmSnack(context, 'Add at least one product', error: true);
    if (widget.isReturn) {
      for (final l in lines) {
        final onHand = _products?.byName(l.productName)?.onHand ?? 0;
        if (l.qty > onHand) {
          return crmSnack(context, "Can't return ${l.qty} of ${l.productName}: only $onHand in stock", error: true);
        }
      }
    }

    if (!widget.isReturn && supplier.creditLimit > 0 && !await _withinCreditLimit(supplier, lines)) return;

    setState(() => _saving = true);
    try {
      await savePurchase(
        Purchase(
          isReturn: widget.isReturn,
          supplierId: supplier.id,
          supplierName: supplier.name,
          billNo: _billNo.text.trim(),
          date: _date,
          lines: lines,
          discount: _discountValue,
          note: _note.text.trim(),
        ),
        paidNow: widget.isReturn ? 0 : (num.tryParse(_paid.text.trim()) ?? 0),
        method: _method,
      );
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
                  key: ValueKey('line-$i-${p?.id}'),
                  initialValue: TextEditingValue(text: p?.name ?? ''),
                  displayStringForOption: (o) => o.name,
                  optionsBuilder: (v) {
                    final q = v.text.trim().toLowerCase();
                    if (q.isEmpty) return const Iterable.empty();
                    return products.all.where((x) => x.name.toLowerCase().contains(q)).take(20);
                  },
                  onSelected: (o) => setState(() {
                    line.product = o;
                    if (line.cost.text.trim().isEmpty && o.costPrice > 0) line.cost.text = '${o.costPrice}';
                  }),
                  fieldViewBuilder: (context, c, focus, onSubmit) => TextField(
                    controller: c,
                    focusNode: focus,
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
                  'In stock: ${p.stock ?? '—'}   ·   Sells at ${crmRs(p.salePrice)}   ·   Last cost ${p.costPrice > 0 ? crmRs(p.costPrice) : '—'}',
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
            if (p != null && line.costValue > 0 && p.salePrice > 0 && line.costValue >= p.salePrice)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Cost is at or above the selling price (${crmRs(p.salePrice)}).',
                    style: CrmTokens.body(size: 11.5, color: CrmTokens.red)),
              ),
          ],
        ),
      ),
    );
  }
}

const paymentMethods = ['Cash', 'Bank transfer', 'Cheque', 'Other'];
