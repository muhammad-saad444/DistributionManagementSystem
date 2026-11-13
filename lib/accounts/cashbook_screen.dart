// Admin: the cash and bank book. Balances of cash in hand, the bank and mobile wallets; what came
// in and went out in a period; a ledger with a running balance; manual entries for opening
// balances, transfers (cash deposited in the bank) and other money in or out; print.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../Admin/dashboard_overview.dart' show dashRs;
import '../account/account.dart';
import '../audit/audit.dart';
import '../print_preview.dart';
import '../ui/app_theme.dart';
import '../ui/excel_export.dart';
import '../ui/kpi_card.dart';
import 'cashbook_data.dart';

final _money = NumberFormat('#,##0');
String _rs(num v) => '${v < 0 ? '−' : ''}Rs ${_money.format(v.abs().round())}';
final _dmy = DateFormat('d MMM yyyy');

enum _Period { thisMonth, lastMonth, thisYear, custom }

class CashBookScreen extends StatefulWidget {
  const CashBookScreen({super.key});

  @override
  State<CashBookScreen> createState() => _CashBookScreenState();
}

class _CashBookScreenState extends State<CashBookScreen> {
  List<CashLine>? _all;
  Object? _error;
  bool _loading = false;
  _Period _period = _Period.thisMonth;
  DateTimeRange? _custom;
  MoneyAccount? _account; // null = all accounts

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
      final lines = await loadCashLines();
      if (mounted) setState(() => _all = lines);
    } catch (e) {
      debugPrint('Cash book: $e');
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  (DateTime, DateTime) get _range {
    final n = DateTime.now();
    return switch (_period) {
      _Period.thisMonth => (DateTime(n.year, n.month), DateTime(n.year, n.month + 1)),
      _Period.lastMonth => (DateTime(n.year, n.month - 1), DateTime(n.year, n.month)),
      _Period.thisYear => (DateTime(n.year), DateTime(n.year + 1)),
      _Period.custom => (
          DateTime(_custom!.start.year, _custom!.start.month, _custom!.start.day),
          DateTime(_custom!.end.year, _custom!.end.month, _custom!.end.day + 1),
        ),
    };
  }

  String get _periodLabel {
    final (s, e) = _range;
    if (s.day == 1 && e == DateTime(s.year, s.month + 1)) return DateFormat('MMMM yyyy').format(s);
    if (s.month == 1 && s.day == 1 && e == DateTime(s.year + 1)) return 'Year ${s.year}';
    return '${_dmy.format(s)} – ${_dmy.format(e.subtract(const Duration(days: 1)))}';
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
  }

  Future<void> _entry({CashEntryType type = CashEntryType.moneyIn, String? id}) async {
    CashEntry? existing;
    if (id != null) {
      existing = await loadCashEntry(id);
      if (existing == null || !mounted) return;
    }
    final done = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _EntrySheet(entry: existing, type: existing?.type ?? type),
    );
    if (done != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
      _load();
    }
  }

  /// The book as an Excel file: the ledger shown (all accounts or the one chosen) and a summary.
  void _export(CashPeriod p) {
    final a = _account;
    final lines = p.lines.where((l) => a == null || l.account == a).toList();
    var bal = a == null ? p.totalOpening : (p.opening[a] ?? 0);
    final opening = bal;
    final rows = <List<Object?>>[];
    for (final l in lines) {
      bal += l.amount;
      rows.add([l.date, l.title, l.account.label, l.note, l.amount > 0 ? l.amount : null, l.amount < 0 ? -l.amount : null, bal]);
    }
    exportToExcel(
      context,
      fileName: exportFileName(a == null ? 'cash-and-bank-book' : '${a.short}-book'),
      title: a == null ? 'Cash & bank book' : '${a.label} book',
      subtitle: _periodLabel,
      sheets: [
        ExportSheet(
          name: 'Ledger',
          headers: ['Date', 'Details', 'Account', 'Note', 'In (Rs)', 'Out (Rs)', 'Balance (Rs)'],
          rows: [
            [p.start, 'Opening balance', null, null, null, null, opening],
            ...rows,
          ],
          totals: ['Closing balance', null, null, null, rows.fold<double>(0, (s, r) => s + ((r[4] as num?) ?? 0)),
            rows.fold<double>(0, (s, r) => s + ((r[5] as num?) ?? 0)), bal],
        ),
        ExportSheet(
          name: 'Accounts',
          headers: ['Account', 'Opening', 'In', 'Out', 'Closing'],
          rows: [
            for (final acc in MoneyAccount.values)
              [acc.label, p.opening[acc] ?? 0, p.moneyIn[acc] ?? 0, p.moneyOut[acc] ?? 0, p.closing(acc)],
          ],
          totals: ['Total', p.totalOpening, p.totalIn, p.totalOut, p.totalClosing],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final all = _all;
    final (start, end) = _range;
    final p = all == null ? null : cashPeriod(all, start, end);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cash & bank book'),
        actions: [
          ExcelButton(onPressed: p == null ? null : () => _export(p)),
          IconButton(
            tooltip: 'Print',
            icon: const Icon(Icons.print_outlined),
            onPressed: p == null
                ? null
                : () => showPrintPreview(
                      context,
                      title: 'Cash & bank book · $_periodLabel',
                      fileName: 'cash-book-${DateFormat('yyyy-MM-dd').format(start)}.pdf',
                      buildPdf: () => _bookPdf(p, _account, _periodLabel),
                    ),
          ),
          IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh), onPressed: _loading ? null : _load),
          const SizedBox(width: 6),
        ],
        bottom: _loading && all != null
            ? const PreferredSize(preferredSize: Size.fromHeight(2), child: LinearProgressIndicator(minHeight: 2))
            : null,
      ),
      body: LayoutBuilder(builder: (context, box) {
        final wide = box.maxWidth >= 860;
        final pad = wide ? 24.0 : 14.0;
        return RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: EdgeInsets.fromLTRB(pad, 18, pad, 32),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1180),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    _header(wide),
                    const SizedBox(height: 16),
                    if (p == null)
                      _error != null
                          ? _panel(
                              child: _message(Icons.cloud_off, "Couldn't load the cash book", 'Check the connection and try again.',
                                  action: TextButton(onPressed: _load, child: const Text('Try again'))))
                          : const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator()))
                    else ...[
                      _kpis(p, wide),
                      if (all!.isEmpty) ...[
                        const SizedBox(height: 16),
                        _panel(
                          child: _message(
                            Icons.account_balance_wallet_outlined,
                            'Start with your opening balances',
                            'Enter how much cash you have in hand and in the bank today. From then on, shop payments, '
                                'expenses and supplier payments flow into this book by themselves.',
                            action: FilledButton.icon(
                              onPressed: () => _entry(type: CashEntryType.opening),
                              icon: const Icon(Icons.add),
                              label: const Text('Set opening balance'),
                            ),
                          ),
                        ),
                      ] else ...[
                        const SizedBox(height: 16),
                        _ledger(p, wide),
                      ],
                    ],
                  ]),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  Widget _header(bool wide) {
    const labels = {
      _Period.thisMonth: 'This month',
      _Period.lastMonth: 'Last month',
      _Period.thisYear: 'This year',
      _Period.custom: 'Choose dates',
    };
    final chips = Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
      for (final p in _Period.values)
        ChoiceChip(
          label: Text(labels[p]!),
          avatar: p == _Period.custom ? const Icon(Icons.date_range, size: 16) : null,
          selected: _period == p,
          showCheckmark: false,
          onSelected: (_) => _choose(p),
        ),
      Padding(padding: const EdgeInsets.only(left: 4), child: Text(_periodLabel, style: _small(w: FontWeight.w600))),
    ]);
    final add = PopupMenuButton<CashEntryType>(
      tooltip: 'New entry',
      onSelected: (t) => _entry(type: t),
      itemBuilder: (_) => const [
        PopupMenuItem(value: CashEntryType.moneyIn, child: ListTile(leading: Icon(Icons.south_west), title: Text('Money in'), subtitle: Text('capital, other income'))),
        PopupMenuItem(value: CashEntryType.moneyOut, child: ListTile(leading: Icon(Icons.north_east), title: Text('Money out'), subtitle: Text('drawings, other payments'))),
        PopupMenuItem(value: CashEntryType.transfer, child: ListTile(leading: Icon(Icons.swap_horiz), title: Text('Transfer'), subtitle: Text('e.g. cash deposited in bank'))),
        PopupMenuItem(value: CashEntryType.opening, child: ListTile(leading: Icon(Icons.flag_outlined), title: Text('Opening balance'))),
      ],
      child: IgnorePointer(
        child: FilledButton.icon(onPressed: () {}, icon: const Icon(Icons.add), label: const Text('New entry')),
      ),
    );
    if (wide) return Row(children: [Expanded(child: chips), const SizedBox(width: 12), add]);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      chips,
      const SizedBox(height: 10),
      Align(alignment: Alignment.centerRight, child: add),
    ]);
  }

  // ---------------------------------------------------------------------------
  // Balances
  // ---------------------------------------------------------------------------

  Widget _kpis(CashPeriod p, bool wide) {
    KpiCard account(MoneyAccount a, Color tint, Color bg) => KpiCard(
          label: a.label.toUpperCase(),
          icon: a.icon,
          tint: tint,
          tintBg: bg,
          value: dashRs(p.closing(a)),
          valueColor: p.closing(a) < -0.5 ? AppColors.red : null,
          sub: 'In ${dashRs(p.moneyIn[a] ?? 0)} · Out ${dashRs(p.moneyOut[a] ?? 0)}',
          spark: p.dailyBalance(a),
          onTap: () => setState(() => _account = _account == a ? null : a),
        );
    final change = p.totalClosing - p.totalOpening;
    final cards = [
      account(MoneyAccount.cash, AppColors.green, AppColors.greenBg),
      account(MoneyAccount.bank, AppColors.blue, AppColors.blueBg),
      account(MoneyAccount.wallet, AppColors.amber, AppColors.amberBg),
      KpiCard(
        label: 'TOTAL MONEY',
        icon: Icons.account_balance_wallet_outlined,
        tint: AppColors.navy,
        tintBg: AppColors.brandSoft,
        value: dashRs(p.totalClosing),
        sub: 'was ${dashRs(p.totalOpening)} at the start',
        trend: change.abs() < 0.5 ? null : ('${change > 0 ? '▲' : '▼'} ${dashRs(change.abs())} this period', change > 0),
        spark: p.dailyBalance(),
        onTap: () => setState(() => _account = null),
      ),
    ];
    return kpiGrid(cards, wide ? 4 : 2);
  }

  // ---------------------------------------------------------------------------
  // The ledger
  // ---------------------------------------------------------------------------

  Widget _ledger(CashPeriod p, bool wide) {
    final a = _account;
    final lines = p.lines.where((l) => a == null || l.account == a).toList();
    final opening = a == null ? p.totalOpening : (p.opening[a] ?? 0);
    var bal = opening;
    final balances = [for (final l in lines) bal += l.amount];
    final inn = lines.where((l) => l.amount > 0).fold<double>(0, (s, l) => s + l.amount);
    final out = lines.where((l) => l.amount < 0).fold<double>(0, (s, l) => s - l.amount);

    final filter = SegmentedButton<MoneyAccount?>(
      segments: [
        const ButtonSegment(value: null, label: Text('All')),
        for (final m in MoneyAccount.values) ButtonSegment(value: m, label: Text(m.short), icon: Icon(m.icon, size: 16)),
      ],
      selected: {a},
      showSelectedIcon: false,
      onSelectionChanged: (s) => setState(() => _account = s.first),
      style: SegmentedButton.styleFrom(
        selectedBackgroundColor: AppColors.navy,
        selectedForegroundColor: Colors.white,
        side: const BorderSide(color: AppColors.border),
        visualDensity: VisualDensity.compact,
      ),
    );

    return _panel(
      padding: const EdgeInsets.fromLTRB(0, 18, 0, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: wide
              ? Row(children: [
                  Expanded(child: _panelTitle(Icons.menu_book_outlined, 'Ledger', '${lines.length} entr${lines.length == 1 ? 'y' : 'ies'} · tap a manual entry to edit')),
                  filter,
                ])
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  _panelTitle(Icons.menu_book_outlined, 'Ledger', '${lines.length} entries'),
                  const SizedBox(height: 10),
                  filter,
                ]),
        ),
        const SizedBox(height: 12),
        if (wide) _ledgerHeader(),
        _balanceRow('Opening balance', p.start, opening, wide),
        for (var i = 0; i < lines.length; i++) ...[
          const Divider(height: 1),
          wide ? _lineWide(lines[i], balances[i], a == null) : _lineNarrow(lines[i], balances[i], a == null),
        ],
        if (lines.isEmpty)
          Padding(
            padding: const EdgeInsets.all(20),
            child: Text('Nothing came in or went out in this period.', textAlign: TextAlign.center, style: _small()),
          ),
        const Divider(height: 1),
        Container(
          color: AppColors.bg,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(children: [
            Expanded(
              child: Text('Closing balance · ${_dmy.format(p.end.subtract(const Duration(days: 1)))}',
                  style: _small(color: AppColors.text, w: FontWeight.w700, size: 13)),
            ),
            if (wide) ...[
              _amountCell(inn, AppColors.green, bold: true),
              _amountCell(out, AppColors.red, bold: true),
            ],
            SizedBox(
              width: wide ? 130 : null,
              child: Text(_rs(bal), textAlign: TextAlign.right, style: _small(color: bal < 0 ? AppColors.red : AppColors.text, w: FontWeight.w800, size: 14)),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _ledgerHeader() => Container(
        color: AppColors.bg,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
        child: Row(children: [
          SizedBox(width: 92, child: Text('DATE', style: _caps())),
          Expanded(child: Text('DETAILS', style: _caps())),
          SizedBox(width: 120, child: Text('IN', textAlign: TextAlign.right, style: _caps())),
          SizedBox(width: 120, child: Text('OUT', textAlign: TextAlign.right, style: _caps())),
          SizedBox(width: 130, child: Text('BALANCE', textAlign: TextAlign.right, style: _caps())),
        ]),
      );

  Widget _balanceRow(String label, DateTime date, double amount, bool wide) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
        child: Row(children: [
          if (wide) SizedBox(width: 92, child: Text(DateFormat('dd MMM').format(date), style: _small(size: 12.5))),
          Expanded(child: Text(label, style: _small(color: AppColors.text, w: FontWeight.w600, size: 13))),
          SizedBox(
            width: wide ? 130 : null,
            child: Text(_rs(amount), textAlign: TextAlign.right, style: _small(color: AppColors.text, w: FontWeight.w700, size: 13)),
          ),
        ]),
      );

  Widget _amountCell(double v, Color c, {bool bold = false}) => SizedBox(
        width: 120,
        child: Text(v.abs() < 0.5 ? '' : _money.format(v.round()),
            textAlign: TextAlign.right, style: _small(color: c, w: bold ? FontWeight.w700 : FontWeight.w600, size: 13)),
      );

  Widget _sourceIcon(CashLine l) {
    final (IconData icon, Color fg, Color bg) = switch (l.source) {
      CashSource.shopPayment => (Icons.storefront_outlined, AppColors.green, AppColors.greenBg),
      CashSource.officeRecovery => (Icons.storefront_outlined, AppColors.green, AppColors.greenBg),
      CashSource.expense => (Icons.receipt_outlined, AppColors.amberDark, AppColors.amberBg),
      CashSource.supplier => (Icons.local_shipping_outlined, AppColors.blue, AppColors.blueBg),
      CashSource.manual => (Icons.edit_note, AppColors.navy, AppColors.brandSoft),
    };
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Icon(icon, size: 16, color: fg),
    );
  }

  String _details(CashLine l, bool showAccount) {
    // The note often starts with the payment method; don't say "Cash · Cash".
    // Only a whole word: "Cash on delivery" stays as it is.
    final parts = l.note.split('·').map((s) => s.trim()).toList();
    if (parts.first.toLowerCase() == l.account.short.toLowerCase()) parts.removeAt(0);
    final note = parts.where((s) => s.isNotEmpty).join(' · ');
    return [if (showAccount) l.account.short, if (note.isNotEmpty) note].join(' · ');
  }

  Widget _lineWide(CashLine l, double balance, bool showAccount) => InkWell(
        onTap: l.entryId == null ? null : () => _entry(id: l.entryId),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
          child: Row(children: [
            SizedBox(width: 92, child: Text(DateFormat('dd MMM').format(l.date), style: _small(size: 12.5))),
            _sourceIcon(l),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(l.title, overflow: TextOverflow.ellipsis, style: _small(color: AppColors.text, w: FontWeight.w600, size: 13)),
                if (_details(l, showAccount).isNotEmpty)
                  Text(_details(l, showAccount), overflow: TextOverflow.ellipsis, style: _small(size: 11.5)),
              ]),
            ),
            _amountCell(l.amount > 0 ? l.amount : 0, AppColors.green),
            _amountCell(l.amount < 0 ? -l.amount : 0, AppColors.red),
            SizedBox(
              width: 130,
              child: Text(_rs(balance), textAlign: TextAlign.right, style: _small(color: balance < 0 ? AppColors.red : AppColors.text, size: 13)),
            ),
          ]),
        ),
      );

  Widget _lineNarrow(CashLine l, double balance, bool showAccount) => InkWell(
        onTap: l.entryId == null ? null : () => _entry(id: l.entryId),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(children: [
            _sourceIcon(l),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(l.title, overflow: TextOverflow.ellipsis, style: _small(color: AppColors.text, w: FontWeight.w600, size: 13)),
                Text([DateFormat('dd MMM').format(l.date), _details(l, showAccount)].where((s) => s.isNotEmpty).join(' · '),
                    overflow: TextOverflow.ellipsis, style: _small(size: 11.5)),
              ]),
            ),
            const SizedBox(width: 8),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('${l.amount > 0 ? '+' : '−'} ${_money.format(l.amount.abs().round())}',
                  style: _small(color: l.amount > 0 ? AppColors.green : AppColors.red, w: FontWeight.w700, size: 13)),
              Text(_rs(balance), style: _small(size: 11)),
            ]),
          ]),
        ),
      );

  // ---------------------------------------------------------------------------
  // Small pieces
  // ---------------------------------------------------------------------------

  Widget _panel({required Widget child, EdgeInsets padding = const EdgeInsets.fromLTRB(20, 18, 20, 18)}) =>
      Container(decoration: kpiCardDecoration(), clipBehavior: Clip.antiAlias, padding: padding, child: child);

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
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 12),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 40, color: AppColors.muted),
          const SizedBox(height: 12),
          Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text)),
          const SizedBox(height: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Text(text, textAlign: TextAlign.center, style: _small()),
          ),
          if (action != null) ...[const SizedBox(height: 14), action],
        ]),
      );
}

