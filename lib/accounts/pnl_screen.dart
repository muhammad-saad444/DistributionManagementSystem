// Admin: profit & loss for a period, laid out like an accountant's statement (sales, cost of
// goods, gross profit, expenses by category, net profit), with the last six months side by side
// and a printable statement.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../account/account.dart';
import '../print_preview.dart';
import '../Admin/dashboard_overview.dart' show dashRs;
import '../ui/app_theme.dart';
import '../ui/kpi_card.dart';
import 'pnl_data.dart';

final _money = NumberFormat('#,##0');
String _rs(num v) => '${v < 0 ? '−' : ''}Rs ${_money.format(v.abs().round())}';
String _pct(double? v) => v == null ? '' : '${v.toStringAsFixed(1)}%';
final _dmy = DateFormat('d MMM yyyy');

enum _Period { thisMonth, lastMonth, last3, thisYear, custom }

class PnlScreen extends StatefulWidget {
  final void Function(String title)? onOpen; // opens another admin page (e.g. Expenses)
  const PnlScreen({super.key, this.onOpen});

  @override
  State<PnlScreen> createState() => _PnlScreenState();
}

class _PnlScreenState extends State<PnlScreen> {
  _Period _period = _Period.thisMonth;
  DateTimeRange? _custom;
  PnlData? _data;
  Object? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  (DateTime, DateTime) get _range {
    final n = DateTime.now();
    return switch (_period) {
      _Period.thisMonth => (DateTime(n.year, n.month), DateTime(n.year, n.month + 1)),
      _Period.lastMonth => (DateTime(n.year, n.month - 1), DateTime(n.year, n.month)),
      _Period.last3 => (DateTime(n.year, n.month - 2), DateTime(n.year, n.month + 1)),
      _Period.thisYear => (DateTime(n.year), DateTime(n.year + 1)),
      _Period.custom => (
          DateTime(_custom!.start.year, _custom!.start.month, _custom!.start.day),
          DateTime(_custom!.end.year, _custom!.end.month, _custom!.end.day + 1),
        ),
    };
  }

