// Stock setup (opening counts), one product's stock history, and stock adjustments.
import 'package:flutter/material.dart';
import 'package:an_agency/ui/app_theme.dart';
import 'package:intl/intl.dart';

import '../crm/crm_ui.dart';
import 'inventory_data.dart';

String _qty(num v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

/// Run once: admin confirms how many units of each product are in the warehouse right now.
class StockSetupScreen extends StatefulWidget {
  const StockSetupScreen({super.key});

  @override
  State<StockSetupScreen> createState() => _StockSetupScreenState();
}

class _StockSetupScreenState extends State<StockSetupScreen> {
  List<OpeningRow>? _rows;
  DateTime? _at;
  Object? _error;
  final Map<String, TextEditingController> _counts = {};
  final _search = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _counts.values) {
      c.dispose();
    }
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final (rows, at) = await computeOpeningStock();
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _at = at;
        for (final r in rows) {
          _counts[r.product.id] = TextEditingController(text: _qty(r.suggested));
        }
      });
    } catch (e) {
      debugPrint('Stock setup failed: $e');
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _start() async {
    final rows = _rows!;
    final counts = <StockProduct, num>{};
    for (final r in rows) {
      final v = num.tryParse(_counts[r.product.id]!.text.trim());
      if (v == null || v < 0) return crmSnack(context, 'Enter a count of 0 or more for ${r.product.name}', error: true);
      counts[r.product] = v;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('Start stock tracking?', style: CrmTokens.display(size: 17)),
        content: Text(
          'This sets the stock of ${rows.length} products to the counts on this screen. From now on purchases add '
          'stock, and every booker invoice (quantity + FOC) takes it out. You can correct any product later with Adjust.',
          style: CrmTokens.body(),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: Text('Cancel', style: CrmTokens.body())),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: CrmTokens.amber, elevation: 0),
            onPressed: () => Navigator.pop(d, true),
            child: Text('Start', style: CrmTokens.body(w: FontWeight.w700, color: CrmTokens.navyDark)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _saving = true);
    try {
      await startStockTracking(counts, _at!);
      // Invoices booked while this screen was open still need taking out.
      await applyUntrackedInvoices();
      if (!mounted) return;
      crmSnack(context, 'Stock tracking started');
      Navigator.pop(context, true);
    } catch (e) {
      debugPrint('Starting stock tracking failed: $e');
      if (!mounted) return;
      setState(() => _saving = false);
      crmSnack(context, "Couldn't save. Check your connection and try again.", error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    final q = _search.text.trim().toLowerCase();
    return Scaffold(
      backgroundColor: CrmTokens.bg,
      appBar: AppBar(
        title: Text('Set up opening stock', style: CrmTokens.display(size: 18, color: AppColors.text, w: FontWeight.w600)),
      ),
      body: rows == null
          ? Center(
              child: _error != null
                  ? OutlinedButton(onPressed: _load, child: Text('Try again', style: CrmTokens.body(color: CrmTokens.navy)))
                  : Column(mainAxisSize: MainAxisSize.min, children: [
                      const CircularProgressIndicator(color: CrmTokens.navy),
                      const SizedBox(height: 14),
                      Text('Adding up everything sold so far…', style: CrmTokens.body(color: CrmTokens.muted)),
                    ]),
            )
          : Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    'Enter how many units of each product are in the warehouse now. Each box starts with Base Size minus '
                    'everything invoiced so far (QTY + FOC). Best done after a physical count.',
                    style: CrmTokens.body(color: CrmTokens.muted),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _search,
                    onChanged: (_) => setState(() {}),
                    style: CrmTokens.body(),
                    decoration: crmInput('Search products', icon: Icons.search),
                  ),
                ]),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 90),
                  children: [
                    for (final r in rows)
                      if (q.isEmpty || r.product.name.toLowerCase().contains(q))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: CrmCard(
                            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                            child: Row(children: [
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(r.product.name, style: CrmTokens.body(w: FontWeight.w600)),
                                  Text(
                                    'Base Size ${_qty(r.product.baseSize)}'
                                    '${r.boughtBefore != 0 ? '  ·  bought ${_qty(r.boughtBefore)}' : ''}'
                                    '  ·  invoiced ${_qty(r.soldBefore)}'
                                    '${r.product.baseSize + r.boughtBefore - r.soldBefore < 0 ? '  ·  oversold by ${_qty(r.soldBefore - r.product.baseSize - r.boughtBefore)}' : ''}',
                                    style: CrmTokens.body(
                                        size: 11.5,
                                        color: r.product.baseSize + r.boughtBefore - r.soldBefore < 0
                                            ? CrmTokens.red
                                            : CrmTokens.muted),
                                  ),
                                ]),
                              ),
                              SizedBox(
                                width: 110,
                                child: TextField(
                                  controller: _counts[r.product.id],
                                  textAlign: TextAlign.right,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  style: CrmTokens.body(w: FontWeight.w700),
                                  decoration: crmInput('In stock'),
                                ),
                              ),
                            ]),
                          ),
                        ),
                  ],
                ),
              ),
            ]),
      floatingActionButton: rows == null
          ? null
          : FloatingActionButton.extended(
              backgroundColor: CrmTokens.amber,
              foregroundColor: CrmTokens.navyDark,
              onPressed: _saving ? null : _start,
              icon: _saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: CrmTokens.navyDark))
                  : const Icon(Icons.check),
              label: Text('Start tracking ${rows.length} products',
                  style: CrmTokens.body(size: 13, color: CrmTokens.navyDark, w: FontWeight.w700)),
            ),
    );
  }
}