TextStyle _caps() => const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: AppColors.muted);
TextStyle _small({Color color = AppColors.muted, FontWeight w = FontWeight.w400, double size = 12.5}) =>
    TextStyle(fontSize: size, fontWeight: w, color: color);

// =============================================================================
// New / edit entry
// =============================================================================

class _EntrySheet extends StatefulWidget {
  final CashEntry? entry;
  final CashEntryType type;
  const _EntrySheet({this.entry, required this.type});

  @override
  State<_EntrySheet> createState() => _EntrySheetState();
}

class _EntrySheetState extends State<_EntrySheet> {
  final _form = GlobalKey<FormState>();
  late CashEntryType _type = widget.type;
  late MoneyAccount _account = widget.entry?.account ?? MoneyAccount.cash;
  late MoneyAccount _to = widget.entry?.toAccount ?? MoneyAccount.bank;
  late DateTime _date = widget.entry?.date ?? DateTime.now();
  late final _amount = TextEditingController(
      text: widget.entry == null ? '' : _money.format(widget.entry!.amount.round()).replaceAll(',', ''));
  late final _note = TextEditingController(text: widget.entry?.note ?? '');
  bool _saving = false;

  bool get _editing => widget.entry?.id != null;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final n = DateTime.now();
    final d = await showDatePicker(context: context, initialDate: _date.isAfter(n) ? n : _date, firstDate: DateTime(n.year - 5), lastDate: n);
    if (d != null) setState(() => _date = d);
  }

  /// Closed books: neither the date it had nor the new one ([day]) may be in them.
  Future<bool> _periodOpen(DateTime? day) async =>
      (widget.entry?.id == null || await ensureOpenPeriod(context, widget.entry!.date)) &&
      (day == null || (mounted && await ensureOpenPeriod(context, day)));

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (!await _periodOpen(_date)) return;
    setState(() => _saving = true);
    try {
      await saveCashEntry(CashEntry(
        id: widget.entry?.id,
        date: _date,
        type: _type,
        account: _account,
        toAccount: _type == CashEntryType.transfer ? _to : null,
        amount: double.parse(_amount.text.trim()),
        note: _note.text,
      ));
      if (mounted) Navigator.pop(context, _editing ? 'Entry updated' : 'Entry added');
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Couldn't save: $e")));
      }
    }
  }

  Future<void> _delete() async {
    if (!await _periodOpen(null)) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete this entry?'),
        content: Text('${widget.entry!.typeLabel} · ${_rs(widget.entry!.amount)} on ${_dmy.format(widget.entry!.date)}. This can\'t be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _saving = true);
    try {
      await deleteCashEntry(widget.entry!.id!);
      if (mounted) Navigator.pop(context, 'Entry deleted');
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Couldn't delete: $e")));
      }
    }
  }

  Widget _accountDrop(String label, MoneyAccount value, void Function(MoneyAccount) on) => DropdownButtonFormField<MoneyAccount>(
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        items: [
          for (final a in MoneyAccount.values)
            DropdownMenuItem(value: a, child: Row(children: [Icon(a.icon, size: 18, color: AppColors.muted), const SizedBox(width: 8), Text(a.label)])),
        ],
        onChanged: (v) => setState(() => on(v ?? value)),
      );

  @override
  Widget build(BuildContext context) {
    final help = switch (_type) {
      CashEntryType.opening => 'How much was in this account when you started using the book.',
      CashEntryType.moneyIn => 'Money that came in from outside sales: the owner\'s capital, a loan, other income.',
      CashEntryType.moneyOut => 'Money that went out other than expenses and supplier payments: the owner\'s drawings, a loan repaid.',
      CashEntryType.transfer => 'Money moved between your own accounts, e.g. cash deposited in the bank. The total doesn\'t change.',
    };
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Form(
              key: _form,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(_editing ? 'Edit entry' : 'New entry', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.text)),
                const SizedBox(height: 14),
                SegmentedButton<CashEntryType>(
                  segments: const [
                    ButtonSegment(value: CashEntryType.moneyIn, label: Text('In')),
                    ButtonSegment(value: CashEntryType.moneyOut, label: Text('Out')),
                    ButtonSegment(value: CashEntryType.transfer, label: Text('Transfer')),
                    ButtonSegment(value: CashEntryType.opening, label: Text('Opening')),
                  ],
                  selected: {_type},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => setState(() => _type = s.first),
                  style: SegmentedButton.styleFrom(
                    selectedBackgroundColor: AppColors.navy,
                    selectedForegroundColor: Colors.white,
                    side: const BorderSide(color: AppColors.border),
                  ),
                ),
                const SizedBox(height: 8),
                Text(help, style: _small(size: 12)),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _amount,
                  autofocus: !_editing,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  decoration: const InputDecoration(labelText: 'Amount (Rs)', prefixText: 'Rs  '),
                  validator: (v) {
                    final n = double.tryParse((v ?? '').trim());
                    if (n == null || n <= 0) return 'Enter the amount';
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                if (_type == CashEntryType.transfer)
                  Row(children: [
                    Expanded(child: _accountDrop('From', _account, (v) => _account = v)),
                    const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Icon(Icons.arrow_forward, color: AppColors.muted)),
                    Expanded(child: _accountDrop('To', _to, (v) => _to = v)),
                  ])
                else
                  _accountDrop('Account', _account, (v) => _account = v),
                if (_type == CashEntryType.transfer && _account == _to) ...[
                  const SizedBox(height: 6),
                  Text('Choose two different accounts.', style: _small(color: AppColors.red, size: 12)),
                ],
                const SizedBox(height: 14),
                InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.field),
                  onTap: _pickDate,
                  child: InputDecorator(
                    decoration: const InputDecoration(labelText: 'Date', prefixIcon: Icon(Icons.event_outlined, size: 20)),
                    child: Text(_dmy.format(_date)),
                  ),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _note,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: 'Note (optional)',
                    hintText: switch (_type) {
                      CashEntryType.moneyIn => 'e.g. Owner\'s capital',
                      CashEntryType.moneyOut => 'e.g. Owner\'s drawings',
                      CashEntryType.transfer => 'e.g. Deposit slip 4411',
                      CashEntryType.opening => 'e.g. Cash counted on 1 Nov',
                    },
                  ),
                ),
                const SizedBox(height: 20),
                Row(children: [
                  if (_editing)
                    TextButton.icon(
                      onPressed: _saving ? null : _delete,
                      style: TextButton.styleFrom(foregroundColor: AppColors.red),
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('Delete'),
                    ),
                  const Spacer(),
                  TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _saving || (_type == CashEntryType.transfer && _account == _to) ? null : _save,
                    child: _saving
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text(_editing ? 'Save' : 'Add entry'),
                  ),
                ]),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Printed book
