// Stock setup (opening counts), one product's stock history, and stock adjustments.
import 'package:flutter/material.dart';
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
        backgroundColor: CrmTokens.navy,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text('Set up opening stock', style: CrmTokens.display(size: 18, color: Colors.white, w: FontWeight.w600)),
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
                                    'Base Size ${_qty(r.product.baseSize)}  ·  invoiced ${_qty(r.soldBefore)}'
                                    '${r.product.baseSize - r.soldBefore < 0 ? '  ·  oversold by ${_qty(r.soldBefore - r.product.baseSize)}' : ''}',
                                    style: CrmTokens.body(
                                        size: 11.5,
                                        color: r.product.baseSize - r.soldBefore < 0 ? CrmTokens.red : CrmTokens.muted),
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

/// One product: stock on hand, value, and every move in and out.
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
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final results = await Future.wait<Object>([loadProductIndex(fresh: true), loadStockMoves(widget.productId)]);
      if (!mounted) return;
      setState(() {
        _product = (results[0] as ProductIndex).all.where((p) => p.id == widget.productId).firstOrNull;
        _moves = results[1] as List<StockMove>;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _adjust() async {
    final p = _product;
    if (p == null) return;
    if (await showAdjustStockDialog(context, p)) _load();
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
      final inQty = moves.where((m) => m.qty > 0 && m.type != 'opening').fold<num>(0, (s, m) => s + m.qty);
      final outQty = moves.where((m) => m.qty < 0).fold<num>(0, (s, m) => s - m.qty);
      body = RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 40),
          children: [
            Row(children: [
              Expanded(
                child: CrmStat(
                  label: 'In stock',
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
            const SizedBox(height: 10),
            if (p?.stock != null)
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: _adjust,
                  icon: const Icon(Icons.tune, color: CrmTokens.navy, size: 18),
                  label: Text('Adjust stock', style: CrmTokens.body(color: CrmTokens.navy, w: FontWeight.w600)),
                ),
              ),
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
                      Icon(m.qty >= 0 ? Icons.south_west : Icons.north_east,
                          size: 18, color: m.qty >= 0 ? CrmTokens.green : CrmTokens.red),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${m.label}${m.ref.isEmpty ? '' : '  ·  ${m.ref}'}', style: CrmTokens.body(w: FontWeight.w600)),
                          Text(
                            [fmt.format(m.date), if (m.party.isNotEmpty) m.party, if (m.note.isNotEmpty) m.note].join('  ·  '),
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
        backgroundColor: CrmTokens.navy,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(widget.productName, style: CrmTokens.display(size: 18, color: Colors.white, w: FontWeight.w600)),
      ),
      body: body,
    );
  }
}

const _reasons = ['Stock count', 'Damaged', 'Expired', 'Found / extra', 'Other'];

/// Asks for a new count (or a change) and saves it. Returns true if stock changed.
Future<bool> showAdjustStockDialog(BuildContext context, StockProduct p) async {
  final count = TextEditingController(text: _qty(p.onHand));
  final note = TextEditingController();
  var reason = _reasons.first;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) {
        final newCount = num.tryParse(count.text.trim());
        final diff = newCount == null ? null : newCount - p.onHand;
        return AlertDialog(
          title: Text('Adjust ${p.name}', style: CrmTokens.display(size: 17)),
          content: SizedBox(
            width: 380,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('System count: ${_qty(p.onHand)} units', style: CrmTokens.body(color: CrmTokens.muted)),
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
    await adjustStock(p, newCount - p.onHand, text.isEmpty ? reason : '$reason: $text');
    if (context.mounted) crmSnack(context, 'Stock updated');
    return true;
  } catch (e) {
    if (context.mounted) crmSnack(context, "Couldn't save. Try again.", error: true);
    return false;
  }
}