/// One product: stock on hand (per warehouse), value, and every move in and out.
class ProductStockScreen extends StatefulWidget {
  final String productId;
  final String productName;
  const ProductStockScreen({super.key, required this.productId, required this.productName});

  @override
  State<ProductStockScreen> createState() => _ProductStockScreenState();
}

class _ProductStockScreenState extends State<ProductStockScreen> {
  StockProduct? _product;
  List<StockMove>? _moves;
  List<Warehouse> _warehouses = const [];
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final results = await Future.wait<Object>([
        loadProductIndex(fresh: true),
        loadStockMoves(widget.productId),
        loadWarehouses(fresh: true),
      ]);
      if (!mounted) return;
      setState(() {
        _product = (results[0] as ProductIndex).all.where((p) => p.id == widget.productId).firstOrNull;
        _moves = results[1] as List<StockMove>;
        _warehouses = results[2] as List<Warehouse>;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  bool get _many => _warehouses.length > 1;
  String _name(String id) => _warehouses.where((w) => w.id == id).firstOrNull?.name ?? id;

  Future<void> _adjust([String? warehouseId]) async {
    final p = _product;
    if (p == null) return;
    if (await showAdjustStockDialog(context, p, warehouses: _warehouses, warehouseId: warehouseId)) _load();
  }

  Future<void> _transfer() async {
    final p = _product;
    if (p == null) return;
    if (await showTransferDialog(context, p, _warehouses.where((w) => w.active).toList())) _load();
  }

  @override
  Widget build(BuildContext context) {
    final p = _product;
    final moves = _moves;
    final fmt = DateFormat('dd MMM yyyy');
    Widget body;
    if (moves == null) {
      body = Center(
        child: _error != null
            ? OutlinedButton(onPressed: _load, child: Text('Try again', style: CrmTokens.body(color: CrmTokens.navy)))
            : const CircularProgressIndicator(color: CrmTokens.navy),
      );
    } else {
      final inQty =
          moves.where((m) => m.qty > 0 && m.type != 'opening' && m.type != 'transfer_in').fold<num>(0, (s, m) => s + m.qty);
      final outQty = moves.where((m) => m.qty < 0 && m.type != 'transfer_out').fold<num>(0, (s, m) => s - m.qty);
      body = RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 40),
          children: [
            Row(children: [
              Expanded(
                child: CrmStat(
                  label: _many ? 'In stock (all warehouses)' : 'In stock',
                  value: p?.stock == null ? 'Not tracked' : '${_qty(p!.onHand)} units',
                  color: (p?.onHand ?? 0) <= 0 ? CrmTokens.red : CrmTokens.navy,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: CrmStat(label: 'Stock value (at cost)', value: crmRs(p?.stockValue ?? 0))),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: CrmStat(label: 'Cost / sells at', value: '${crmRs(p?.costPrice ?? 0)} / ${crmRs(p?.salePrice ?? 0)}')),
              const SizedBox(width: 8),
              Expanded(child: CrmStat(label: 'In / out (after opening)', value: '+${_qty(inQty)} / −${_qty(outQty)}')),
            ]),
            if (p != null && p.stock != null && _many) ...[
              const CrmSectionTitle('By warehouse'),
              CrmCard(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Column(children: [
                  for (final w in _warehouses)
                    if (w.active || p.inWarehouse(w.id) != 0)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(children: [
                          const Icon(Icons.warehouse_outlined, size: 18, color: CrmTokens.navy),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(w.active ? w.name : '${w.name} (inactive)', style: CrmTokens.body(w: FontWeight.w600)),
                          ),
                          Text(
                            '${_qty(p.inWarehouse(w.id))} units',
                            style: CrmTokens.body(
                                w: FontWeight.w700, color: p.inWarehouse(w.id) <= 0 ? CrmTokens.red : CrmTokens.navy),
                          ),
                          IconButton(
                            tooltip: 'Adjust ${w.name}',
                            onPressed: () => _adjust(w.id),
                            icon: const Icon(Icons.tune, size: 18, color: CrmTokens.muted),
                          ),
                        ]),
                      ),
                ]),
              ),
            ],
            const SizedBox(height: 10),
            if (p?.stock != null)
              Wrap(spacing: 8, runSpacing: 8, children: [
                OutlinedButton.icon(
                  onPressed: () => _adjust(),
                  icon: const Icon(Icons.tune, color: CrmTokens.navy, size: 18),
                  label: Text('Adjust stock', style: CrmTokens.body(color: CrmTokens.navy, w: FontWeight.w600)),
                ),
                if (_many)
                  OutlinedButton.icon(
                    onPressed: _transfer,
                    icon: const Icon(Icons.swap_horiz, color: CrmTokens.navy, size: 18),
                    label: Text('Transfer between warehouses', style: CrmTokens.body(color: CrmTokens.navy, w: FontWeight.w600)),
                  ),
              ]),
            const CrmSectionTitle('Stock history'),
            if (moves.isEmpty)
              const CrmEmpty(icon: Icons.history, text: 'No stock moves yet.')
            else
              for (final m in moves)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: CrmCard(
                    padding: const EdgeInsets.all(12),
                    child: Row(children: [
                      Icon(
                        m.type.startsWith('transfer') ? Icons.swap_horiz : (m.qty >= 0 ? Icons.south_west : Icons.north_east),
                        size: 18,
                        color: m.type.startsWith('transfer') ? CrmTokens.blue : (m.qty >= 0 ? CrmTokens.green : CrmTokens.red),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${m.label}${m.ref.isEmpty ? '' : '  ·  ${m.ref}'}', style: CrmTokens.body(w: FontWeight.w600)),
                          Text(
                            [
                              fmt.format(m.date),
                              if (_many) _name(m.warehouseId),
                              if (m.party.isNotEmpty) m.party,
                              if (m.note.isNotEmpty) m.note,
                            ].join('  ·  '),
                            style: CrmTokens.body(size: 12, color: CrmTokens.muted),
                          ),
                        ]),
                      ),
                      Text('${m.qty > 0 ? '+' : '−'}${_qty(m.qty.abs())}',
                          style: CrmTokens.body(size: 14, w: FontWeight.w700, color: m.qty >= 0 ? CrmTokens.green : CrmTokens.red)),
                    ]),
                  ),
                ),
          ],
        ),
      );
    }
    return Scaffold(
      backgroundColor: CrmTokens.bg,
      appBar: AppBar(
        title: Text(widget.productName, style: CrmTokens.display(size: 18, color: AppColors.text, w: FontWeight.w600)),
      ),
      body: body,
    );
  }
}

