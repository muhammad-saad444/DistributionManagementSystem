// Adding or editing a product: what it's called, how it's packed, what it sells for, and (when
// new) how many are already in stock.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../crm/crm_ui.dart';
import '../inventory/inventory_data.dart';
import 'product_list_screen.dart';

/// Selling units. A product saved with something else (older products) keeps it as an option.
const productUnits = [
  'Piece', 'Pack', 'Box', 'Carton', 'Dozen', 'Bottle', 'Jar', 'Tin', 'Bag', 'Sachet', 'Tube', 'Roll', 'Kg', 'Litre'
];

/// Offered before a company has categories of its own.
const _starterCategories = ['Food', 'Beverages', 'Personal Care', 'Home Care', 'Stationery', 'Others'];

class ProductFormScreen extends StatefulWidget {
  final String? docId;
  final Map<String, dynamic>? productData;

  const ProductFormScreen({super.key, this.docId, this.productData});

  @override
  State<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends State<ProductFormScreen> {
  final _formKey = GlobalKey<FormState>();

  final _name = TextEditingController();
  final _code = TextEditingController();
  final _packSize = TextEditingController();
  final _perCarton = TextEditingController();
  final _cost = TextEditingController();
  final _tp = TextEditingController();
  final _retail = TextEditingController();
  final _reorder = TextEditingController();
  final _opening = TextEditingController();
  final _description = TextEditingController();
  // Category and brand are typed with suggestions; these hold whatever is in the box.
  String _category = '';
  String _brand = '';
  int _resetCount = 0; // rebuilds the two suggestion boxes after the form is cleared

  String _unit = 'Piece';
  bool _active = true;
  bool _saving = false;

  List<String> _categories = _starterCategories;
  List<String> _brands = const [];

  bool get isEdit => widget.docId != null;

  @override
  void initState() {
    super.initState();
    final d = widget.productData;
    if (d != null) {
      String s(String k) => (d[k] ?? '').toString().trim();
      String n(String k) {
        final v = num.tryParse(s(k));
        return v == null || v == 0 ? '' : '$v';
      }

      _name.text = s('productName');
      _code.text = s('productCode');
      _category = s('productCategory');
      _brand = s('brand');
      final unit = s('productSize');
      if (unit.isNotEmpty) _unit = unit;
      _packSize.text = s('packSize');
      _perCarton.text = n('unitsPerCarton');
      _cost.text = n('costPrice');
      _tp.text = n('dbPrice').isEmpty ? n('dbPrie') : n('dbPrice');
      _retail.text = n('retailPrice');
      _reorder.text = n('reorderLevel');
      _description.text = s('description');
      _active = d['active'] != false;
    }
    _loadSuggestions();
  }

  @override
  void dispose() {
    for (final c in [_name, _code, _packSize, _perCarton, _cost, _tp, _retail, _reorder, _opening, _description]) {
      c.dispose();
    }
    super.dispose();
  }

  /// The company's own categories and brands, taken from its products.
  Future<void> _loadSuggestions() async {
    try {
      final products = await loadProductIndex();
      final cats = <String>{};
      final brands = <String>{};
      for (final p in products.all) {
        if (p.category.trim().isNotEmpty) cats.add(p.category.trim());
        if (p.brand.trim().isNotEmpty) brands.add(p.brand.trim());
      }
      if (!mounted) return;
      setState(() {
        if (cats.isNotEmpty) _categories = cats.toList()..sort();
        _brands = brands.toList()..sort();
      });
    } catch (_) {
      // Suggestions are a convenience; typing still works without them.
    }
  }

  num _num(TextEditingController c) => num.tryParse(c.text.trim()) ?? 0;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final name = _name.text.trim();
    setState(() => _saving = true);
    try {
      final dup = await findDuplicateProduct(name, exceptId: widget.docId);
      if (dup != null) {
        if (!mounted) return;
        setState(() => _saving = false);
        return crmSnack(context, 'There is already a product called "${dup.name}". Use a different name.', error: true);
      }
      await saveProduct(
        {
          'productName': name,
          'productCode': _code.text.trim(),
          'productCategory': _category.trim(),
          'brand': _brand.trim(),
          'productSize': _unit, // shown as "Size" on booker invoices
          'packSize': _packSize.text.trim(),
          'unitsPerCarton': _num(_perCarton),
          // Left out when empty so an edit never wipes the cost the last purchase set.
          if (_cost.text.trim().isNotEmpty) 'costPrice': _num(_cost),
          'dbPrice': _num(_tp),
          'retailPrice': _num(_retail),
          'reorderLevel': _num(_reorder),
          'description': _description.text.trim(),
          'active': _active,
        },
        id: widget.docId,
        openingStock: isEdit ? 0 : _num(_opening),
      );
    } catch (e) {
      debugPrint('Saving product failed: $e');
      if (!mounted) return;
      setState(() => _saving = false);
      return crmSnack(context, "Couldn't save the product. Check your connection and try again.", error: true);
    }
    if (!mounted) return;
    crmSnack(context, isEdit ? 'Product updated' : 'Product added');

    // Opened from the product list: go back to it. Opened as a page of the admin panel there is
    // nothing to go back to, so clear the form for the next product.
    if (Navigator.of(context).canPop()) {
      Navigator.pop(context, true);
    } else {
      setState(() {
        _saving = false;
        for (final c in [_name, _code, _packSize, _perCarton, _cost, _tp, _retail, _reorder, _opening, _description]) {
          c.clear();
        }
        // Category, brand and unit stay: products are usually added in runs from the same range.
        _resetCount++;
      });
      _loadSuggestions();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CrmTokens.bg,
      appBar: AppBar(
        backgroundColor: CrmTokens.navy,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(isEdit ? 'Edit product' : 'Add product',
            style: CrmTokens.display(size: 18, color: Colors.white, w: FontWeight.w600)),
        actions: [
          if (!isEdit)
            IconButton(
              tooltip: 'View products',
              icon: const Icon(Icons.list_alt_outlined, color: Colors.white),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProductListScreen())),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: LayoutBuilder(builder: (context, box) {
              final wide = box.maxWidth > 560;
              Widget pair(Widget a, Widget b) => wide
                  ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(child: a),
                      const SizedBox(width: 12),
                      Expanded(child: b),
                    ])
                  : Column(children: [a, const SizedBox(height: 12), b]);

              return ListView(
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 40),
                children: [
                  CrmSectionTitle('Product'),
                  CrmCard(
                    child: Column(children: [
                      _text(_name, 'Product name *', icon: Icons.inventory_2_outlined, validator: (v) {
                        if ((v ?? '').trim().isEmpty) return 'Enter the product name';
                        return null;
                      }),
                      if (isEdit)
                        Padding(
                          padding: const EdgeInsets.only(top: 4, left: 4),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text('Bookers find products by name, so keep it the same as on their invoices.',
                                style: CrmTokens.body(size: 11.5, color: CrmTokens.muted)),
                          ),
                        ),
                      const SizedBox(height: 12),
                      pair(
                        _text(_code, 'Product code / SKU', icon: Icons.qr_code_2_outlined),
                        _suggest('Category', _category, _categories, Icons.category_outlined, (v) => _category = v),
                      ),
                      const SizedBox(height: 12),
                      _suggest('Brand / principal company', _brand, _brands, Icons.sell_outlined, (v) => _brand = v,
                          hint: 'Whose product it is, e.g. the company you distribute for'),
                    ]),
                  ),
                  CrmSectionTitle('Packing'),
                  CrmCard(
                    child: Column(children: [
                      pair(
                        DropdownButtonFormField<String>(
                          initialValue: _unit,
                          isExpanded: true,
                          decoration: crmInput('Selling unit *', icon: Icons.straighten_outlined),
                          items: [
                            for (final u in {...productUnits, _unit})
                              DropdownMenuItem(value: u, child: Text(u, style: CrmTokens.body())),
                          ],
                          onChanged: (v) => setState(() => _unit = v ?? 'Piece'),
                        ),
                        _text(_packSize, 'Pack size', icon: Icons.scale_outlined, hint: 'e.g. 500 g, 1 L, 12 pcs'),
                      ),
                      const SizedBox(height: 12),
                      _text(_perCarton, 'Units per carton', icon: Icons.all_inbox_outlined, number: true, decimals: false,
                          hint: 'How many ${_unit.toLowerCase()}s come in one carton'),
                    ]),
                  ),
                  CrmSectionTitle('Prices'),
                  CrmCard(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      pair(
                        _text(_cost, 'Cost price (Rs.)', icon: Icons.shopping_cart_outlined, number: true,
                            hint: 'What you buy one ${_unit.toLowerCase()} for', onChanged: true),
                        _text(_tp, 'TP price (Rs.) *', icon: Icons.payments_outlined, number: true, onChanged: true,
                            validator: (v) {
                          final p = num.tryParse((v ?? '').trim());
                          if (p == null || p <= 0) return 'Enter the price bookers sell at';
                          return null;
                        }),
                      ),
                      _margin(),
                      const SizedBox(height: 12),
                      _text(_retail, 'Retail price / MRP (Rs.)', icon: Icons.local_offer_outlined, number: true,
                          validator: (v) {
                        final r = num.tryParse((v ?? '').trim()) ?? 0;
                        final tp = _num(_tp);
                        if (r > 0 && tp > 0 && r < tp) return 'Retail is usually above the TP price';
                        return null;
                      }),
                      const SizedBox(height: 8),
                      Text(
                        'Each purchase bill updates the cost to what you last paid, so profit always uses the real cost.',
                        style: CrmTokens.body(size: 11.5, color: CrmTokens.muted),
                      ),
                    ]),
                  ),
                  CrmSectionTitle('Stock'),
                  CrmCard(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      if (isEdit)
                        _text(_reorder, 'Reorder level', icon: Icons.notifications_active_outlined, number: true,
                            hint: 'Warn when stock falls to this')
                      else
                        pair(
                          _text(_opening, 'Opening stock (units)', icon: Icons.inventory_outlined, number: true,
                              hint: 'Already on hand, if any'),
                          _text(_reorder, 'Reorder level', icon: Icons.notifications_active_outlined, number: true,
                              hint: 'Warn when stock falls to this'),
                        ),
                      const SizedBox(height: 8),
                      Text(
                        isEdit
                            ? 'Stock changes through purchases, booker invoices and Adjust stock, not here.'
                            : 'Leave opening stock empty if you will enter a purchase bill for these goods, '
                                'otherwise they get counted twice. New stock goes into the Main warehouse.',
                        style: CrmTokens.body(size: 11.5, color: CrmTokens.muted),
                      ),
                      if (isEdit) ...[
                        const Divider(height: 22),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          activeThumbColor: CrmTokens.green,
                          value: _active,
                          onChanged: (v) => setState(() => _active = v),
                          title: Text('Active', style: CrmTokens.body(w: FontWeight.w600)),
                          subtitle: Text(
                              _active
                                  ? 'Bookers can sell it and it can be bought.'
                                  : 'Hidden from new invoices and purchases. Its history stays.',
                              style: CrmTokens.body(size: 12, color: CrmTokens.muted)),
                        ),
                      ],
                    ]),
                  ),
                  const SizedBox(height: 12),
                  CrmCard(child: _text(_description, 'Description (optional)', icon: Icons.notes_outlined, lines: 3)),
                  const SizedBox(height: 18),
                  SizedBox(
                    height: 48,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: CrmTokens.amber,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: CrmTokens.navyDark))
                          : const Icon(Icons.check, color: CrmTokens.navyDark),
                      label: Text(isEdit ? 'Save changes' : 'Add product',
                          style: CrmTokens.body(size: 14, color: CrmTokens.navyDark, w: FontWeight.w700)),
                    ),
                  ),
                ],
              );
            }),
          ),
        ),
      ),
    );
  }

  /// Profit per unit at this cost and TP, shown under the two prices.
  Widget _margin() {
    final cost = _num(_cost);
    final tp = _num(_tp);
    if (cost <= 0 || tp <= 0) return const SizedBox.shrink();
    final profit = tp - cost;
    final pct = profit / cost * 100;
    final loss = profit <= 0;
    String money(num v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: loss ? CrmTokens.redBg : CrmTokens.greenBg,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(children: [
          Icon(loss ? Icons.trending_down : Icons.trending_up, size: 18, color: loss ? CrmTokens.red : CrmTokens.green),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              loss
                  ? 'TP is ${profit == 0 ? 'the same as' : 'below'} cost: Rs. ${money(-profit)} loss on every ${_unit.toLowerCase()}'
                  : 'Profit Rs. ${money(profit)} per ${_unit.toLowerCase()}  ·  ${pct.toStringAsFixed(1)}% on cost',
              style: CrmTokens.body(color: loss ? CrmTokens.red : CrmTokens.green, w: FontWeight.w600),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _text(
    TextEditingController c,
    String label, {
    IconData? icon,
    String? hint,
    bool number = false,
    bool decimals = true,
    int lines = 1,
    bool onChanged = false, // rebuild as they type (for the margin line)
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: c,
      onChanged: onChanged ? (_) => setState(() {}) : null,
      maxLines: lines,
      style: CrmTokens.body(),
      keyboardType: number ? TextInputType.numberWithOptions(decimal: decimals) : null,
      inputFormatters: number ? [FilteringTextInputFormatter.allow(RegExp(decimals ? r'[0-9.]' : r'[0-9]'))] : null,
      decoration: crmInput(label, icon: icon, hint: hint),
      validator: validator ??
          (number
              ? (v) => (v ?? '').trim().isNotEmpty && num.tryParse(v!.trim()) == null ? 'Enter a number' : null
              : null),
    );
  }

  /// A text box that suggests values already in use, and still takes a new one.
  Widget _suggest(String label, String value, List<String> options, IconData icon, ValueChanged<String> onChanged,
      {String? hint}) {
    return Autocomplete<String>(
      key: ValueKey('$label-$_resetCount'),
      initialValue: TextEditingValue(text: value),
      optionsBuilder: (v) {
        final q = v.text.trim().toLowerCase();
        return options.where((o) => o.toLowerCase().contains(q) && o.toLowerCase() != q).take(12);
      },
      onSelected: onChanged,
      fieldViewBuilder: (context, c, focus, onSubmit) => TextFormField(
        controller: c,
        focusNode: focus,
        onChanged: onChanged,
        style: CrmTokens.body(),
        decoration: crmInput(label, icon: icon, hint: hint ?? 'Pick one or type a new one'),
      ),
    );
  }
}