// =============================================================================

Future<Uint8List> _bookPdf(CashPeriod p, MoneyAccount? a, String periodLabel) async {
  final doc = pw.Document();
  final lines = p.lines.where((l) => a == null || l.account == a).toList();
  final opening = a == null ? p.totalOpening : (p.opening[a] ?? 0);
  var bal = opening;
  String m(double v) => v.abs() < 0.5 ? '' : _money.format(v.round());
  pw.Widget cell(String t, {bool right = false, bool bold = false}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        child: pw.Text(t, textAlign: right ? pw.TextAlign.right : pw.TextAlign.left, style: pw.TextStyle(fontSize: 8.5, fontWeight: bold ? pw.FontWeight.bold : null)),
      );
  final rows = <pw.TableRow>[];
  for (final l in lines) {
    bal += l.amount;
    rows.add(pw.TableRow(children: [
      cell(DateFormat('dd-MM-yyyy').format(l.date)),
      cell([l.title, if (a == null) l.account.short, if (l.note.isNotEmpty) l.note].join(' · ')),
      cell(m(l.amount > 0 ? l.amount : 0), right: true),
      cell(m(l.amount < 0 ? -l.amount : 0), right: true),
      cell(_money.format(bal.round()), right: true),
    ]));
  }

  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4.copyWith(marginLeft: 32, marginRight: 32, marginTop: 32, marginBottom: 32),
    footer: (ctx) => pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
    ),
    build: (_) => [
      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
        pw.Text(Account.companyName, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
        pw.Text(a == null ? 'Cash & bank book' : '${a.label} book', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
      ]),
      pw.Text(periodLabel, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
      pw.SizedBox(height: 10),
      pw.Table(
        border: pw.TableBorder.all(color: PdfColors.grey500, width: 0.5),
        children: [
          pw.TableRow(decoration: const pw.BoxDecoration(color: PdfColors.grey300), children: [
            for (final h in const ['Account', 'Opening', 'In', 'Out', 'Closing']) cell(h, bold: true, right: h != 'Account'),
          ]),
          for (final acc in MoneyAccount.values)
            pw.TableRow(children: [
              cell(acc.label),
              cell(_money.format((p.opening[acc] ?? 0).round()), right: true),
              cell(_money.format((p.moneyIn[acc] ?? 0).round()), right: true),
              cell(_money.format((p.moneyOut[acc] ?? 0).round()), right: true),
              cell(_money.format(p.closing(acc).round()), right: true, bold: true),
            ]),
          pw.TableRow(decoration: const pw.BoxDecoration(color: PdfColors.grey200), children: [
            cell('Total', bold: true),
            cell(_money.format(p.totalOpening.round()), right: true, bold: true),
            cell(_money.format(p.totalIn.round()), right: true, bold: true),
            cell(_money.format(p.totalOut.round()), right: true, bold: true),
            cell(_money.format(p.totalClosing.round()), right: true, bold: true),
          ]),
        ],
      ),
      pw.SizedBox(height: 14),
      pw.Table(
        border: pw.TableBorder.all(color: PdfColors.grey500, width: 0.5),
        columnWidths: const {
          0: pw.FixedColumnWidth(60),
          1: pw.FlexColumnWidth(5),
          2: pw.FlexColumnWidth(1.4),
          3: pw.FlexColumnWidth(1.4),
          4: pw.FlexColumnWidth(1.6),
        },
        children: [
          pw.TableRow(repeat: true, decoration: const pw.BoxDecoration(color: PdfColors.grey300), children: [
            cell('Date', bold: true),
            cell('Details', bold: true),
            cell('In', bold: true, right: true),
            cell('Out', bold: true, right: true),
            cell('Balance', bold: true, right: true),
          ]),
          pw.TableRow(children: [cell(''), cell('Opening balance', bold: true), cell(''), cell(''), cell(_money.format(opening.round()), right: true, bold: true)]),
          ...rows,
          pw.TableRow(decoration: const pw.BoxDecoration(color: PdfColors.grey200), children: [
            cell(''),
            cell('Closing balance', bold: true),
            cell(''),
            cell(''),
            cell(_money.format(bal.round()), right: true, bold: true),
          ]),
        ],
      ),
    ],
  ));
  return doc.save();
}
