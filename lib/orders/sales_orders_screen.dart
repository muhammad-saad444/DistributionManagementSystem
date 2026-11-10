// The office's side of sales orders: switch approval on or off, review what bookers ordered
// against stock, change quantities, then approve (the invoice is made) or reject.
import 'package:flutter/material.dart';
import 'package:an_agency/ui/app_theme.dart';

import '../crm/crm_ui.dart';
import '../inventory/inventory_data.dart';
import 'my_orders_page.dart' show soStatusLook;
import 'orders_data.dart';

num _n(Object? v) => num.tryParse('${v ?? ''}'.trim()) ?? 0;
String _plain(num v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : '$v';

class AdminSalesOrdersScreen extends StatefulWidget {
  const AdminSalesOrdersScreen({super.key});

  @override
  State<AdminSalesOrdersScreen> createState() => _AdminSalesOrdersScreenState();
}

class _AdminSalesOrdersScreenState extends State<AdminSalesOrdersScreen> {
  List<SalesOrder>? _orders;
  Map<String, String> _names = const {};
  bool? _approval;
  Object? _error;
  bool _pendingOnly = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final r = await Future.wait<Object>([loadSalesOrders(), ordersNeedApproval(), bookerNames()]);
      if (!mounted) return;
      setState(() {
        _orders = r[0] as List<SalesOrder>;
        _approval = r[1] as bool;
        _names = r[2] as Map<String, String>;
      });
    } catch (e) {
      debugPrint('Sales orders: $e');
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _toggle(bool on) async {
    setState(() => _approval = on);
    try {
      await setOrdersNeedApproval(on);
      if (mounted) {
        crmSnack(context,
            on ? 'Bookers\' orders now wait for your approval' : 'Bookers make invoices directly again');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _approval = !on);
        crmSnack(context, "Couldn't save. Check your connection.", error: true);
      }
    }
  }

  String _booker(SalesOrder o) => o.bookerName.isNotEmpty ? o.bookerName : (_names[o.userId] ?? o.userEmail);

  @override
  Widget build(BuildContext context) {
    final orders = _orders;
    return Scaffold(
      backgroundColor: CrmTokens.bg,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text('Sales orders', style: CrmTokens.display(size: 18, color: AppColors.text, w: FontWeight.w600)),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh, color: AppColors.text))],
      ),
      body: orders == null
          ? Center(
              child: _error == null
                  ? const CircularProgressIndicator(color: CrmTokens.navy)
                  : Column(mainAxisSize: MainAxisSize.min, children: [
                      const CrmEmpty(icon: Icons.cloud_off, text: "Couldn't load orders. Check your connection."),
                      OutlinedButton(onPressed: _load, child: Text('Try again', style: CrmTokens.body(color: CrmTokens.navy))),
                    ]),
            )
          : RefreshIndicator(
              color: CrmTokens.navy,
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 40),
                children: [
                  CrmCard(
                    child: SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _approval ?? false,
                      onChanged: _toggle,
                      title: Text('Bookers\' orders need approval', style: CrmTokens.body(w: FontWeight.w700)),
                      subtitle: Text(
                        (_approval ?? false)
                            ? 'Book Order sends an order here. You check stock, change it if needed, and approve: the '
                                'invoice is made in the booker\'s name and stock goes out then.'
                            : 'Off: Book Order makes the invoice straight away (as before). Turn on to review orders first.',
                        style: CrmTokens.body(size: 12, color: CrmTokens.muted),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                        child: CrmStat(
                            label: 'Waiting for approval',
                            value: '${orders.where((o) => o.status == 'pending').length}')),
                    const SizedBox(width: 8),
                    Expanded(
                      child: CrmStat(
                        label: 'Value waiting',
                        value: crmRs(orders.where((o) => o.status == 'pending').fold<num>(0, (s, o) => s + o.grandTotal)),
                      ),
                    ),
                  ]),
                  Row(children: [
                    Checkbox(
                        value: _pendingOnly,
                        activeColor: CrmTokens.navy,
                        onChanged: (v) => setState(() => _pendingOnly = v ?? true)),
                    Text('Waiting only', style: CrmTokens.body(color: CrmTokens.muted)),
                  ]),
                  for (final o in orders.where((o) => !_pendingOnly || o.status == 'pending')) _card(o, orders),
                  if (orders.where((o) => !_pendingOnly || o.status == 'pending').isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 30),
                      child: CrmEmpty(
                        icon: Icons.assignment_turned_in_outlined,
                        text: _pendingOnly ? 'Nothing waiting for approval.' : 'No sales orders yet.',
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _card(SalesOrder o, List<SalesOrder> all) {
    final (label, color, bg) = soStatusLook(o.status);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: CrmCard(
        onTap: () async {
          final changed = await Navigator.push<bool>(
              context, MaterialPageRoute(builder: (_) => SalesOrderReviewScreen(order: o, all: all, bookerName: _booker(o))));
          if (changed == true) _load();
        },
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('${o.number}  ·  ${o.customer}', style: CrmTokens.display(size: 15))),
            CrmPill(o.status == 'pending' ? 'Waiting' : label, color: color, background: bg),
          ]),
          const SizedBox(height: 3),
          Text(
            [
              _booker(o),
              if (o.area.isNotEmpty) o.area,
              o.salesDate,
              '${o.items.length} product${o.items.length == 1 ? '' : 's'}',
              crmRs(o.grandTotal),
              if (o.invoiceNumber.isNotEmpty) 'invoice #${o.invoiceNumber}',
            ].join('  ·  '),
            style: CrmTokens.body(size: 12, color: CrmTokens.muted),
          ),
        ]),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Review one order