  String get _periodLabel {
    final (s, e) = _range;
    final last = e.subtract(const Duration(days: 1));
    if (s.day == 1 && e == DateTime(s.year, s.month + 1)) return DateFormat('MMMM yyyy').format(s);
    if (s.month == 1 && s.day == 1 && e == DateTime(s.year + 1)) return 'Year ${s.year}';
    return '${_dmy.format(s)} – ${_dmy.format(last)}';
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final (s, e) = _range;
    try {
      final d = await loadPnl(s, e);
      if (mounted) setState(() => _data = d);
    } catch (err) {
      debugPrint('P&L: $err');
      if (mounted) setState(() => _error = err);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _choose(_Period p) async {
    if (p == _Period.custom) {
      final n = DateTime.now();
      final r = await showDateRangePicker(
        context: context,
        firstDate: DateTime(n.year - 3),
        lastDate: n,
        initialDateRange: _custom ?? DateTimeRange(start: DateTime(n.year, n.month), end: n),
      );
      if (r == null) return;
      _custom = r;
    }
    setState(() => _period = p);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profit & loss'),
        actions: [
          IconButton(
            tooltip: 'Print statement',
            icon: const Icon(Icons.print_outlined),
            onPressed: d == null
                ? null
                : () => showPrintPreview(
                      context,
                      title: 'Profit & loss · $_periodLabel',
                      fileName: 'profit-and-loss-${DateFormat('yyyy-MM-dd').format(d.period.start)}.pdf',
                      buildPdf: () => _pnlPdf(d, _periodLabel),
                    ),
          ),
          IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh), onPressed: _loading ? null : _load),
          const SizedBox(width: 6),
        ],
        bottom: _loading && d != null
            ? const PreferredSize(preferredSize: Size.fromHeight(2), child: LinearProgressIndicator(minHeight: 2))
            : null,
      ),
      body: LayoutBuilder(builder: (context, box) {
        final wide = box.maxWidth >= 860;
        return ListView(
          padding: EdgeInsets.fromLTRB(wide ? 24 : 14, 16, wide ? 24 : 14, 32),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1100),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  _periodChips(),
                  const SizedBox(height: 14),
                  if (d == null)
                    _error != null
                        ? _message(Icons.cloud_off, "Couldn't work out profit & loss", 'Check the connection and try again.',
                            action: TextButton(onPressed: _load, child: const Text('Try again')))
                        : const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator()))
                  else ...[
                    _kpis(d, wide),
                    if (d.period.productsWithoutCost > 0) ...[const SizedBox(height: 12), _costWarning(d.period)],
                    const SizedBox(height: 14),
                    if (wide)
                      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(flex: 6, child: _statement(d.period)),
                        const SizedBox(width: 14),
                        Expanded(flex: 5, child: _months(d.months)),
                      ])
                    else ...[
                      _statement(d.period),
                      const SizedBox(height: 14),
                      _months(d.months),
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

  Widget _periodChips() {
    const labels = {
      _Period.thisMonth: 'This month',
      _Period.lastMonth: 'Last month',
      _Period.last3: 'Last 3 months',
      _Period.thisYear: 'This year',
      _Period.custom: 'Choose dates',
    };
    return Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
      for (final p in _Period.values)
        ChoiceChip(
          label: Text(labels[p]!),
          avatar: p == _Period.custom ? const Icon(Icons.date_range, size: 16) : null,
          selected: _period == p,
          showCheckmark: false,
          onSelected: (_) => _choose(p),
        ),
      Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Text(_periodLabel, style: _small(w: FontWeight.w600)),
      ),
    ]);
  }

  /// The four headline figures, as dashboard cards: each with the last six months as a trend line
  /// and, for a single month, the change from the month before.
  Widget _kpis(PnlData d, bool wide) {
    final p = d.period;
    final months = d.months;
    // The month before the chosen one, when a single month is chosen and it's in the six.
    ProfitAndLoss? before;
    final i = months.indexWhere((m) => m.start == p.start && m.end == p.end);
    if (i > 0) before = months[i - 1];

    (String, bool)? vs(double now, double then, {bool upIsGood = true}) {
      if (before == null || then.abs() < 0.5) return null;
      final pct = (now - then) / then.abs() * 100;
      final up = now >= then;
      return ('${up ? '▲' : '▼'} ${pct.abs().toStringAsFixed(0)}% vs ${DateFormat('MMM').format(before.start)}', up == upIsGood);
    }

    String margin(double v) => p.marginOf(v) == null ? 'no sales in this period' : '${_pct(p.marginOf(v))} of sales';
    final loss = p.net < 0;
    final cards = [
      KpiCard(
        label: 'SALES',
        icon: Icons.point_of_sale_outlined,
        tint: AppColors.blue,
        tintBg: AppColors.blueBg,
        value: dashRs(p.sales),
        sub: '${p.invoices} invoice${p.invoices == 1 ? '' : 's'}',
        trend: vs(p.sales, before?.sales ?? 0),
        spark: [for (final m in months) m.sales],
      ),
      KpiCard(
        label: 'GROSS PROFIT',
        icon: Icons.trending_up,
        tint: AppColors.navy,
        tintBg: AppColors.brandSoft,
        value: dashRs(p.gross),
        valueColor: p.gross < 0 ? AppColors.red : null,
        sub: margin(p.gross),
        trend: vs(p.gross, before?.gross ?? 0),
        spark: [for (final m in months) m.gross],
      ),
      KpiCard(
        label: 'EXPENSES',
        icon: Icons.receipt_outlined,
        tint: AppColors.amber,
        tintBg: AppColors.amberBg,
        value: dashRs(p.expenses.total),
        sub: '${p.expenses.count} expense${p.expenses.count == 1 ? '' : 's'}',
        trend: vs(p.expenses.total, before?.expenses.total ?? 0, upIsGood: false),
        spark: [for (final m in months) m.expenses.total],
        onTap: widget.onOpen == null ? null : () => widget.onOpen!('Expenses'),
      ),
      KpiCard(
        label: loss ? 'NET LOSS' : 'NET PROFIT',
        icon: Icons.account_balance_wallet_outlined,
        tint: loss ? AppColors.red : AppColors.green,
        tintBg: loss ? AppColors.redBg : AppColors.greenBg,
        value: dashRs(p.net),
        valueColor: loss ? AppColors.red : AppColors.green,
        sub: margin(p.net),
        trend: vs(p.net, before?.net ?? 0),
        spark: [for (final m in months) m.net],
      ),
    ];
    return kpiGrid(cards, wide ? 4 : 2);
  }

  Widget _costWarning(ProfitAndLoss p) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.amberBg,
          borderRadius: BorderRadius.circular(AppRadius.field),
          border: Border.all(color: AppColors.amber.withValues(alpha: 0.4)),
        ),
        child: Row(children: [
          const Icon(Icons.info_outline, size: 18, color: AppColors.amberDark),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${p.productsWithoutCost} product${p.productsWithoutCost == 1 ? ' was' : 's were'} sold without a purchase cost, '
              'so ${p.productsWithoutCost == 1 ? 'its' : 'their'} cost counts as Rs 0 and profit looks higher than it is. '
              'Record a purchase (or set the cost on the product) to fix it.',
              style: _small(color: AppColors.amberDark),
            ),
          ),
        ]),
      );

  // ---------------------------------------------------------------------------
  // The statement
  // ---------------------------------------------------------------------------

  Widget _statement(ProfitAndLoss p) {
    Widget line(String label, double amount,
        {bool bold = false, bool indent = false, bool negative = false, Color? color, String? note, bool topRule = false}) {
      return Container(
        decoration: topRule ? const BoxDecoration(border: Border(top: BorderSide(color: AppColors.text, width: 0.8))) : null,
        padding: EdgeInsets.fromLTRB(indent ? 20 : 0, 8, 0, 8),
        child: Row(children: [
          Expanded(
            child: Text(label,
                style: TextStyle(fontSize: bold ? 14 : 13, fontWeight: bold ? FontWeight.w700 : FontWeight.w400, color: AppColors.text)),
          ),
          if (note != null) Padding(padding: const EdgeInsets.only(right: 14), child: Text(note, style: _small(size: 11.5))),
          Text(
            negative ? '(${_money.format(amount.abs().round())})' : _rs(amount),
            style: TextStyle(
              fontSize: bold ? 14 : 13,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
              color: color ?? AppColors.text,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ]),
      );
    }

    return Container(
      decoration: kpiCardDecoration(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _panelTitle(Icons.description_outlined, 'Statement', _periodLabel),
          const SizedBox(height: 12),
          line('Sales', p.sales, bold: true, note: '${p.invoices} invoices'),
          line('Less: cost of goods sold', p.cost, indent: true, negative: true),
          line('Gross profit', p.gross,
              bold: true, topRule: true, note: _pct(p.marginOf(p.gross)), color: p.gross < 0 ? AppColors.red : null),
          const SizedBox(height: 10),
          Text('Expenses', style: _small(color: AppColors.text, w: FontWeight.w600)),
          if (p.expenses.byCategory.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 0, 8),
              child: Text('No expenses recorded for this period', style: _small()),
            ),
          for (final c in p.expenses.byCategory) line(c.key, c.value, indent: true, negative: true),
          line('Total expenses', p.expenses.total, topRule: true, negative: true),
          const SizedBox(height: 6),
          Container(
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.text, width: 0.8), bottom: BorderSide(color: AppColors.text, width: 2)),
            ),
            child: line(p.net < 0 ? 'Net loss' : 'Net profit', p.net,
                bold: true, note: _pct(p.marginOf(p.net)), color: p.net < 0 ? AppColors.red : AppColors.green),
          ),
          const SizedBox(height: 10),
          Text(
            'Cost of goods uses each product\'s latest purchase cost, the same as Purchases → Profit. '
            'Sales are after returns and invoice discounts.',
            style: _small(size: 11),
          ),
        ]),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Last six months
  // ---------------------------------------------------------------------------

  Widget _months(List<ProfitAndLoss> months) {
    final maxAbs = months.fold<double>(1, (m, p) => [m, p.sales, p.net.abs()].reduce((a, b) => a > b ? a : b));
    final thisMonth = DateTime(DateTime.now().year, DateTime.now().month);
    TextStyle num(bool bold, [Color? c]) => TextStyle(
        fontSize: 12.5,
        fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
        color: c ?? AppColors.text,
        fontFeatures: const [FontFeature.tabularFigures()]);
    return Container(
      decoration: kpiCardDecoration(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _panelTitle(Icons.calendar_month_outlined, 'Last six months', 'net profit by month'),
          const SizedBox(height: 14),
          Row(children: [
            const Expanded(flex: 3, child: SizedBox()),
            for (final h in const ['Sales', 'Gross', 'Expenses', 'Net'])
              Expanded(flex: 3, child: Text(h, textAlign: TextAlign.right, style: _small(size: 11.5, w: FontWeight.w600))),
          ]),
          const Divider(height: 14),
          for (final p in months.reversed) ...[
            Container(
              color: p.start == thisMonth ? AppColors.brandSoft : null,
              padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Expanded(flex: 3, child: Text(DateFormat('MMM yy').format(p.start), style: num(p.start == thisMonth))),
                  Expanded(flex: 3, child: Text(_short(p.sales), textAlign: TextAlign.right, style: num(false))),
                  Expanded(flex: 3, child: Text(_short(p.gross), textAlign: TextAlign.right, style: num(false))),
                  Expanded(flex: 3, child: Text(_short(p.expenses.total), textAlign: TextAlign.right, style: num(false))),
                  Expanded(
                    flex: 3,
                    child: Text(_short(p.net), textAlign: TextAlign.right, style: num(true, p.net < 0 ? AppColors.red : AppColors.green)),
                  ),
                ]),
                const SizedBox(height: 5),
                // Net profit as a bar against the biggest figure in the table.
                Align(
                  alignment: Alignment.centerRight,
                  child: FractionallySizedBox(
                    widthFactor: (p.net.abs() / maxAbs).clamp(0.0, 1.0),
                    child: Container(
                      height: 3,
                      decoration: BoxDecoration(
                        color: (p.net < 0 ? AppColors.red : AppColors.green).withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ]),
            ),
          ],
        ]),
      ),
    );
  }

  /// A panel heading the dashboard way: tinted icon, title, and a muted note.
  Widget _panelTitle(IconData icon, String title, String note) => Row(children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(color: AppColors.brandSoft, borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, size: 15, color: AppColors.navy),
        ),
        const SizedBox(width: 10),
        Text(title, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: AppColors.text)),
        const SizedBox(width: 8),
        Expanded(child: Text(note, style: _small(size: 11.5), overflow: TextOverflow.ellipsis)),
      ]);

  Widget _message(IconData icon, String title, String text, {Widget? action}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 40, color: AppColors.muted),
          const SizedBox(height: 12),
          Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text)),
          const SizedBox(height: 4),
          Text(text, textAlign: TextAlign.center, style: _small()),
          if (action != null) ...[const SizedBox(height: 12), action],
        ]),
      );
}

