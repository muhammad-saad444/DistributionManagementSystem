// Invoices → Sales tax: the month's sales tax for filing. Value without tax and tax, by rate, by
// registered and unregistered shops, and every invoice line with the shop's NTN or CNIC; Excel for
// the accountant.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../Admin/dashboard_overview.dart' show dashRs;
import '../ui/app_theme.dart';
import '../ui/excel_export.dart';
import '../ui/kpi_card.dart';
import 'company_profile.dart';
import 'company_profile_screen.dart';
import 'sales_tax_data.dart';

final _money = NumberFormat('#,##0');
final _monthName = DateFormat('MMMM yyyy');
final _day = DateFormat('d MMM');

String _pct(double r) => '${r == r.roundToDouble() ? r.toInt() : r}%';

class SalesTaxScreen extends StatefulWidget {
  const SalesTaxScreen({super.key});

  @override
  State<SalesTaxScreen> createState() => _SalesTaxScreenState();
}

class _SalesTaxScreenState extends State<SalesTaxScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  List<SalesTaxLine>? _lines;
  int _invoiceCount = 0;
  CompanyProfile? _profile;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _lines = null;
      _error = null;
    });
    try {
      final results = await Future.wait([loadSalesTax(_month), loadCompanyProfile(fresh: true)]);
      if (!mounted) return;
      final (lines, count) = results[0] as (List<SalesTaxLine>, int);
      setState(() {
        _lines = lines;
        _invoiceCount = count;
        _profile = results[1] as CompanyProfile;
      });
    } catch (e) {
      debugPrint('Sales tax: $e');
      if (mounted) setState(() => _error = e);
    }
  }

  void _shift(int months) {
    final next = DateTime(_month.year, _month.month + months);
    if (next.isAfter(DateTime.now())) return;
    setState(() => _month = next);
    _load();
  }

  void _export(List<SalesTaxLine> lines) {
    final p = _profile ?? const CompanyProfile();
    exportToExcel(
      context,
      fileName: exportFileName('sales-tax-${DateFormat('yyyy-MM').format(_month)}'),
      title: 'Sales tax · ${_monthName.format(_month)}',
      subtitle: [if (p.ntn.isNotEmpty) 'NTN ${p.ntn}', if (p.strn.isNotEmpty) 'STRN ${p.strn}'].join(' · '),
      sheets: [
        ExportSheet(
          name: 'Invoices',
          headers: ['Date', 'Invoice #', 'Buyer', 'Buyer NTN', 'Buyer CNIC', 'Registered', 'Rate %', 'Value excl. tax (Rs)', 'Sales tax (Rs)'],
          rows: [
            for (final l in lines) [l.date, l.number, l.shop, l.ntn, l.cnic, l.registered ? 'Yes' : 'No', l.rate, l.taxable, l.tax],
          ],
          totals: ['Total', null, null, null, null, null, null, lines.fold<double>(0, (s, l) => s + l.taxable), lines.fold<double>(0, (s, l) => s + l.tax)],
        ),
        ExportSheet(
          name: 'By rate',
          headers: ['Rate %', 'Value excl. tax (Rs)', 'Sales tax (Rs)'],
          rows: [for (final e in _byRate(lines).entries) [e.key, e.value.$1, e.value.$2]],
        ),
      ],
    );
  }

  Map<double, (double, double)> _byRate(List<SalesTaxLine> lines) {
    final m = <double, (double, double)>{};
    for (final l in lines) {
      final v = m[l.rate] ?? (0.0, 0.0);
      m[l.rate] = (v.$1 + l.taxable, v.$2 + l.tax);
    }
    return Map.fromEntries(m.entries.toList()..sort((a, b) => b.key.compareTo(a.key)));
  }

  @override
  Widget build(BuildContext context) {
    final lines = _lines;
    final now = DateTime.now();
    final isThisMonth = _month.year == now.year && _month.month == now.month;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sales tax'),
        actions: [
          ExcelButton(onPressed: lines == null || lines.isEmpty ? null : () => _export(lines)),
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
                  Row(children: [
                    Container(
                      decoration: kpiCardDecoration(),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => _shift(-1)),
                        Text(_monthName.format(_month), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                        IconButton(icon: const Icon(Icons.chevron_right), onPressed: isThisMonth ? null : () => _shift(1)),
                      ]),
                    ),
                    const SizedBox(width: 16),
                    if (_profile != null)
                      Expanded(
                        child: Text(
                          _profile!.taxEnabled
                              ? 'Sales tax is on: ${_pct(_profile!.taxRate)}, ${_profile!.taxInclusive ? 'included in prices' : 'added on top'}'
                              : 'Sales tax is off for new invoices',
                          textAlign: TextAlign.right,
                          style: const TextStyle(fontSize: 12, color: AppColors.muted),
                        ),
                      ),
                  ]),
                  const SizedBox(height: 16),
                  if (lines == null)
                    _error != null
                        ? _panel(child: _empty(Icons.cloud_off, "Couldn't load", 'Check the connection and try again.'))
                        : const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator()))
                  else if (lines.isEmpty)
                    _panel(
                      child: Column(children: [
                        _empty(
                          Icons.percent,
                          'No invoices with sales tax in ${_monthName.format(_month)}',
                          _profile?.taxEnabled == true
                              ? 'Invoices made from now on carry sales tax.'
                              : 'Switch sales tax on in Settings → Company details & sales tax. Invoices made after that carry it.',
                        ),
                        if (_profile?.taxEnabled != true)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 20),
                            child: FilledButton(
                              onPressed: () async {
                                await Navigator.push(context, MaterialPageRoute(builder: (_) => const CompanyProfileScreen()));
                                _load();
                              },
                              child: const Text('Open sales tax settings'),
                            ),
                          ),
                      ]),
                    )
                  else ...[
                    _kpis(lines, wide),
                    const SizedBox(height: 16),
                    if (wide)
                      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(flex: 4, child: _ratesPanel(lines)),
                        const SizedBox(width: 16),
                        Expanded(flex: 8, child: _listPanel(lines)),
                      ])
                    else ...[
                      _ratesPanel(lines),
                      const SizedBox(height: 16),
                      _listPanel(lines),
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

  Widget _kpis(List<SalesTaxLine> lines, bool wide) {
    final taxable = lines.fold<double>(0, (s, l) => s + l.taxable);
    final tax = lines.fold<double>(0, (s, l) => s + l.tax);
    final invoices = {for (final l in lines) l.invoiceId}.length;
    final regTax = lines.where((l) => l.registered).fold<double>(0, (s, l) => s + l.tax);
    final unregShops = {for (final l in lines) if (!l.registered) l.shop.toLowerCase()}.length;
    return kpiGrid([
      KpiCard(
        label: 'SALES EXCL. TAX',
        icon: Icons.receipt_long_outlined,
        tint: AppColors.navy,
        tintBg: AppColors.brandSoft,
        value: dashRs(taxable),
        sub: 'value of goods without tax',
      ),
      KpiCard(
        label: 'SALES TAX',
        icon: Icons.percent,
        tint: AppColors.amber,
        tintBg: AppColors.amberBg,
        value: dashRs(tax),
        sub: 'to declare for the month',
      ),
      KpiCard(
        label: 'INVOICES WITH TAX',
        icon: Icons.fact_check_outlined,
        tint: AppColors.blue,
        tintBg: AppColors.blueBg,
        value: '$invoices',
        sub: 'of $_invoiceCount this month',
        progress: _invoiceCount == 0 ? null : invoices / _invoiceCount,
      ),
      KpiCard(
        label: 'TO REGISTERED SHOPS',
        icon: Icons.verified_outlined,
        tint: AppColors.green,
        tintBg: AppColors.greenBg,
        value: tax == 0 ? '—' : '${(regTax / tax * 100).toStringAsFixed(0)}%',
        sub: unregShops == 0 ? 'every shop has an NTN' : '$unregShops shop${unregShops == 1 ? '' : 's'} without an NTN',
        progress: tax == 0 ? null : regTax / tax,
      ),
    ], wide ? 4 : 2);
  }

  Widget _ratesPanel(List<SalesTaxLine> lines) => _panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _title(Icons.donut_small_outlined, 'By rate', 'value excl. tax · tax'),
          const SizedBox(height: 12),
          for (final e in _byRate(lines).entries) ...[
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: e.key == 0 ? AppColors.bg : AppColors.amberBg, borderRadius: BorderRadius.circular(20)),
                child: Text(e.key == 0 ? 'Exempt' : _pct(e.key),
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: e.key == 0 ? AppColors.muted : AppColors.amberDark)),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text('Rs ${_money.format(e.value.$1.round())}', style: const TextStyle(fontSize: 13, color: AppColors.text))),
              Text('Rs ${_money.format(e.value.$2.round())}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.text)),
            ]),
            const Divider(height: 20),
          ],
          const Text(
            'Shops without an NTN show their CNIC in the Excel file. Add NTNs to shops under Customers.',
            style: TextStyle(fontSize: 11.5, color: AppColors.muted),
          ),
        ]),
      );

  Widget _listPanel(List<SalesTaxLine> lines) => _panel(
        padding: const EdgeInsets.fromLTRB(0, 18, 0, 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: _title(Icons.list_alt_outlined, 'Invoices', 'by date')),
          const SizedBox(height: 8),
          for (var i = 0; i < lines.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 20, endIndent: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Row(children: [
                SizedBox(width: 52, child: Text(_day.format(lines[i].date), style: const TextStyle(fontSize: 12, color: AppColors.muted))),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('#${lines[i].number} · ${lines[i].shop}',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.text), overflow: TextOverflow.ellipsis),
                    Text(
                      [
                        lines[i].registered ? 'NTN ${lines[i].ntn}' : (lines[i].cnic.isNotEmpty ? 'CNIC ${lines[i].cnic}' : 'No NTN or CNIC'),
                        lines[i].rate == 0 ? 'exempt' : _pct(lines[i].rate),
                      ].join(' · '),
                      style: TextStyle(fontSize: 11.5, color: lines[i].registered ? AppColors.muted : AppColors.amberDark),
                    ),
                  ]),
                ),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('Rs ${_money.format(lines[i].tax.round())}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.text)),
                  Text('on Rs ${_money.format(lines[i].taxable.round())}', style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
                ]),
              ]),
            ),
          ],
        ]),
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
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 38, color: AppColors.muted),
          const SizedBox(height: 10),
          Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.text)),
          const SizedBox(height: 4),
          Text(text, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
        ]),
      );
}
