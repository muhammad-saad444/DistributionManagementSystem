// Supplier quotations: record what each supplier offers, compare prices per product, and buy from
// the best offer (which opens a purchase bill filled from the quotation).
import 'package:flutter/material.dart';

import '../crm/crm_ui.dart';
import 'inventory_data.dart';
import 'purchase_form.dart';
import '../orders/purchase_orders_screen.dart';
import 'quotations_data.dart';

String _plain(num v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : '$v';
String _rs(num v) => 'Rs. ${_plain(v)}';

/// The Quotations tab of Purchases.
class QuotationsTab extends StatefulWidget {
  final VoidCallback onPurchased; // a purchase was made from a quotation: bills need reloading
  const QuotationsTab({super.key, required this.onPurchased});

  @override
  State<QuotationsTab> createState() => _QuotationsTabState();
}

class _QuotationsTabState extends State<QuotationsTab> {
  List<Quotation>? _quotes;
  Map<String, StockProduct> _products = const {};
  Object? _error;
  bool _compare = true;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final results = await Future.wait<Object>([loadQuotations(), loadProductIndex()]);
      if (!mounted) return;
      setState(() {
        _quotes = results[0] as List<Quotation>;
        _products = {for (final p in (results[1] as ProductIndex).all) p.id: p};
      });
    } catch (e) {
      debugPrint('Quotations: loading failed: $e');
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _edit([Quotation? q]) async {
    final saved = await Navigator.push<bool>(
        context, MaterialPageRoute(builder: (_) => QuotationFormScreen(quotation: q)));
    if (saved == true) _load();
  }

  /// Orders from the supplier first (goods come later, then are received against the order).
  Future<void> _order(Quotation q, [List<QuoteLine>? lines]) async {
    final saved = await Navigator.push<bool>(
        context, MaterialPageRoute(builder: (_) => PurchaseOrderFormScreen(quotation: q, quoteLines: lines)));
    if (saved == true && mounted) crmSnack(context, 'See it in the Orders tab');
  }

  Future<void> _buy(Quotation q, [List<QuoteLine>? lines]) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => PurchaseFormScreen(quotation: q, quoteLines: lines)),
    );
    if (saved == true) {
      _load();
      widget.onPurchased();
    }
  }

  @override
  Widget build(BuildContext context) {
    final quotes = _quotes;
    if (quotes == null) {
      if (_error != null) {
        return Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const CrmEmpty(icon: Icons.cloud_off, text: "Couldn't load quotations. Check your connection."),
            OutlinedButton(onPressed: _load, child: Text('Try again', style: CrmTokens.body(color: CrmTokens.navy))),
          ]),
        );
      }
      return const Center(child: CircularProgressIndicator(color: CrmTokens.navy));
    }
    return RefreshIndicator(
      color: CrmTokens.navy,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 96),
        children: [
          Row(children: [
            Expanded(
              child: SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: true, label: Text('Compare prices'), icon: Icon(Icons.compare_arrows)),
                  ButtonSegment(value: false, label: Text('All quotations'), icon: Icon(Icons.request_quote_outlined)),
                ],
                selected: {_compare},
                onSelectionChanged: (v) => setState(() => _compare = v.first),
              ),
            ),
            const SizedBox(width: 10),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: CrmTokens.navy, elevation: 0),
              onPressed: () => _edit(),
              icon: const Icon(Icons.add, color: Colors.white, size: 18),
              label: Text('Quotation', style: CrmTokens.body(color: Colors.white, w: FontWeight.w600)),
            ),
          ]),
          const SizedBox(height: 12),
          if (quotes.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 40),
              child: CrmEmpty(
                icon: Icons.request_quote_outlined,
                text: 'No quotations yet. When suppliers send prices, add them here to compare and buy from the best one.',
              ),
            )
          else if (_compare)
            ..._compareView(quotes)
          else
            ..._listView(quotes),
        ],
      ),
    );
  }

  List<Widget> _compareView(List<Quotation> quotes) {
    final offers = compareOffers(quotes);
    final q = _search.trim().toLowerCase();
    final entries = offers.entries
        .map((e) => MapEntry(_products[e.key]?.name ?? e.value.first.line.productName, e))
        .where((e) => q.isEmpty || e.key.toLowerCase().contains(q))
        .toList()
      ..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));
    return [
      TextField(
        onChanged: (v) => setState(() => _search = v),
        style: CrmTokens.body(),
        decoration: crmInput('Search product', icon: Icons.search),
      ),
      const SizedBox(height: 10),
      if (offers.isEmpty)
        const CrmEmpty(icon: Icons.event_busy, text: 'Every quotation has expired. Add new ones to compare.')
      else if (entries.isEmpty)
        const CrmEmpty(icon: Icons.search_off, text: 'No quotations for that product.')
      else
        for (final e in entries) _productCard(e.key, e.value.value),
    ];
  }

  Widget _productCard(String name, List<QuoteOffer> offers) {
    final p = _products[offers.first.line.productId];
    final best = offers.first.line.unitCost;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: CrmCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(name, style: CrmTokens.display(size: 15))),
            if (p != null && p.costPrice > 0)
              Text('Last paid ${_rs(p.costPrice)}', style: CrmTokens.body(size: 12, color: CrmTokens.muted)),
          ]),
          const SizedBox(height: 8),
          for (var i = 0; i < offers.length; i++) _offerRow(offers[i], i == 0, offers[i].line.unitCost - best),
        ]),
      ),
    );
  }

  Widget _offerRow(QuoteOffer o, bool isBest, num moreThanBest) {
    final q = o.quotation;
    final sub = [
      if (q.ref.isNotEmpty) 'Quote ${q.ref}',
      crmDay.format(q.date),
      if (q.validUntil != null) 'valid till ${crmDay.format(q.validUntil!)}',
      if (o.line.minQty > 0) 'min ${_plain(o.line.minQty)}',
    ].join('  ·  ');
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
      decoration: BoxDecoration(
        color: isBest ? CrmTokens.greenBg : CrmTokens.bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(
                child: Text(q.supplierName,
                    style: CrmTokens.body(w: FontWeight.w600), overflow: TextOverflow.ellipsis),
              ),
              if (isBest) ...[
                const SizedBox(width: 6),
                const CrmPill('Best price', color: CrmTokens.green, background: Colors.white),
              ],
            ]),
            const SizedBox(height: 2),
            Text(sub, style: CrmTokens.body(size: 11.5, color: CrmTokens.muted)),
          ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(_rs(o.line.unitCost),
              style: CrmTokens.body(size: 14, w: FontWeight.w700, color: isBest ? CrmTokens.green : CrmTokens.textDark)),
          if (!isBest) Text('+${_rs(moreThanBest)}', style: CrmTokens.body(size: 11, color: CrmTokens.red)),
        ]),
        const SizedBox(width: 6),
        TextButton(
          onPressed: () => _order(q, [o.line]),
          child: Text('Order', style: CrmTokens.body(color: CrmTokens.navy, w: FontWeight.w600)),
        ),
        TextButton(
          onPressed: () => _buy(q, [o.line]),
          child: Text('Buy', style: CrmTokens.body(color: CrmTokens.navy, w: FontWeight.w700)),
        ),
      ]),
    );
  }

  List<Widget> _listView(List<Quotation> quotes) => [
        for (final q in quotes)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: CrmCard(
              onTap: () => _details(q),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(q.supplierName, style: CrmTokens.display(size: 15)),
                    const SizedBox(height: 3),
                    Text(
                      [
                        if (q.ref.isNotEmpty) 'Quote ${q.ref}',
                        crmDay.format(q.date),
                        '${q.lines.length} product${q.lines.length == 1 ? '' : 's'}',
                      ].join('  ·  '),
                      style: CrmTokens.body(size: 12, color: CrmTokens.muted),
                    ),
                  ]),
                ),
                _status(q),
              ]),
            ),
          ),
      ];

  Widget _status(Quotation q) {
    if (q.isUsed) return const CrmPill('Bought', color: CrmTokens.blue, background: CrmTokens.blueBg);
    if (q.isExpired) return const CrmPill('Expired', color: CrmTokens.muted, background: CrmTokens.bg);
    if (q.validUntil != null) {
      return CrmPill('Till ${crmDay.format(q.validUntil!)}', color: CrmTokens.green, background: CrmTokens.greenBg);
    }
    return const CrmPill('Open', color: CrmTokens.green, background: CrmTokens.greenBg);
  }

  Future<void> _details(Quotation q) async {
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
              Expanded(child: Text(q.supplierName, style: CrmTokens.display(size: 17))),
              _status(q),
            ]),
            const SizedBox(height: 4),
            Text(
              [
                if (q.ref.isNotEmpty) 'Quote ${q.ref}',
                crmDay.format(q.date),
                if (q.validUntil != null) 'valid till ${crmDay.format(q.validUntil!)}',
              ].join('  ·  '),
              style: CrmTokens.body(color: CrmTokens.muted),
            ),
            const Divider(height: 22),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(sheet).size.height * 0.45),
              child: ListView(shrinkWrap: true, children: [
                for (final l in q.lines)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(children: [
                      Expanded(child: Text(l.productName, style: CrmTokens.body())),
                      if (l.minQty > 0)
                        Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: Text('min ${_plain(l.minQty)}', style: CrmTokens.body(size: 12, color: CrmTokens.muted)),
                        ),
                      Text(_rs(l.unitCost), style: CrmTokens.body(w: FontWeight.w700)),
                    ]),
                  ),
              ]),
            ),
            if (q.note.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(q.note, style: CrmTokens.body(size: 12, color: CrmTokens.muted)),
            ],
            const SizedBox(height: 14),
            Row(children: [
              IconButton(
                tooltip: 'Delete',
                onPressed: () => Navigator.pop(sheet, 'delete'),
                icon: const Icon(Icons.delete_outline, color: CrmTokens.red),
              ),
              IconButton(
                tooltip: 'Edit',
                onPressed: () => Navigator.pop(sheet, 'edit'),
                icon: const Icon(Icons.edit_outlined, color: CrmTokens.navy),
              ),
              const Spacer(),
              OutlinedButton(
                onPressed: () => Navigator.pop(sheet, 'order'),
                child: Text('Purchase order', style: CrmTokens.body(color: CrmTokens.navy, w: FontWeight.w600)),
              ),
              const SizedBox(width: 6),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: CrmTokens.amber, elevation: 0),
                onPressed: () => Navigator.pop(sheet, 'buy'),
                icon: const Icon(Icons.add_shopping_cart, color: CrmTokens.navyDark, size: 18),
                label: Text('Make purchase', style: CrmTokens.body(color: CrmTokens.navyDark, w: FontWeight.w700)),
              ),
            ]),
          ]),
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'order':
        _order(q);
      case 'buy':
        if (q.isExpired && !await _confirm('This quotation has expired', 'Its prices may have changed. Buy at these prices anyway?', 'Continue')) {
          return;
        }
        _buy(q);
      case 'edit':
        _edit(q);
      case 'delete':
        if (!await _confirm('Delete quotation?',
            'Only the quotation is deleted. Purchases made from it stay.', 'Delete')) {
          return;
        }
        try {
          await deleteQuotation(q.id);
          _load();
        } catch (e) {
          if (mounted) crmSnack(context, "Couldn't delete. Check your connection.", error: true);
        }
    }
  }

  Future<bool> _confirm(String title, String text, String yes) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(title, style: CrmTokens.display(size: 17)),
        content: Text(text, style: CrmTokens.body()),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: Text('Cancel', style: CrmTokens.body())),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: CrmTokens.navy, elevation: 0),
            onPressed: () => Navigator.pop(d, true),
            child: Text(yes, style: CrmTokens.body(color: Colors.white, w: FontWeight.w600)),
          ),
        ],
      ),
    );
    return ok == true;
  }
}