const _reasons = ['Stock count', 'Damaged', 'Expired', 'Found / extra', 'Other'];

/// A warehouse picker for dialogs (nothing when the company has only Main).
Widget _warehousePicker(List<Warehouse> warehouses, String value, String label, ValueChanged<String> onChanged) {
  if (warehouses.length <= 1) return const SizedBox.shrink();
  return Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: DropdownButtonFormField<String>(
      key: ValueKey('$label-$value'),
      initialValue: value,
      isExpanded: true,
      decoration: crmInput(label, icon: Icons.warehouse_outlined),
      items: [for (final w in warehouses) DropdownMenuItem(value: w.id, child: Text(w.name, style: CrmTokens.body()))],
      onChanged: (v) => onChanged(v ?? value),
    ),
  );
}

/// Asks for a new count in one warehouse (or a change) and saves it. Returns true if stock changed.
Future<bool> showAdjustStockDialog(
  BuildContext context,
  StockProduct p, {
  List<Warehouse> warehouses = const [],
  String? warehouseId,
}) async {
  var w = warehouseId ?? mainWarehouseId;
  final count = TextEditingController(text: _qty(p.inWarehouse(w)));
  final note = TextEditingController();
  var reason = _reasons.first;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) {
        final system = p.inWarehouse(w);
        final newCount = num.tryParse(count.text.trim());
        final diff = newCount == null ? null : newCount - system;
        return AlertDialog(
          title: Text('Adjust ${p.name}', style: CrmTokens.display(size: 17)),
          content: SizedBox(
            width: 380,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              _warehousePicker(warehouses, w, 'Warehouse', (v) => set(() {
                    w = v;
                    count.text = _qty(p.inWarehouse(v));
                  })),
              Text('System count: ${_qty(system)} units', style: CrmTokens.body(color: CrmTokens.muted)),
              const SizedBox(height: 10),
              TextField(
                controller: count,
                autofocus: true,
                onChanged: (_) => set(() {}),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: CrmTokens.body(),
                decoration: crmInput('Actual count (units)', icon: Icons.inventory_2_outlined),
              ),
              if (diff != null && diff != 0)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('${diff > 0 ? 'Adds' : 'Removes'} ${_qty(diff.abs())} units',
                      style: CrmTokens.body(size: 12, color: diff > 0 ? CrmTokens.green : CrmTokens.red)),
                ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: reason,
                decoration: crmInput('Reason'),
                items: [for (final r in _reasons) DropdownMenuItem(value: r, child: Text(r, style: CrmTokens.body()))],
                onChanged: (v) => reason = v ?? reason,
              ),
              const SizedBox(height: 10),
              TextField(controller: note, style: CrmTokens.body(), decoration: crmInput('Note (optional)')),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancel', style: CrmTokens.body())),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: CrmTokens.amber, elevation: 0),
              onPressed: diff == null || diff == 0 || newCount! < 0 ? null : () => Navigator.pop(ctx, true),
              child: Text('Save', style: CrmTokens.body(w: FontWeight.w700, color: CrmTokens.navyDark)),
            ),
          ],
        );
      },
    ),
  );
  final newCount = num.tryParse(count.text.trim());
  final text = note.text.trim();
  count.dispose();
  note.dispose();
  if (ok != true || newCount == null) return false;
  try {
    await adjustStock(p, newCount - p.inWarehouse(w), text.isEmpty ? reason : '$reason: $text', warehouseId: w);
    if (context.mounted) crmSnack(context, 'Stock updated');
    return true;
  } catch (e) {
    if (context.mounted) crmSnack(context, "Couldn't save. Try again.", error: true);
    return false;
  }
}