// -----------------------------------------------------------------------------

class _Row {
  final Map<String, String> item;
  final qty = TextEditingController();
  final bns = TextEditingController();
  bool removed = false;
  _Row(this.item) {
    qty.text = item['QTY'] ?? '';
    bns.text = (item['BNS'] ?? '') == '0' ? '' : item['BNS'] ?? '';
  }
  num get tp => _n(item['TP']);
  num get qtyValue => _n(qty.text);
  num get bnsValue => _n(bns.text);
  String get name => item['Product Name'] ?? '';

  Map<String, String> toItem() => {
        ...item,
        'QTY': _plain(qtyValue),
        'BNS': _plain(bnsValue),
        'Gross Total': (tp * qtyValue).toStringAsFixed(2),
      };

  void dispose() {
    qty.dispose();
    bns.dispose();
  }
}

class SalesOrderReviewScreen extends StatefulWidget {
  final SalesOrder order;
  final List<SalesOrder> all; // for stock already promised to other waiting orders
  final String bookerName;
  const SalesOrderReviewScreen({super.key, required this.order, required this.all, required this.bookerName});

  @override
  State<SalesOrderReviewScreen> createState() => _SalesOrderReviewScreenState();
}

class _SalesOrderReviewScreenState extends State<SalesOrderReviewScreen> {
  late final List<_Row> _rows = [for (final i in widget.order.items) _Row(i)];
  ProductIndex? _products;
  String _warehouseName = '';
  final _note = TextEditingController();
  bool _busy = false;

  bool get _pending => widget.order.status == 'pending';

  @override
  void initState() {
    super.initState();
    _loadStock();
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    _note.dispose();
    super.dispose();
  }

  Future<void> _loadStock() async {
    try {
      final r = await Future.wait<Object>([loadProductIndex(fresh: true), warehouseNames()]);
      if (!mounted) return;
      setState(() {
        _products = r[0] as ProductIndex;
        _warehouseName = (r[1] as Map<String, String>)[widget.order.warehouseId] ?? 'Main warehouse';
      });
    } catch (_) {}
  }