// -----------------------------------------------------------------------------
// Adding or editing a quotation
// -----------------------------------------------------------------------------

class _QLine {
  StockProduct? product;
  String typed = '';
  final price = TextEditingController();
  final minQty = TextEditingController();

  num get priceValue => num.tryParse(price.text.trim()) ?? 0;
  num get minQtyValue => num.tryParse(minQty.text.trim()) ?? 0;

  void dispose() {
    price.dispose();
    minQty.dispose();
  }
}

class QuotationFormScreen extends StatefulWidget {
  final Quotation? quotation;
  const QuotationFormScreen({super.key, this.quotation});

  @override
  State<QuotationFormScreen> createState() => _QuotationFormScreenState();
}

class _QuotationFormScreenState extends State<QuotationFormScreen> {
  List<Supplier>? _suppliers;
  ProductIndex? _products;
  Object? _error;
  String? _supplierId;
  final _ref = TextEditingController();
  final _note = TextEditingController();
  DateTime _date = DateTime.now();
  DateTime? _validUntil;
  final List<_QLine> _lines = [_QLine()];
  bool _saving = false;

  bool get _editing => widget.quotation != null;

  @override
  void initState() {
    super.initState();
    final q = widget.quotation;
    if (q != null) {
      _supplierId = q.supplierId;
      _ref.text = q.ref;
      _note.text = q.note;
      _date = q.date;
      _validUntil = q.validUntil;
    }
    _load();
  }