/// 1,234,567 → "12.3 L"; small amounts in full. Negative with a minus.
String _short(double v) {
  final a = v.abs();
  final s = a >= 10000000
      ? '${(a / 10000000).toStringAsFixed(2)} Cr'
      : a >= 100000
          ? '${(a / 100000).toStringAsFixed(1)} L'
          : _money.format(a.round());
  return v < -0.5 ? '−$s' : s;
}

TextStyle _small({Color color = AppColors.muted, FontWeight w = FontWeight.w400, double size = 12.5}) =>
    TextStyle(fontSize: size, fontWeight: w, color: color);

// =============================================================================
// Printed statement
// =============================================================================

Future<Uint8List> _pnlPdf(PnlData d, String periodLabel) async {
  final doc = pw.Document();
  final p = d.period;
  String amt(double v, {bool paren = false}) =>
      paren ? '(${_money.format(v.abs().round())})' : '${v < 0 ? '-' : ''}${_money.format(v.abs().round())}';

  pw.Widget row(String label, String value, {bool bold = false, bool indent = false, String note = '', pw.Border? border}) =>
      pw.Container(
        decoration: border == null ? null : pw.BoxDecoration(border: border),
        padding: pw.EdgeInsets.fromLTRB(indent ? 18 : 0, 4, 0, 4),
        child: pw.Row(children: [
          pw.Expanded(child: pw.Text(label, style: pw.TextStyle(fontSize: 10.5, fontWeight: bold ? pw.FontWeight.bold : null))),
          if (note.isNotEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.only(right: 16),
              child: pw.Text(note, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
            ),
          pw.SizedBox(
            width: 110,
            child: pw.Text(value, textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 10.5, fontWeight: bold ? pw.FontWeight.bold : null)),
          ),
        ]),
      );

  const rule = pw.Border(top: pw.BorderSide(width: 0.7));
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4.copyWith(marginLeft: 48, marginRight: 48, marginTop: 44, marginBottom: 44),
    build: (_) => [
      pw.Center(child: pw.Text(Account.companyName, style: pw.TextStyle(fontSize: 17, fontWeight: pw.FontWeight.bold))),
      pw.SizedBox(height: 2),
      pw.Center(child: pw.Text('Profit & Loss Statement', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold))),
      pw.Center(child: pw.Text(periodLabel, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700))),
      pw.SizedBox(height: 18),
      pw.Align(alignment: pw.Alignment.centerRight, child: pw.Text('Amount (Rs)', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700))),
      row('Sales', amt(p.sales), bold: true, note: '${p.invoices} invoices'),
      row('Less: cost of goods sold', amt(p.cost, paren: true), indent: true),
      row('Gross profit', amt(p.gross), bold: true, note: _pct(p.marginOf(p.gross)), border: rule),
      pw.SizedBox(height: 10),
      pw.Text('Expenses', style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold)),
      if (p.expenses.byCategory.isEmpty) row('None recorded', '-', indent: true),
      for (final c in p.expenses.byCategory) row(c.key, amt(c.value, paren: true), indent: true),
      row('Total expenses', amt(p.expenses.total, paren: true), border: rule),
      pw.SizedBox(height: 8),
      row(p.net < 0 ? 'Net loss' : 'Net profit', amt(p.net),
          bold: true,
          note: _pct(p.marginOf(p.net)),
          border: const pw.Border(top: pw.BorderSide(width: 0.7), bottom: pw.BorderSide(width: 2))),
      if (p.productsWithoutCost > 0) ...[
        pw.SizedBox(height: 10),
        pw.Text('Note: ${p.productsWithoutCost} product(s) sold without a purchase cost are counted at Rs 0 cost.',
            style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700)),
      ],
      pw.SizedBox(height: 22),
      pw.Text('Last six months', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 6),
      pw.Table(
        border: pw.TableBorder.all(color: PdfColors.grey500, width: 0.5),
        children: [
          pw.TableRow(decoration: const pw.BoxDecoration(color: PdfColors.grey300), children: [
            for (final h in const ['Month', 'Sales', 'Cost of goods', 'Gross profit', 'Expenses', 'Net'])
              pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(h, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold))),
          ]),
          for (final m in d.months)
            pw.TableRow(children: [
              for (final v in [
                DateFormat('MMM yyyy').format(m.start),
                amt(m.sales),
                amt(m.cost),
                amt(m.gross),
                amt(m.expenses.total),
                amt(m.net),
              ])
                pw.Padding(
                  padding: const pw.EdgeInsets.all(4),
                  child: pw.Text(v, textAlign: v.contains(RegExp(r'^[A-Z]')) ? pw.TextAlign.left : pw.TextAlign.right, style: const pw.TextStyle(fontSize: 9)),
                ),
            ]),
        ],
      ),
      pw.SizedBox(height: 14),
      pw.Text('Printed ${DateFormat('dd-MM-yyyy').format(DateTime.now())}. Cost of goods uses each product\'s latest purchase cost.',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
    ],
  ));
  return doc.save();
}
