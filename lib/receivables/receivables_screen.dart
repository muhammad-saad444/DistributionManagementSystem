// Admin: what the market owes the company, across every booker, split by how long it has been
// unpaid. View by shop, by booker or by area; filter, search, open a shop's khata, print.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../account/account.dart';
import '../khata.dart' show KhataShopScreen;
import '../print_preview.dart';
import '../ui/app_theme.dart';
import '../ui/excel_export.dart';
import 'receivables_data.dart';

final _money = NumberFormat('#,##0');
String _rs(num v) => 'Rs ${_money.format(v.round())}';

// One colour per age bucket: fresh to worrying.
const _bucketColors = [AppColors.green, AppColors.blue, AppColors.amber, AppColors.red];

enum _View { shops, bookers, areas }

class ReceivablesScreen extends StatefulWidget {
  const ReceivablesScreen({super.key});

  @override
  State<ReceivablesScreen> createState() => _ReceivablesScreenState();
}

class _ReceivablesScreenState extends State<ReceivablesScreen> {
  List<ShopReceivable>? _rows;
  Object? _error;
  bool _loading = false;

  _View _view = _View.shops;
  String? _booker; // uid, null = all
  String? _area; // null = all
  int _minBucket = 0; // 0 = everything, 1 = over 30 days, 2 = over 60, 3 = over 90
  String _search = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await loadReceivables();
      if (mounted) setState(() => _rows = rows);
    } catch (e) {
      debugPrint('Receivables: $e');
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Rows after the filters, with each shop's ageing cut to the chosen age (e.g. only over 60 days).
  List<ShopReceivable> get _filtered {
    final q = _search.trim().toLowerCase();
    final out = <ShopReceivable>[];
    for (final r in _rows ?? const <ShopReceivable>[]) {
      if (_booker != null && r.bookerUid != _booker) continue;
      if (_area != null && r.area != _area) continue;
      if (q.isNotEmpty && !r.shop.toLowerCase().contains(q) && !r.bookerName.toLowerCase().contains(q)) continue;
      if (_minBucket > 0) {
        final b = r.ageing.buckets;
        final kept = Ageing();
        if (_minBucket <= 1) kept.d31to60 = b[1];
        if (_minBucket <= 2) kept.d61to90 = b[2];
        kept.over90 = b[3];
        if (kept.total < 0.5) continue;
        out.add(ShopReceivable(
          bookerUid: r.bookerUid,
          bookerName: r.bookerName,
          shop: r.shop,
          area: r.area,
          ageing: kept,
          oldestDays: r.oldestDays,
          openInvoices: r.openInvoices,
          lastPayment: r.lastPayment,
          creditLimit: r.creditLimit,
        ));
      } else {
        out.add(r);
      }
    }
    return out;
  }

  String get _filterText {
    final parts = <String>[
      if (_booker != null) 'Booker: ${_rows?.firstWhere((r) => r.bookerUid == _booker).bookerName}',
      if (_area != null) 'Area: $_area',
      if (_minBucket > 0) 'Only over ${const [0, 30, 60, 90][_minBucket]} days',
      if (_search.trim().isNotEmpty) 'Search: ${_search.trim()}',
    ];
    return parts.isEmpty ? 'All shops' : parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final rows = _filtered;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Receivables'),
        actions: [
          ExcelButton(
            onPressed: _rows == null || rows.isEmpty
                ? null
                : () => exportToExcel(
                      context,
                      fileName: exportFileName('receivables'),
                      title: 'Receivables ageing',
                      subtitle: _filterText,
                      sheets: [
                        ExportSheet(
                          name: 'Shops',
                          headers: ['Shop', 'Booker', 'Area', '0-30 days', '31-60 days', '61-90 days', 'Over 90 days', 'Total owed',
                            'Oldest unpaid (days)', 'Open invoices', 'Last payment', 'Credit limit'],
                          rows: [
                            for (final r in rows)
                              [r.shop, r.bookerName, r.area, ...r.ageing.buckets, r.total, r.oldestDays, r.openInvoices, r.lastPayment,
                                r.creditLimit > 0 ? r.creditLimit : null],
                          ],
                          totals: ['Total', null, null, ...totalAgeing(rows).buckets, totalAgeing(rows).total],
                        ),
                        for (final (name, key) in [('Bookers', (ShopReceivable r) => r.bookerName), ('Areas', (ShopReceivable r) => r.area)])
                          ExportSheet(
                            name: name,
                            headers: [name == 'Bookers' ? 'Booker' : 'Area', 'Shops', '0-30 days', '31-60 days', '61-90 days', 'Over 90 days', 'Total owed'],
                            rows: [for (final g in groupReceivables(rows, key)) [g.name, g.shops, ...g.ageing.buckets, g.ageing.total]],
                          ),
                      ],
                    ),
          ),
          IconButton(
            tooltip: 'Print',
            icon: const Icon(Icons.print_outlined),
            onPressed: _rows == null || rows.isEmpty
                ? null
                : () => showPrintPreview(
                      context,
                      title: 'Receivables ageing',
                      fileName: 'receivables-${DateFormat('yyyy-MM-dd').format(DateTime.now())}.pdf',
                      buildPdf: () => _ageingPdf(rows, _filterText),
                    ),
          ),
          IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh), onPressed: _loading ? null : _load),
          const SizedBox(width: 6),
        ],
        bottom: _loading && _rows != null
            ? const PreferredSize(preferredSize: Size.fromHeight(2), child: LinearProgressIndicator(minHeight: 2))
            : null,
      ),
      body: _body(rows),
    );
  }

  Widget _body(List<ShopReceivable> rows) {
    if (_rows == null) {
      if (_error != null) {
        return _message(Icons.cloud_off, "Couldn't load receivables", 'Check the connection and try again.',
            action: TextButton(onPressed: _load, child: const Text('Try again')));
      }
      return const Center(child: CircularProgressIndicator());
    }
    final all = _rows!;
    final t = totalAgeing(rows);
    return RefreshIndicator(
      onRefresh: _load,
      child: LayoutBuilder(builder: (context, box) {
        final wide = box.maxWidth >= 760;
        return ListView(
          padding: EdgeInsets.fromLTRB(wide ? 24 : 14, 18, wide ? 24 : 14, 32),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1180),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  _summary(t, rows.length, wide),
                  const SizedBox(height: 14),
                  _filters(all, wide),
                  const SizedBox(height: 14),
                  if (all.isEmpty)
                    _message(Icons.verified_outlined, 'Nothing owed', 'No shop owes the company anything right now.')
                  else if (rows.isEmpty)
                    _message(Icons.filter_alt_off_outlined, 'No shops match', 'Change the filters to see more.')
                  else
                    switch (_view) {
                      _View.shops => _shopList(rows, wide),
                      _View.bookers => _groupList(groupReceivables(rows, (r) => r.bookerName), 'Booker', wide),
                      _View.areas => _groupList(groupReceivables(rows, (r) => r.area), 'Area', wide),
                    },
                ]),
              ),
            ),
          ],
        );
      }),
    );
  }

  // ---------------------------------------------------------------------------
  // Summary: the total, an ageing bar, and one tile per age (tap to filter)
  // ---------------------------------------------------------------------------

  Widget _summary(Ageing t, int shops, bool wide) {
    final total = t.total;
    final tiles = [
      for (var i = 0; i < 4; i++)
        _bucketTile(i, t.buckets[i], total),
    ];
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('TOTAL OWED BY THE MARKET', style: _caps()),
                const SizedBox(height: 6),
                Text(_rs(total), style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('$shops shop${shops == 1 ? '' : 's'}', style: _small(w: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(total < 0.5 ? '' : '${(t.overdue / total * 100).toStringAsFixed(0)}% older than 30 days',
                  style: _small(color: t.overdue > 0.5 ? AppColors.red : AppColors.muted)),
            ]),
          ]),
          const SizedBox(height: 14),
          _ageBar(t.buckets, total, height: 10),
          const SizedBox(height: 16),
          if (wide)
            Row(children: [
              for (var i = 0; i < 4; i++) ...[if (i > 0) const SizedBox(width: 10), Expanded(child: tiles[i])],
            ])
          else
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 2.2,
              children: tiles,
            ),
        ]),
      ),
    );
  }

  Widget _bucketTile(int i, double amount, double total) {
    // Tapping an older bucket shows only debt at least that old; tapping again clears it.
    final selected = _minBucket > 0 && _minBucket == i;
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.field),
      onTap: i == 0 ? null : () => setState(() => _minBucket = selected ? 0 : i),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.brandSoft : AppColors.bg,
          borderRadius: BorderRadius.circular(AppRadius.field),
          border: Border.all(color: selected ? AppColors.navy : Colors.transparent),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
          Row(children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: _bucketColors[i], shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Expanded(child: Text(ageingLabels[i], style: _small(), overflow: TextOverflow.ellipsis)),
          ]),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(_rs(amount),
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: i == 3 && amount > 0.5 ? AppColors.red : AppColors.text)),
          ),
          Text(total < 0.5 ? '' : '${(amount / total * 100).toStringAsFixed(0)}%', style: _small()),
        ]),
      ),
    );
  }

  Widget _ageBar(List<double> buckets, double total, {double height = 6}) {
    if (total < 0.5) return Container(height: height, decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(height)));
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: SizedBox(
        height: height,
        child: Row(children: [
          for (var i = 0; i < 4; i++)
            if (buckets[i] > 0.5) Expanded(flex: (buckets[i] / total * 1000).round().clamp(1, 1000), child: Container(color: _bucketColors[i])),
        ]),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Filters
  // ---------------------------------------------------------------------------

  Widget _filters(List<ShopReceivable> all, bool wide) {
    final bookers = <String, String>{for (final r in all) r.bookerUid: r.bookerName};
    final areas = {for (final r in all) r.area}.toList()..sort();
    final view = SegmentedButton<_View>(
      segments: const [
        ButtonSegment(value: _View.shops, label: Text('Shops'), icon: Icon(Icons.storefront_outlined, size: 18)),
        ButtonSegment(value: _View.bookers, label: Text('Bookers'), icon: Icon(Icons.person_outline, size: 18)),
        ButtonSegment(value: _View.areas, label: Text('Areas'), icon: Icon(Icons.map_outlined, size: 18)),
      ],
      selected: {_view},
      showSelectedIcon: false,
      onSelectionChanged: (s) => setState(() => _view = s.first),
      style: SegmentedButton.styleFrom(
        selectedBackgroundColor: AppColors.navy,
        selectedForegroundColor: Colors.white,
        side: const BorderSide(color: AppColors.border),
      ),
    );
    Widget drop<T>(String label, T? value, Map<T, String> items, void Function(T?) on) => SizedBox(
          width: wide ? 190 : double.infinity,
          child: DropdownButtonFormField<T?>(
            key: ValueKey('$label-$value'), // rebuilt when a drill-down sets it
            initialValue: value,
            isExpanded: true,
            decoration: InputDecoration(labelText: label),
            items: [
              DropdownMenuItem<T?>(value: null, child: Text('All', style: _small(color: AppColors.text))),
              for (final e in items.entries)
                DropdownMenuItem<T?>(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis, style: _small(color: AppColors.text))),
            ],
            onChanged: (v) => setState(() => on(v)),
          ),
        );
    final search = SizedBox(
      width: wide ? 230 : double.infinity,
      child: TextField(
        decoration: const InputDecoration(hintText: 'Search shop or booker', prefixIcon: Icon(Icons.search, size: 20)),
        onChanged: (v) => setState(() => _search = v),
      ),
    );
    final bookerDrop = drop<String>('Booker', _booker, bookers, (v) => _booker = v);
    final areaDrop = drop<String>('Area', _area, {for (final a in areas) a: a}, (v) => _area = v);
    if (wide) {
      return Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
        view,
        bookerDrop,
        areaDrop,
        search,
        if (_minBucket > 0) _clearAge(),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      view,
      const SizedBox(height: 10),
      Row(children: [Expanded(child: bookerDrop), const SizedBox(width: 10), Expanded(child: areaDrop)]),
      const SizedBox(height: 10),
      search,
      if (_minBucket > 0) ...[const SizedBox(height: 8), Align(alignment: Alignment.centerLeft, child: _clearAge())],
    ]);
  }

  Widget _clearAge() => InputChip(
        label: Text('Only over ${const [0, 30, 60, 90][_minBucket]} days'),
        onDeleted: () => setState(() => _minBucket = 0),
      );

  // ---------------------------------------------------------------------------
  // Shops
  // ---------------------------------------------------------------------------

  Widget _shopList(List<ShopReceivable> rows, bool wide) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        if (wide) _tableHeader('Shop'),
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const Divider(height: 1),
          wide ? _shopRowWide(rows[i]) : _shopRowNarrow(rows[i]),
        ],
        if (wide) ...[const Divider(height: 1), _totalRow(totalAgeing(rows))],
      ]),
    );
  }

  Widget _tableHeader(String first) => Container(
        color: AppColors.bg,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(children: [
          Expanded(flex: 5, child: Text(first.toUpperCase(), style: _caps())),
          for (final l in const ['0–30', '31–60', '61–90', '90+', 'TOTAL'])
            Expanded(flex: 2, child: Text(l, textAlign: TextAlign.right, style: _caps())),
        ]),
      );

  List<Widget> _amountCells(Ageing a) => [
        for (var i = 0; i < 4; i++)
          Expanded(
            flex: 2,
            child: Text(
              a.buckets[i] < 0.5 ? '–' : _money.format(a.buckets[i].round()),
              textAlign: TextAlign.right,
              style: _small(color: a.buckets[i] < 0.5 ? AppColors.muted : (i == 3 ? AppColors.red : AppColors.text)),
            ),
          ),
        Expanded(
          flex: 2,
          child: Text(_money.format(a.total.round()), textAlign: TextAlign.right, style: _small(color: AppColors.text, w: FontWeight.w700)),
        ),
      ];

  Widget _shopRowWide(ShopReceivable r) => InkWell(
        onTap: () => _openShop(r),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          child: Row(children: [
            Expanded(
              flex: 5,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(child: Text(r.shop, overflow: TextOverflow.ellipsis, style: _small(color: AppColors.text, w: FontWeight.w600))),
                  if (r.overLimit) ...[const SizedBox(width: 6), _badge('Over limit', AppColors.red, AppColors.redBg)],
                ]),
                const SizedBox(height: 2),
                Text(_shopSub(r), overflow: TextOverflow.ellipsis, style: _small(size: 11.5)),
              ]),
            ),
            ..._amountCells(r.ageing),
          ]),
        ),
      );

  Widget _shopRowNarrow(ShopReceivable r) => InkWell(
        onTap: () => _openShop(r),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(r.shop, style: _small(color: AppColors.text, w: FontWeight.w600, size: 14)),
                  const SizedBox(height: 2),
                  Text(_shopSub(r), style: _small(size: 11.5)),
                ]),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(_rs(r.total), style: _small(color: AppColors.text, w: FontWeight.w700, size: 14)),
                if (r.overLimit) ...[const SizedBox(height: 4), _badge('Over limit', AppColors.red, AppColors.redBg)],
              ]),
            ]),
            const SizedBox(height: 10),
            _ageBar(r.ageing.buckets, r.total),
          ]),
        ),
      );

  String _shopSub(ShopReceivable r) {
    final paid = r.lastPayment == null ? 'no payment yet' : 'last paid ${DateFormat('d MMM').format(r.lastPayment!)}';
    return '${r.bookerName} · ${r.area} · oldest ${r.oldestDays} day${r.oldestDays == 1 ? '' : 's'} · $paid';
  }

  Widget _totalRow(Ageing t) => Container(
        color: AppColors.bg,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        child: Row(children: [
          Expanded(flex: 5, child: Text('Total', style: _small(color: AppColors.text, w: FontWeight.w700))),
          ..._amountCells(t),
        ]),
      );

  void _openShop(ShopReceivable r) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => KhataShopScreen(userId: r.bookerUid, bookerName: r.bookerName, customer: r.shop, readOnly: true),
    ));
  }

  // ---------------------------------------------------------------------------
  // Bookers / areas
  // ---------------------------------------------------------------------------

  Widget _groupList(List<ReceivableGroup> groups, String what, bool wide) {
    final total = groups.fold<double>(0, (s, g) => s + g.ageing.total);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        if (wide) _tableHeader(what),
        for (var i = 0; i < groups.length; i++) ...[
          if (i > 0) const Divider(height: 1),
          InkWell(
            onTap: () => setState(() {
              // Drill down: that booker's (or area's) shops.
              if (what == 'Booker') {
                _booker = _rows!.firstWhere((r) => r.bookerName == groups[i].name).bookerUid;
              } else {
                _area = groups[i].name;
              }
              _view = _View.shops;
            }),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: wide ? 16 : 14, vertical: 12),
              child: wide
                  ? Row(children: [
                      Expanded(flex: 5, child: _groupName(groups[i], total)),
                      ..._amountCells(groups[i].ageing),
                    ])
                  : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Row(children: [
                        Expanded(child: _groupName(groups[i], total)),
                        Text(_rs(groups[i].ageing.total), style: _small(color: AppColors.text, w: FontWeight.w700, size: 14)),
                      ]),
                      const SizedBox(height: 10),
                      _ageBar(groups[i].ageing.buckets, groups[i].ageing.total),
                    ]),
            ),
          ),
        ],
        if (wide) ...[
          const Divider(height: 1),
          _totalRow(groups.fold(Ageing(), (a, g) => a..addAll(g.ageing))),
        ],
      ]),
    );
  }

  Widget _groupName(ReceivableGroup g, double total) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(g.name, overflow: TextOverflow.ellipsis, style: _small(color: AppColors.text, w: FontWeight.w600, size: 14)),
        const SizedBox(height: 2),
        Text(
          '${g.shops} shop${g.shops == 1 ? '' : 's'} · ${total < 0.5 ? 0 : (g.ageing.total / total * 100).toStringAsFixed(0)}% of the total',
          style: _small(size: 11.5),
        ),
      ]);

  // ---------------------------------------------------------------------------
  // Small pieces
  // ---------------------------------------------------------------------------

  Widget _badge(String text, Color fg, Color bg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
        child: Text(text, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: fg)),
      );

  Widget _message(IconData icon, String title, String text, {Widget? action}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 40, color: AppColors.muted),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text)),
          const SizedBox(height: 4),
          Text(text, textAlign: TextAlign.center, style: _small()),
          if (action != null) ...[const SizedBox(height: 12), action],
        ]),
      );

  TextStyle _caps() => const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: AppColors.muted);
  TextStyle _small({Color color = AppColors.muted, FontWeight w = FontWeight.w400, double size = 12.5}) =>
      TextStyle(fontSize: size, fontWeight: w, color: color);
}