  @override
  void dispose() {
    _ref.dispose();
    _note.dispose();
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final results = await Future.wait<Object>([loadSuppliers(activeOnly: true), loadProductIndex(fresh: true)]);
      if (!mounted) return;
      final suppliers = results[0] as List<Supplier>;
      final products = results[1] as ProductIndex;
      setState(() {
        final q = widget.quotation;
        _suppliers = [
          ...suppliers,
          // An edited quotation keeps its supplier even if that supplier was switched off since.
          if (q != null && !suppliers.any((s) => s.id == q.supplierId))
            Supplier(id: q.supplierId, name: q.supplierName),
        ];
        _products = products;
        if (q != null && q.lines.isNotEmpty) {
          final byId = {for (final p in products.all) p.id: p};
          for (final l in _lines) {
            l.dispose();
          }
          _lines
            ..clear()
            ..addAll([
              for (final l in q.lines)
                _QLine()
                  ..product = byId[l.productId] ?? products.byName(l.productName)
                  ..typed = l.productName
                  ..price.text = _plain(l.unitCost)
                  ..minQty.text = l.minQty > 0 ? _plain(l.minQty) : '',
            ]);
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _save() async {
    final supplier = _suppliers?.where((s) => s.id == _supplierId).firstOrNull;
    if (supplier == null) return crmSnack(context, 'Choose the supplier who sent this quotation', error: true);
    final lines = <QuoteLine>[];
    final seen = <String>{};
    for (final l in _lines) {
      if (l.product == null && l.typed.trim().isEmpty && l.priceValue == 0) continue; // empty row
      final p = l.product;
      if (p == null) {
        return crmSnack(
            context,
            l.typed.trim().isEmpty
                ? 'Choose a product on every line'
                : '"${l.typed.trim()}" isn\'t in your product list. Add it in Products first.',
            error: true);
      }
      if (l.priceValue <= 0) return crmSnack(context, 'Enter the quoted price for ${p.name}', error: true);
      if (!seen.add(p.id)) return crmSnack(context, '${p.name} is on two lines. Keep one.', error: true);
      lines.add(QuoteLine(productId: p.id, productName: p.name, unitCost: l.priceValue, minQty: l.minQtyValue));
    }
    if (lines.isEmpty) return crmSnack(context, 'Add at least one product and its price', error: true);
    if (_validUntil != null && _validUntil!.isBefore(DateTime(_date.year, _date.month, _date.day))) {
      return crmSnack(context, '"Valid until" is before the quotation date', error: true);
    }

    setState(() => _saving = true);
    try {
      final old = widget.quotation;
      await saveQuotation(Quotation(
        id: old?.id ?? '',
        supplierId: supplier.id,
        supplierName: supplier.name,
        ref: _ref.text.trim(),
        date: _date,
        validUntil: _validUntil,
        lines: lines,
        note: _note.text.trim(),
      ));
      if (!mounted) return;
      crmSnack(context, _editing ? 'Quotation updated' : 'Quotation saved');
      Navigator.pop(context, true);
    } catch (e) {
      debugPrint('Saving quotation failed: $e');
      if (!mounted) return;
      setState(() => _saving = false);
      crmSnack(context, "Couldn't save. Check your connection and try again.", error: true);
    }
  }

  Future<void> _pickDate({required bool validUntil}) async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: validUntil ? (_validUntil ?? _date.add(const Duration(days: 15))) : _date,
      firstDate: DateTime(2023),
      lastDate: validUntil ? DateTime(now.year + 2) : now,
    );
    if (d == null) return;
    setState(() => validUntil ? _validUntil = d : _date = d);
  }

  @override
  Widget build(BuildContext context) {
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
        title: Text(_editing ? 'Edit quotation' : 'New quotation',
            style: CrmTokens.display(size: 18, color: Colors.white, w: FontWeight.w600)),
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
            Text('Prices a supplier is offering. Nothing is bought and no stock changes until you make a purchase from it.',
                style: CrmTokens.body(color: CrmTokens.muted)),
            const SizedBox(height: 12),
            if (suppliers.isEmpty)
              const CrmEmpty(icon: Icons.local_shipping_outlined, text: 'No suppliers yet. Add one from Add Supplier first.')
            else
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
                child: TextField(
                  controller: _ref,
                  style: CrmTokens.body(),
                  decoration: crmInput('Quotation no.', icon: Icons.tag),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: InkWell(
                  onTap: () => _pickDate(validUntil: false),
                  child: InputDecorator(
                    decoration: crmInput('Date', icon: Icons.calendar_today_outlined),
                    child: Text(crmDay.format(_date), style: CrmTokens.body()),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            InkWell(
              onTap: () => _pickDate(validUntil: true),
              child: InputDecorator(
                decoration: crmInput('Valid until (optional)', icon: Icons.event_available_outlined).copyWith(
                  suffixIcon: _validUntil == null
                      ? null
                      : IconButton(
                          tooltip: 'No end date',
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () => setState(() => _validUntil = null),
                        ),
                ),
                child: Text(_validUntil == null ? 'No end date' : crmDay.format(_validUntil!),
                    style: CrmTokens.body(color: _validUntil == null ? CrmTokens.muted : CrmTokens.textDark)),
              ),
            ),
            CrmSectionTitle('Quoted prices',
                trailing: Text('${_lines.length} line${_lines.length == 1 ? '' : 's'}',
                    style: CrmTokens.body(size: 12, color: CrmTokens.muted))),
            for (final l in _lines) _lineCard(l),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => _lines.add(_QLine())),
                icon: const Icon(Icons.add, color: CrmTokens.navy),
                label: Text('Add product', style: CrmTokens.body(color: CrmTokens.navy, w: FontWeight.w600)),
              ),
            ),
            const SizedBox(height: 8),
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
                    : const Icon(Icons.check, color: CrmTokens.navyDark),
                label: Text('Save quotation', style: CrmTokens.body(size: 14, color: CrmTokens.navyDark, w: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _lineCard(_QLine line) {
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
                tooltip: 'Remove line',
                onPressed: () => setState(() => _lines.remove(line)),
                icon: const Icon(Icons.close, color: CrmTokens.muted),
              ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextField(
                controller: line.price,
                onChanged: (_) => setState(() {}),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: CrmTokens.body(),
                decoration: crmInput('Quoted price per unit (Rs.)'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: line.minQty,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: CrmTokens.body(),
                decoration: crmInput('Minimum qty (optional)'),
              ),
            ),
          ]),
          if (p != null && p.costPrice > 0 && line.priceValue > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 4),
              child: Text(
                line.priceValue == p.costPrice
                    ? 'Same as you last paid (${_rs(p.costPrice)}).'
                    : '${_rs((line.priceValue - p.costPrice).abs())} ${line.priceValue < p.costPrice ? 'cheaper' : 'dearer'} '
                        'than you last paid (${_rs(p.costPrice)}).',
                style: CrmTokens.body(
                    size: 12, color: line.priceValue <= p.costPrice ? CrmTokens.green : CrmTokens.red, w: FontWeight.w500),
              ),
            ),
        ]),
      ),
    );
  }

  void _setProduct(_QLine line, StockProduct? o, String typed) {
    line.typed = typed;
    if (o?.id == line.product?.id) return;
    setState(() => line.product = o);
  }
}