/// Moves units of a product from one warehouse to another. Returns true if it did.
Future<bool> showTransferDialog(BuildContext context, StockProduct p, List<Warehouse> warehouses) async {
  if (warehouses.length < 2) return false;
  var from = warehouses.first.id;
  var to = warehouses[1].id;
  final qty = TextEditingController();
  final note = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
      final n = num.tryParse(qty.text.trim()) ?? 0;
      final available = p.inWarehouse(from);
      final String? problem = from == to
          ? 'Choose two different warehouses'
          : (n > available ? 'Only ${_qty(available)} units in the "from" warehouse' : null);
      return AlertDialog(
        title: Text('Transfer ${p.name}', style: CrmTokens.display(size: 17)),
        content: SizedBox(
          width: 380,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            _warehousePicker(warehouses, from, 'From', (v) => set(() => from = v)),
            _warehousePicker(warehouses, to, 'To', (v) => set(() => to = v)),
            TextField(
              controller: qty,
              autofocus: true,
              onChanged: (_) => set(() {}),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: CrmTokens.body(),
              decoration: crmInput('Units to move', icon: Icons.swap_horiz, hint: '${_qty(available)} available'),
            ),
            const SizedBox(height: 10),
            TextField(controller: note, style: CrmTokens.body(), decoration: crmInput('Note (optional)')),
            if (problem != null && (n > 0 || from == to))
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(problem, style: CrmTokens.body(size: 12, color: CrmTokens.red)),
              ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancel', style: CrmTokens.body())),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: CrmTokens.amber, elevation: 0),
            onPressed: n <= 0 || problem != null ? null : () => Navigator.pop(ctx, true),
            child: Text('Transfer', style: CrmTokens.body(w: FontWeight.w700, color: CrmTokens.navyDark)),
          ),
        ],
      );
    }),
  );
  final n = num.tryParse(qty.text.trim()) ?? 0;
  final text = note.text.trim();
  qty.dispose();
  note.dispose();
  if (ok != true || n <= 0) return false;
  try {
    await transferStock(p, from: from, to: to, qty: n, note: text);
    if (context.mounted) crmSnack(context, 'Moved ${_qty(n)} units');
    return true;
  } catch (e) {
    if (context.mounted) crmSnack(context, "Couldn't transfer. Try again.", error: true);
    return false;
  }
}
