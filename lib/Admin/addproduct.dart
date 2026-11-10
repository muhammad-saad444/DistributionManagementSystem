// Adding or editing a product: what it's called, how it's packed, what it sells for, and (when
// new) how many are already in stock.
import 'package:flutter/material.dart';
import 'package:an_agency/ui/app_theme.dart';
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
  // One profit % and one typed price per tier (B2B wholesaler, B2R retailer = TP, B2C consumer = MRP).
  final _markup = TextEditingController(); // B2R profit % on cost
  final _b2bMarkup = TextEditingController();
  final _b2cMarkup = TextEditingController();
  final _tp = TextEditingController(); // B2R
  final _b2b = TextEditingController();
  final _retail = TextEditingController(); // B2C
  Map<String, dynamic> _current = const {}; // prices saved now, kept until a purchase gives a cost
  final _reorder = TextEditingController();
  final _description = TextEditingController();
  // Category and brand are typed with suggestions; these hold whatever is in the box.
  String _category = '';
  String _brand = '';
  int _resetCount = 0; // rebuilds the two suggestion boxes after the form is cleared

  String _unit = 'Piece';
  bool _active = true;
  bool _fixed = false; // new products default to profit %; older ones keep their typed TP
  num _lastCost = 0; // set by purchase bills, shown here, never typed
  num _currentTp = 0;
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
      _lastCost = num.tryParse(s('costPrice')) ?? 0;
      _fixed = d['pricing'] != 'markup';
      _markup.text = n('markupPct');
      _currentTp = num.tryParse(s('dbPrice').isEmpty ? s('dbPrie') : s('dbPrice')) ?? 0;
      _tp.text = n('dbPrice').isEmpty ? n('dbPrie') : n('dbPrice');
      _retail.text = n('retailPrice');
      _b2b.text = n('b2bPrice');
      String pct(String k) => d[k] is num ? '${d[k]}' : '';
      _b2bMarkup.text = pct('b2bMarkupPct');
      _b2cMarkup.text = pct('b2cMarkupPct');
      _current = d;
      _reorder.text = n('reorderLevel');
      _description.text = s('description');
      _active = d['active'] != false;
    }
    _loadSuggestions();
  }

  @override
  void dispose() {
    for (final c in [_name, _code, _packSize, _perCarton, _markup, _b2bMarkup, _b2cMarkup, _tp, _b2b, _retail, _reorder, _description]) {
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

  /// TP in profit % mode: last cost plus the profit %. Before the first purchase there is no cost,
  /// so the current TP (if any) stays until a purchase sets it.
  num get _markupTp => _lastCost > 0 ? tpFromCost(_lastCost, _num(_markup)) : _currentTp;

  TextEditingController _pctOf(String tier) => switch (tier) { 'b2b' => _b2bMarkup, 'b2c' => _b2cMarkup, _ => _markup };
  TextEditingController _priceOf(String tier) => switch (tier) { 'b2b' => _b2b, 'b2c' => _retail, _ => _tp };

  /// A tier's price as it will be saved. 0 for B2B or B2C means "sells at the B2R TP".
  num _tierPrice(String tier) {
    if (_fixed) return _num(_priceOf(tier));
    if (tier == 'b2r') return _markupTp;
    if (_pctOf(tier).text.trim().isEmpty) return 0;
    return _lastCost > 0 ? priceFromCost(_lastCost, _num(_pctOf(tier))) : tierPrice(_current, tier);
  }

  /// What that tier is actually charged: its own price, else the TP.
  num _charged(String tier) {
    final own = _tierPrice(tier);
    return own > 0 ? own : _tierPrice('b2r');
  }

  num? _pctField(String tier) {
    if (_fixed) return tier == 'b2r' ? 0 : null;
    final t = _pctOf(tier).text.trim();
    return t.isEmpty ? (tier == 'b2r' ? 0 : null) : num.tryParse(t);
  }

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
          'pricing': _fixed ? 'fixed' : 'markup',
          'markupPct': _pctField('b2r'),
          'b2bMarkupPct': _pctField('b2b'),
          'b2cMarkupPct': _pctField('b2c'),
          'dbPrice': _tierPrice('b2r'),
          'b2bPrice': _tierPrice('b2b'),
          'retailPrice': _tierPrice('b2c'),
          'reorderLevel': _num(_reorder),
          'description': _description.text.trim(),
          'active': _active,
        },
        id: widget.docId,
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
        for (final c in [_name, _code, _packSize, _perCarton, _markup, _b2bMarkup, _b2cMarkup, _tp, _b2b, _retail, _reorder, _description]) {
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
        title: Text(isEdit ? 'Edit product' : 'Add product',
            style: CrmTokens.display(size: 18, color: AppColors.text, w: FontWeight.w600)),
        actions: [
          if (!isEdit)
            IconButton(
              tooltip: 'View products',
              icon: const Icon(Icons.list_alt_outlined, color: AppColors.text),
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
                      Text('How are the prices set?', style: CrmTokens.body(w: FontWeight.w600)),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: SegmentedButton<bool>(
                          showSelectedIcon: false,
                          segments: const [
                            ButtonSegment(value: false, label: Text('Profit % on cost'), icon: Icon(Icons.percent)),
                            ButtonSegment(value: true, label: Text('Fixed prices'), icon: Icon(Icons.lock_outline)),
                          ],
                          selected: {_fixed},
                          onSelectionChanged: (v) => setState(() => _fixed = v.first),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _fixed
                            ? 'You type each price (e.g. the company\'s printed trade price and MRP). Purchases only change the cost.'
                            : 'Every purchase sets each price = cost + its profit %. Cost comes from the purchase bill.',
                        style: CrmTokens.body(size: 11.5, color: CrmTokens.muted),
                      ),
                      const SizedBox(height: 14),
                      _readOnly('Last purchase cost',
                          _lastCost > 0 ? 'Rs. ${_money(_lastCost)}' : 'No purchase yet', Icons.shopping_cart_outlined),
                      const SizedBox(height: 12),
                      Text('Price for each kind of customer. The shop\'s type on its profile picks which one Book Order charges.',
                          style: CrmTokens.body(size: 11.5, color: CrmTokens.muted)),
                      const SizedBox(height: 10),
                      for (final tier in const ['b2b', 'b2r', 'b2c']) ...[
                        _tierInput(tier),
                        _tierLine(tier),
                        const SizedBox(height: 12),
                      ],
                      _priceSummary(),
                    ]),
                  ),
                  CrmSectionTitle('Stock'),
                  CrmCard(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      _text(_reorder, 'Reorder level', icon: Icons.notifications_active_outlined, number: true,
                          hint: 'Warn when stock falls to this'),
                      const SizedBox(height: 8),
                      Text(
                        'Stock comes in through purchase bills and goes out through booker invoices. '
                        'Goods already in the warehouse on day one: Manage Stock, Adjust, once.',
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

  String _money(num v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  /// The box for one tier: its profit % (profit % mode) or its price (fixed mode).
  Widget _tierInput(String tier) {
    final main = tier == 'b2r';
    final optional = main ? ' *' : '';
    final fallback = 'Leave empty to charge the B2R TP';
    if (_fixed) {
      return _text(_priceOf(tier), '${tierLabel(tier)} price (Rs.)$optional',
          icon: main ? Icons.payments_outlined : Icons.local_offer_outlined,
          number: true,
          onChanged: true,
          hint: main ? 'The trade price shops pay' : fallback, validator: (v) {
        final p = num.tryParse((v ?? '').trim());
        if (main) return p == null || p <= 0 ? 'Enter the price retailers pay' : null;
        if ((v ?? '').trim().isNotEmpty && p == null) return 'Enter a number';
        final tp = _num(_tp);
        if (p != null && p > 0 && tp > 0) {
          if (tier == 'b2b' && p > tp) return 'Wholesale is usually below the TP';
          if (tier == 'b2c' && p < tp) return 'Consumer price is usually above the TP';
        }
        return null;
      });
    }
    return _text(_pctOf(tier), '${tierLabel(tier)} profit %$optional',
        icon: Icons.percent,
        number: true,
        onChanged: true,
        hint: main ? 'e.g. 5 sells Rs 9 cost at Rs 9.45' : fallback, validator: (v) {
      final t = (v ?? '').trim();
      final p = num.tryParse(t);
      if (main) return p == null || p < 0 ? 'Enter the profit % you want' : null;
      if (t.isNotEmpty && (p == null || p < 0)) return 'Enter a profit %';
      return null;
    });
  }

  /// Under each tier: what it is charged and the profit on the last cost.
  Widget _tierLine(String tier) {
    final price = _charged(tier);
    if (price <= 0) return const SizedBox.shrink();
    final own = _tierPrice(tier) > 0;
    var text = tier != 'b2r' && !own ? 'Charged the B2R TP: Rs. ${_money(price)}' : 'Charged Rs. ${_money(price)}';
    var color = CrmTokens.muted;
    if (_lastCost > 0) {
      final profit = price - _lastCost;
      text += profit > 0
          ? '  ·  profit Rs. ${_money(profit)} (${(profit / _lastCost * 100).toStringAsFixed(1)}%)'
          : '  ·  ${profit == 0 ? 'no profit' : 'loss Rs. ${_money(-profit)}'}';
      color = profit > 0 ? CrmTokens.green : CrmTokens.red;
    }
    return Padding(
      padding: const EdgeInsets.only(top: 4, left: 4),
      child: Text(text, style: CrmTokens.body(size: 12, color: color, w: FontWeight.w600)),
    );
  }

  Widget _readOnly(String label, String value, IconData icon) => InputDecorator(
        decoration: crmInput(label, icon: icon),
        child: Text(value, style: CrmTokens.body(color: CrmTokens.muted)),
      );

  /// Before the first purchase there is no cost to work prices out from: say so.
  Widget _priceSummary() {
    if (_fixed || _lastCost > 0) return const SizedBox.shrink(); // each tier shows its own price and profit
    final text = _currentTp > 0
        ? 'Prices stay as they are until the first purchase sets them from the cost.'
        : 'Prices are set on the first purchase: cost + each profit %.';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(color: CrmTokens.blueBg, borderRadius: BorderRadius.circular(8)),
      child: Row(children: [
        const Icon(Icons.info_outline, size: 18, color: CrmTokens.navy),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: CrmTokens.body(color: CrmTokens.navy, w: FontWeight.w600))),
      ]),
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
