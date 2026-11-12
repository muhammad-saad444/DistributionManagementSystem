// Every return from the market (opened from the Invoices page): refunds, what went back into
// stock, what was written off as damaged or expired, by product, and the list of returns.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../Admin/dashboard_overview.dart' show dashRs;
import '../ui/app_theme.dart';
import '../ui/excel_export.dart';
import '../ui/kpi_card.dart';
import 'returns_data.dart';

final _money = NumberFormat('#,##0');

enum _Period { thisMonth, lastMonth, thisYear }

class ReturnsScreen extends StatefulWidget {
  const ReturnsScreen({super.key});

  @override
  State<ReturnsScreen> createState() => _ReturnsScreenState();
}

class _ReturnsScreenState extends State<ReturnsScreen> {
  _Period _period = _Period.thisMonth;
  List<ReturnRecord>? _all; // everything since the start of the year before last month's
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final n = DateTime.now();
      final from = DateTime(n.year, n.month - 1).isBefore(DateTime(n.year)) ? DateTime(n.year, n.month - 1) : DateTime(n.year);
      final list = await loadReturns(from);
      if (mounted) setState(() => _all = list);
    } catch (e) {
      debugPrint('Returns: $e');
      if (mounted) setState(() => _error = e);
    }
  }

  (DateTime, DateTime) get _range {
    final n = DateTime.now();
    return switch (_period) {
      _Period.thisMonth => (DateTime(n.year, n.month), DateTime(n.year, n.month + 1)),
      _Period.lastMonth => (DateTime(n.year, n.month - 1), DateTime(n.year, n.month)),
      _Period.thisYear => (DateTime(n.year), DateTime(n.year + 1)),
    };
  }

  @override
  Widget build(BuildContext context) {
    final (s, e) = _range;
    final list = _all?.where((r) => !r.date.isBefore(s) && r.date.isBefore(e)).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Returns'),
        actions: [
          ExcelButton(
            onPressed: list == null || list.isEmpty
                ? null
                : () {
                    double n(dynamic v) => (num.tryParse('${v ?? 0}') ?? 0).toDouble();
                    final byProduct = <String, List<double>>{}; // good, written off, refund
                    for (final r in list) {
                      for (final l in r.lines) {
                        final row = byProduct.putIfAbsent((l['product'] ?? 'Item').toString(), () => [0, 0, 0]);
                        row[conditionNamed(l['condition']?.toString()).backToStock ? 0 : 1] += n(l['qty']);
                        row[2] += n(l['amount']);
                      }
                    }
                    exportToExcel(
                      context,
                      fileName: exportFileName('returns'),
                      title: 'Returns',
                      subtitle: const {_Period.thisMonth: 'This month', _Period.lastMonth: 'Last month', _Period.thisYear: 'This year'}[_period]!,
                      sheets: [
                        ExportSheet(
                          name: 'Returns',
                          headers: ['Date', 'Invoice #', 'Shop', 'Area', 'Product', 'Qty', 'Condition', 'Refund (Rs)', 'Note', 'Recorded by'],
                          rows: [
                            for (final r in list)
                              for (final l in r.lines)
                                [r.date, r.invoiceNumber, r.customer, r.area, l['product'], n(l['qty']),
                                  conditionNamed(l['condition']?.toString()).label, n(l['amount']), r.note, r.byName],
                          ],
                          totals: ['Total', null, null, null, null, null, null, list.fold<double>(0, (s, r) => s + r.refund)],
                        ),
                        ExportSheet(
                          name: 'By product',
                          headers: ['Product', 'Back in stock', 'Written off', 'Refund (Rs)'],
                          rows: [for (final e in byProduct.entries) [e.key, e.value[0], e.value[1], e.value[2]]],
                        ),
                      ],
                    );
                  },
          ),
          IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh), onPressed: _load),
          const SizedBox(width: 6),
        ],
      ),
      body: LayoutBuilder(builder: (context, box) {
        final wide = box.maxWidth >= 860;
        final pad = wide ? 24.0 : 14.0;
        return ListView(
          padding: EdgeInsets.fromLTRB(pad, 18, pad, 32),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1180),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final p in _Period.values)
                      ChoiceChip(
                        label: Text(const {_Period.thisMonth: 'This month', _Period.lastMonth: 'Last month', _Period.thisYear: 'This year'}[p]!),
                        selected: _period == p,
                        showCheckmark: false,
                        onSelected: (_) => setState(() => _period = p),
                      ),
                  ]),
                  const SizedBox(height: 16),
                  if (list == null)
                    _error != null
                        ? _panel(child: _empty(Icons.cloud_off, "Couldn't load returns", 'Check the connection and try again.'))
                        : const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator()))
                  else ...[
                    _kpis(list, wide),
                    const SizedBox(height: 16),
                    if (list.isEmpty)
                      _panel(
                        child: _empty(Icons.assignment_return_outlined, 'No returns in this period',
                            'Returns are recorded from an invoice: open it and press Return.'),
                      )
                    else if (wide)
                      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(flex: 5, child: _byProduct(list)),
                        const SizedBox(width: 16),
                        Expanded(flex: 7, child: _list(list)),
                      ])
                    else ...[
                      _byProduct(list),
                      const SizedBox(height: 16),
                      _list(list),
                    ],
                  ],
                ]),
              ),
            ),
          ],
        );
      }),
    );
  }

  Widget _kpis(List<ReturnRecord> list, bool wide) {
    final refunds = list.fold<double>(0, (s, r) => s + r.refund);
    final goodUnits = list.fold<double>(0, (s, r) => s + r.qtyWhere((c) => c.backToStock));
    final badUnits = list.fold<double>(0, (s, r) => s + r.qtyWhere((c) => !c.backToStock));
    final badValue = list.fold<double>(0, (s, r) => s + r.amountWhere((c) => !c.backToStock));
    final shops = {for (final r in list) r.customer}.length;
    return kpiGrid([
      KpiCard(
        label: 'REFUNDED TO SHOPS',
        icon: Icons.assignment_return_outlined,
        tint: AppColors.blue,
        tintBg: AppColors.blueBg,
        value: dashRs(refunds),
        sub: '${list.length} return${list.length == 1 ? '' : 's'} from $shops shop${shops == 1 ? '' : 's'}',
      ),
      KpiCard(
        label: 'BACK IN STOCK',
        icon: Icons.inventory_2_outlined,
        tint: AppColors.green,
        tintBg: AppColors.greenBg,
        value: '${_money.format(goodUnits)} units',
        sub: 'good condition, can be sold again',
      ),
      KpiCard(
        label: 'WRITTEN OFF',
        icon: Icons.broken_image_outlined,
        tint: badUnits > 0 ? AppColors.red : AppColors.navy,
        tintBg: badUnits > 0 ? AppColors.redBg : AppColors.brandSoft,
        value: '${_money.format(badUnits)} units',
        valueColor: badUnits > 0 ? AppColors.red : null,
        sub: badUnits > 0 ? '${dashRs(badValue)} damaged or expired' : 'nothing damaged or expired',
      ),
      KpiCard(
        label: 'SHARE DAMAGED',
        icon: Icons.pie_chart_outline,
        tint: AppColors.amber,
        tintBg: AppColors.amberBg,
        value: goodUnits + badUnits == 0 ? '—' : '${(badUnits / (goodUnits + badUnits) * 100).toStringAsFixed(0)}%',
        sub: 'of returned units',
        progress: goodUnits + badUnits == 0 ? null : badUnits / (goodUnits + badUnits),
      ),
    ], wide ? 4 : 2);
  }

  Widget _byProduct(List<ReturnRecord> list) {
    final good = <String, double>{};
    final bad = <String, double>{};
    final value = <String, double>{};
    for (final r in list) {
      for (final l in r.lines) {
        final p = (l['product'] ?? 'Item').toString();
        final q = (num.tryParse('${l['qty'] ?? 0}') ?? 0).toDouble();
        if (conditionNamed(l['condition']?.toString()).backToStock) {
          good[p] = (good[p] ?? 0) + q;
        } else {
          bad[p] = (bad[p] ?? 0) + q;
        }
        value[p] = (value[p] ?? 0) + (num.tryParse('${l['amount'] ?? 0}') ?? 0).toDouble();
      }
    }
    final products = value.keys.toList()..sort((a, b) => value[b]!.compareTo(value[a]!));
    return _panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _title(Icons.inventory_2_outlined, 'By product', 'units back · written off · refund'),
        const SizedBox(height: 12),
        for (final p in products) ...[
          Row(children: [
            Expanded(child: Text(p, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.text))),
            _pill('${_money.format(good[p] ?? 0)} good', AppColors.green, AppColors.greenBg),
            const SizedBox(width: 6),
            if ((bad[p] ?? 0) > 0) ...[_pill('${_money.format(bad[p])} off', AppColors.red, AppColors.redBg), const SizedBox(width: 6)],
            SizedBox(
              width: 86,
              child: Text('Rs ${_money.format(value[p]!.round())}',
                  textAlign: TextAlign.right, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.text)),
            ),
          ]),
          const Divider(height: 18),
        ],
      ]),
    );
  }

  Widget _list(List<ReturnRecord> list) => _panel(
        padding: const EdgeInsets.fromLTRB(0, 18, 0, 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: _title(Icons.list_alt_outlined, 'All returns', 'newest first')),
          const SizedBox(height: 10),
          for (var i = 0; i < list.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 20, endIndent: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${list[i].customer} · Invoice #${list[i].invoiceNumber}',
                        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.text)),
                    const SizedBox(height: 4),
                    Wrap(spacing: 6, runSpacing: 4, children: [
                      for (final l in list[i].lines)
                        _pill(
                          '${l['product']} × ${_money.format((num.tryParse('${l['qty']}') ?? 0))} · ${conditionNamed(l['condition']?.toString()).label}',
                          conditionNamed(l['condition']?.toString()).backToStock ? AppColors.green : AppColors.red,
                          conditionNamed(l['condition']?.toString()).backToStock ? AppColors.greenBg : AppColors.redBg,
                        ),
                    ]),
                    const SizedBox(height: 4),
                    Text(
                      [
                        DateFormat('d MMM yyyy').format(list[i].date),
                        if (list[i].byName.isNotEmpty) 'by ${list[i].byName}',
                        if (list[i].note.isNotEmpty) list[i].note,
                      ].join(' · '),
                      style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
                    ),
                  ]),
                ),
                Text('Rs ${_money.format(list[i].refund.round())}',
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.text)),
              ]),
            ),
          ],
        ]),
      );

  Widget _pill(String t, Color fg, Color bg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
        child: Text(t, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg)),
      );

  Widget _panel({required Widget child, EdgeInsets padding = const EdgeInsets.fromLTRB(20, 18, 20, 12)}) =>
      Container(decoration: kpiCardDecoration(), clipBehavior: Clip.antiAlias, padding: padding, child: child);

  Widget _title(IconData icon, String title, String note) => Row(children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(color: AppColors.brandSoft, borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, size: 15, color: AppColors.navy),
        ),
        const SizedBox(width: 10),
        Text(title, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: AppColors.text)),
        const SizedBox(width: 8),
        Expanded(child: Text(note, style: const TextStyle(fontSize: 11.5, color: AppColors.muted), overflow: TextOverflow.ellipsis)),
      ]);

  Widget _empty(IconData icon, String title, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 38, color: AppColors.muted),
          const SizedBox(height: 10),
          Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.text)),
          const SizedBox(height: 4),
          Text(text, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
        ]),
      );
}