// =============================================================================
// Printed ageing report
// =============================================================================

Future<Uint8List> _ageingPdf(List<ShopReceivable> rows, String filters) async {
  final doc = pw.Document();
  final t = totalAgeing(rows);
  String m(double v) => v < 0.5 ? '-' : _money.format(v.round());
  pw.Widget cell(String s, {bool right = false, bool bold = false, PdfColor? color}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        child: pw.Text(s,
            textAlign: right ? pw.TextAlign.right : pw.TextAlign.left,
            style: pw.TextStyle(fontSize: 8.5, fontWeight: bold ? pw.FontWeight.bold : null, color: color)),
      );

  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4.landscape.copyWith(marginLeft: 30, marginRight: 30, marginTop: 30, marginBottom: 30),
    footer: (ctx) => pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
    ),
    build: (_) => [
      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
        pw.Text(Account.companyName, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
        pw.Text('Receivables ageing', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
        pw.Text(DateFormat('dd-MM-yyyy').format(DateTime.now()), style: const pw.TextStyle(fontSize: 10)),
      ]),
      pw.SizedBox(height: 4),
      pw.Text(filters, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
      pw.SizedBox(height: 10),
      pw.Row(children: [
        for (var i = 0; i < 4; i++)
          pw.Expanded(
            child: pw.Container(
              margin: pw.EdgeInsets.only(right: i < 3 ? 6 : 0),
              padding: const pw.EdgeInsets.all(6),
              decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey400, width: 0.5)),
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Text(ageingLabels[i], style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
                pw.Text('Rs ${m(t.buckets[i])}', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
              ]),
            ),
          ),
      ]),
      pw.SizedBox(height: 10),
      pw.Table(
        border: pw.TableBorder.all(color: PdfColors.grey500, width: 0.5),
        columnWidths: const {
          0: pw.FixedColumnWidth(22),
          1: pw.FlexColumnWidth(3),
          2: pw.FlexColumnWidth(2),
          3: pw.FlexColumnWidth(1.6),
          4: pw.FixedColumnWidth(40),
          5: pw.FlexColumnWidth(1.4),
          6: pw.FlexColumnWidth(1.4),
          7: pw.FlexColumnWidth(1.4),
          8: pw.FlexColumnWidth(1.4),
          9: pw.FlexColumnWidth(1.6),
        },
        children: [
          pw.TableRow(repeat: true, decoration: const pw.BoxDecoration(color: PdfColors.grey300), children: [
            cell('#', bold: true),
            cell('Shop', bold: true),
            cell('Booker', bold: true),
            cell('Area', bold: true),
            cell('Oldest', bold: true, right: true),
            cell('0-30', bold: true, right: true),
            cell('31-60', bold: true, right: true),
            cell('61-90', bold: true, right: true),
            cell('90+', bold: true, right: true),
            cell('Total', bold: true, right: true),
          ]),
          for (var i = 0; i < rows.length; i++)
            pw.TableRow(children: [
              cell('${i + 1}'),
              cell(rows[i].shop),
              cell(rows[i].bookerName),
              cell(rows[i].area),
              cell('${rows[i].oldestDays}d', right: true),
              cell(m(rows[i].ageing.d0to30), right: true),
              cell(m(rows[i].ageing.d31to60), right: true),
              cell(m(rows[i].ageing.d61to90), right: true),
              cell(m(rows[i].ageing.over90), right: true, color: rows[i].ageing.over90 > 0.5 ? PdfColors.red800 : null),
              cell(m(rows[i].total), right: true, bold: true),
            ]),
          pw.TableRow(decoration: const pw.BoxDecoration(color: PdfColors.grey200), children: [
            cell(''),
            cell('Total (${rows.length} shops)', bold: true),
            cell(''),
            cell(''),
            cell(''),
            cell(m(t.d0to30), right: true, bold: true),
            cell(m(t.d31to60), right: true, bold: true),
            cell(m(t.d61to90), right: true, bold: true),
            cell(m(t.over90), right: true, bold: true),
            cell(m(t.total), right: true, bold: true),
          ]),
        ],
      ),
    ],
  ));
  return doc.save();
}