  num get _total => _rows.where((r) => !r.removed).fold<num>(0, (s, r) => s + r.tp * r.qtyValue);
  num get _grand {
    final o = widget.order;
    return o.discountType == 'percent' ? _total - _total * o.discount / 100 : _total - o.discount;
  }

  Future<void> _approve() async {
    final lines = [
      for (final r in _rows)
        if (!r.removed && (r.qtyValue > 0 || r.bnsValue > 0)) r.toItem(),
    ];
    if (lines.isEmpty) return crmSnack(context, 'Nothing left on the order. Reject it instead.', error: true);
    final short = _shortages();
    if (short.isNotEmpty) {
      final go = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: Text('Not enough stock', style: CrmTokens.display(size: 17)),
          content: Text('${short.join('\n')}\n\nApprove anyway? Stock will go below zero.', style: CrmTokens.body()),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: Text('Go back', style: CrmTokens.body())),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: CrmTokens.amber, elevation: 0),
              onPressed: () => Navigator.pop(d, true),
              child: Text('Approve anyway', style: CrmTokens.body(color: CrmTokens.navyDark, w: FontWeight.w700)),
            ),
          ],
        ),
      );
      if (go != true) return;
    }
    setState(() => _busy = true);
    try {
      final number = await approveSalesOrder(widget.order, lines, note: _note.text.trim());
      if (!mounted) return;
      crmSnack(context, 'Approved. Invoice #$number made for ${widget.bookerName}.');
      Navigator.pop(context, true);
    } catch (e) {
      debugPrint('Approving order failed: $e');
      if (!mounted) return;
      setState(() => _busy = false);
      crmSnack(context, "Couldn't approve. Check your connection and try again.", error: true);
    }
  }

  Future<void> _reject() async {
    final reason = TextEditingController(text: _note.text);
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('Reject ${widget.order.number}?', style: CrmTokens.display(size: 17)),
        content: TextField(
          controller: reason,
          maxLines: 2,
          style: CrmTokens.body(),
          decoration: crmInput('Reason (the booker sees this)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: Text('Back', style: CrmTokens.body())),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: CrmTokens.red, elevation: 0),
            onPressed: () => Navigator.pop(d, true),
            child: Text('Reject', style: CrmTokens.body(color: Colors.white, w: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await rejectSalesOrder(widget.order, reason.text.trim());
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      crmSnack(context, "Couldn't save. Check your connection.", error: true);
    }
  }

  /// Stock in the order's warehouse after other waiting orders take theirs.
  num? _available(String name) {
    final p = _products?.byName(name);
    if (p == null || p.stock == null) return null;
    final promised = pendingDemand(widget.all, exceptId: widget.order.id)[name.trim().toLowerCase()] ?? 0;
    return p.inWarehouse(widget.order.warehouseId) - promised;
  }

  List<String> _shortages() => [
        for (final r in _rows)
          if (!r.removed)
            if (_available(r.name) case final a? when r.qtyValue + r.bnsValue > a)
              '${r.name}: wants ${_plain(r.qtyValue + r.bnsValue)}, ${_plain(a < 0 ? 0 : a)} available',
      ];

  @override
  Widget build(BuildContext context) {
    final o = widget.order;
    final (label, color, bg) = soStatusLook(o.status);
    return Scaffold(
      backgroundColor: CrmTokens.bg,
      appBar: AppBar(
        title: Text(o.number, style: CrmTokens.display(size: 18, color: AppColors.text, w: FontWeight.w600)),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 40),
            children: [
              CrmCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(o.customer, style: CrmTokens.display(size: 17))),
                    CrmPill(label, color: color, background: bg),
                  ]),
                  const SizedBox(height: 4),
                  Text(
                    [
                      'Booker: ${widget.bookerName}',
                      if (o.area.isNotEmpty) o.area,
                      o.salesDate,
                      if (_warehouseName.isNotEmpty) 'from $_warehouseName',
                    ].join('  ·  '),
                    style: CrmTokens.body(color: CrmTokens.muted),
                  ),
                  if (o.invoiceNumber.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('Invoice #${o.invoiceNumber}', style: CrmTokens.body(w: FontWeight.w700, color: CrmTokens.green)),
                    ),
                  if (o.decisionNote.isNotEmpty)
                    Text('Note: ${o.decisionNote}', style: CrmTokens.body(size: 12, color: CrmTokens.muted)),
                ]),
              ),
              CrmSectionTitle('Products',
                  trailing: _products == null
                      ? null
                      : Text('stock after other waiting orders', style: CrmTokens.body(size: 11.5, color: CrmTokens.muted))),
              for (final r in _rows) _rowCard(r),
              const SizedBox(height: 8),
              CrmCard(
                child: Column(children: [
                  _sum('Total', crmRs(_total)),
                  if (o.discount > 0)
                    _sum('Discount', o.discountType == 'percent' ? '${_plain(o.discount)}%' : crmRs(o.discount)),
                  const Divider(height: 18),
                  _sum('Grand total', crmRs(_grand), bold: true),
                ]),
              ),
              if (_pending) ...[
                const SizedBox(height: 12),
                TextField(controller: _note, style: CrmTokens.body(), decoration: crmInput('Note (optional)')),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: CrmTokens.red), padding: const EdgeInsets.symmetric(vertical: 14)),
                      onPressed: _busy ? null : _reject,
                      child: Text('Reject', style: CrmTokens.body(color: CrmTokens.red, w: FontWeight.w700)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: CrmTokens.green, elevation: 0, padding: const EdgeInsets.symmetric(vertical: 14)),
                      onPressed: _busy ? null : _approve,
                      icon: _busy
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.check, color: Colors.white),
                      label: Text('Approve and make invoice', style: CrmTokens.body(color: Colors.white, w: FontWeight.w700)),
                    ),
                  ),
                ]),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _sum(String l, String v, {bool bold = false}) => Row(children: [
        Expanded(child: Text(l, style: CrmTokens.body(w: bold ? FontWeight.w700 : FontWeight.w400))),
        Text(v, style: bold ? CrmTokens.display(size: 16, color: CrmTokens.navy) : CrmTokens.body(w: FontWeight.w600)),
      ]);

  Widget _rowCard(_Row r) {
    final a = _available(r.name);
    final short = a != null && r.qtyValue + r.bnsValue > a;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Opacity(
        opacity: r.removed ? 0.45 : 1,
        child: CrmCard(
          padding: const EdgeInsets.all(10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(r.name, style: CrmTokens.body(w: FontWeight.w600))),
              Text('TP ${crmRs(r.tp)}', style: CrmTokens.body(size: 12, color: CrmTokens.muted)),
              if (_pending)
                IconButton(
                  tooltip: r.removed ? 'Put back' : 'Remove from order',
                  icon: Icon(r.removed ? Icons.undo : Icons.close, color: CrmTokens.muted, size: 20),
                  onPressed: () => setState(() => r.removed = !r.removed),
                ),
            ]),
            if (a != null)
              Text(
                short ? 'Only ${_plain(a < 0 ? 0 : a)} available' : '${_plain(a)} available',
                style: CrmTokens.body(size: 11.5, color: short ? CrmTokens.red : CrmTokens.green, w: FontWeight.w600),
              ),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: r.qty,
                  enabled: _pending && !r.removed,
                  onChanged: (_) => setState(() {}),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: CrmTokens.body(),
                  decoration: crmInput('QTY'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: r.bns,
                  enabled: _pending && !r.removed,
                  onChanged: (_) => setState(() {}),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: CrmTokens.body(),
                  decoration: crmInput('Bonus (FOC)'),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 110,
                child: Text(crmRs(r.removed ? 0 : r.tp * r.qtyValue),
                    textAlign: TextAlign.right, style: CrmTokens.body(w: FontWeight.w700)),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}
