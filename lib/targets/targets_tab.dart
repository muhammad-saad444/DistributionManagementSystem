// Booker Credits → Targets: each booker's sales and recovery target for the month, what they have
// achieved, and whether they are keeping up with the month. The office sets targets here.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../Admin/dashboard_overview.dart' show dashRs;
import '../ui/app_theme.dart';
import '../ui/excel_export.dart';
import '../ui/kpi_card.dart';
import 'targets_data.dart';

final _money = NumberFormat('#,##0');

class TargetsTab extends StatefulWidget {
  const TargetsTab({super.key});

  @override
  State<TargetsTab> createState() => _TargetsTabState();
}

class _TargetsTabState extends State<TargetsTab> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  List<BookerMonth>? _rows;
  Object? _error;
  bool _loading = false;

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
      final rows = await loadTargetBoard(_month);
      if (mounted) setState(() => _rows = rows);
    } catch (e) {
      debugPrint('Targets: $e');
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _shift(int by) {
    setState(() {
      _month = DateTime(_month.year, _month.month + by);
      _rows = null;
    });
    _load();
  }

  bool get _isFuture => _month.isAfter(DateTime(DateTime.now().year, DateTime.now().month));

  Future<void> _setTarget(BookerMonth b) async {
    final saved = await showDialog<bool>(context: context, builder: (_) => _TargetDialog(month: _month, booker: b));
    if (saved == true) _load();
  }

  Future<void> _copyLast() async {
    final rows = _rows;
    if (rows == null) return;
    try {
      final n = await copyLastMonthTargets(_month, rows);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(n == 0
            ? 'Nothing to copy: last month had no targets for bookers without one now.'
            : 'Copied last month\'s targets for $n booker${n == 1 ? '' : 's'}'),
      ));
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Couldn't copy: $e")));
    }
  }

  void _export(List<BookerMonth> rows, double share) {
    exportToExcel(
      context,
      fileName: exportFileName('targets-${monthKey(_month)}'),
      title: 'Targets',
      subtitle: DateFormat('MMMM yyyy').format(_month),
      sheets: [
        ExportSheet(
          name: 'Bookers',
          headers: ['Booker', 'Sales target', 'Sales achieved', 'Sales %', 'Recovery target', 'Recovered', 'Recovery %', 'Invoices', 'Sales pace'],
          rows: [
            for (final b in rows)
              [
                b.name,
                b.target.sales > 0 ? b.target.sales : null,
                b.sales,
                b.target.sales > 0 ? b.salesProgress(share).pct : null,
                b.target.recovery > 0 ? b.target.recovery : null,
                b.recovery,
                b.target.recovery > 0 ? b.recoveryProgress(share).pct : null,
                b.invoices,
                _paceLabel(b.salesProgress(share).pace),
              ],
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    final today = DateTime.now();
    final share = monthShare(_month, today);
    final left = daysLeft(_month, today);
    return LayoutBuilder(builder: (context, box) {
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
                  Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    _monthSwitcher(),
                    OutlinedButton.icon(
                      onPressed: rows == null || _loading ? null : _copyLast,
                      icon: const Icon(Icons.content_copy_outlined, size: 18),
                      label: const Text('Copy last month'),
                    ),
                    ExcelButton(onPressed: rows == null || rows.isEmpty ? null : () => _export(rows, share)),
                  ]),
                  const SizedBox(height: 16),
                  if (rows == null)
                    _error != null
                        ? _panel(child: _empty(Icons.cloud_off, "Couldn't load targets", 'Check the connection and pull down to try again.'))
                        : const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator()))
                  else ...[
                    _kpis(rows, share, left, wide),
                    const SizedBox(height: 16),
                    _table(rows, share, wide),
                    const SizedBox(height: 10),
                    Text(
                      'Sales: the month\'s invoices (after discount and returns). Recovery: payments from shops in the khata and office recoveries. '
                      'Pace compares the % done with how much of the month has gone; within 5 points either way is on track.',
                      style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
                    ),
                  ],
                ]),
              ),
            ),
          ],
        ),
      );
    });
  }

  Widget _monthSwitcher() {
    final now = DateTime.now();
    final current = _month.year == now.year && _month.month == now.month;
    return Container(
      decoration: kpiCardDecoration(),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(tooltip: 'Previous month', icon: const Icon(Icons.chevron_left), onPressed: () => _shift(-1)),
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 140),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(DateFormat('MMMM yyyy').format(_month),
                style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: AppColors.text)),
            Text(current ? 'this month' : (_isFuture ? 'next month' : 'past month'),
                style: const TextStyle(fontSize: 11, color: AppColors.muted)),
          ]),
        ),
        // One month ahead is allowed, so next month's targets can be set before it starts.
        IconButton(tooltip: 'Next month', icon: const Icon(Icons.chevron_right), onPressed: _isFuture ? null : () => _shift(1)),
      ]),
    );
  }

  Widget _kpis(List<BookerMonth> rows, double share, int left, bool wide) {
    double sum(double Function(BookerMonth b) f) => rows.fold(0, (s, b) => s + f(b));
    final salesT = sum((b) => b.target.sales);
    final salesA = sum((b) => b.sales);
    final recT = sum((b) => b.target.recovery);
    final recA = sum((b) => b.recovery);
    final withTarget = rows.where((b) => b.target.sales > 0).toList();
    final behind = withTarget.where((b) => b.salesProgress(share).pace == Pace.behind).length;
    final good = withTarget.where((b) => {Pace.ahead, Pace.onTrack, Pace.done}.contains(b.salesProgress(share).pace)).length;
    final sp = TargetProgress(salesT, salesA, share);
    final rp = TargetProgress(recT, recA, share);
    return kpiGrid([
      KpiCard(
        label: 'SALES VS TARGET',
        icon: Icons.flag_outlined,
        tint: AppColors.blue,
        tintBg: AppColors.blueBg,
        value: salesT > 0 ? '${sp.pct.toStringAsFixed(0)}%' : dashRs(salesA),
        sub: salesT > 0 ? '${dashRs(salesA)} of ${dashRs(salesT)}' : 'sold · no targets set yet',
        progress: salesT > 0 ? sp.pct / 100 : null,
      ),
      KpiCard(
        label: 'RECOVERY VS TARGET',
        icon: Icons.payments_outlined,
        tint: AppColors.green,
        tintBg: AppColors.greenBg,
        value: recT > 0 ? '${rp.pct.toStringAsFixed(0)}%' : dashRs(recA),
        sub: recT > 0 ? '${dashRs(recA)} of ${dashRs(recT)}' : 'recovered · no targets set yet',
        progress: recT > 0 ? rp.pct / 100 : null,
      ),
      KpiCard(
        label: 'BOOKERS',
        icon: Icons.people_outline,
        tint: behind > 0 ? AppColors.red : AppColors.navy,
        tintBg: behind > 0 ? AppColors.redBg : AppColors.brandSoft,
        value: withTarget.isEmpty ? '${rows.length}' : '$good of ${withTarget.length}',
        valueColor: behind > 0 ? AppColors.red : null,
        sub: withTarget.isEmpty ? 'no sales targets set' : (behind == 0 ? 'all keeping up' : '$behind behind on sales'),
      ),
      KpiCard(
        label: 'DAYS LEFT',
        icon: Icons.calendar_month_outlined,
        tint: AppColors.amber,
        tintBg: AppColors.amberBg,
        value: '$left',
        sub: salesT > 0 && left > 0 && sp.left > 0 ? '${dashRs(sp.perDayNeeded(left))} a day still needed' : '${(share * 100).toStringAsFixed(0)}% of the month gone',
        progress: share,
      ),
    ], wide ? 4 : 2);
  }

  Widget _table(List<BookerMonth> rows, double share, bool wide) => _panel(
        padding: const EdgeInsets.fromLTRB(0, 18, 0, 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: AppColors.brandSoft, borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.flag_outlined, size: 15, color: AppColors.navy),
              ),
              const SizedBox(width: 10),
              const Text('Bookers', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: AppColors.text)),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('tap Set to give a booker their targets', style: TextStyle(fontSize: 11.5, color: AppColors.muted), overflow: TextOverflow.ellipsis),
              ),
            ]),
          ),
          const SizedBox(height: 10),
          if (rows.isEmpty) _empty(Icons.people_outline, 'No bookers yet', 'Bookers appear here once they have logged in.'),
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            _row(rows[i], share, wide),
          ],
        ]),
      );

  Widget _row(BookerMonth b, double share, bool wide) {
    final sp = b.salesProgress(share);
    final rp = b.recoveryProgress(share);
    final set = OutlinedButton(
      onPressed: () => _setTarget(b),
      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), visualDensity: VisualDensity.compact),
      child: Text(b.target.isSet ? 'Change' : 'Set'),
    );
    final who = Row(children: [
      CircleAvatar(
        radius: 16,
        backgroundColor: AppColors.brandSoft,
        child: Text(b.name.isEmpty ? 'B' : b.name[0].toUpperCase(),
            style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.navy, fontSize: 13)),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(b.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.text)),
          Text('${b.invoices} invoice${b.invoices == 1 ? '' : 's'}', style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
        ]),
      ),
    ]);
    if (wide) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(children: [
          Expanded(flex: 3, child: who),
          const SizedBox(width: 12),
          Expanded(flex: 4, child: _meter('Sales', sp)),
          const SizedBox(width: 20),
          Expanded(flex: 4, child: _meter('Recovery', rp)),
          const SizedBox(width: 12),
          SizedBox(width: 92, child: _paceChip(sp.pace)),
          SizedBox(width: 84, child: Align(alignment: Alignment.centerRight, child: set)),
        ]),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [Expanded(child: who), _paceChip(sp.pace), const SizedBox(width: 8), set]),
        const SizedBox(height: 10),
        _meter('Sales', sp),
        const SizedBox(height: 8),
        _meter('Recovery', rp),
      ]),
    );
  }

  /// "Sales  Rs 9.2 Lac of Rs 15 Lac  61%" with a bar; a marker shows where it should be by now.
  Widget _meter(String label, TargetProgress p) {
    final has = p.target > 0;
    final color = switch (p.pace) {
      Pace.done || Pace.ahead => AppColors.green,
      Pace.onTrack => AppColors.blue,
      Pace.behind => AppColors.red,
      Pace.none => AppColors.muted,
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Text(label, style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            has ? '${dashRs(p.achieved)} of ${dashRs(p.target)}' : '${dashRs(p.achieved)} · no target',
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.text),
          ),
        ),
        if (has) Text('${p.pct.toStringAsFixed(0)}%', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: color)),
      ]),
      const SizedBox(height: 5),
      LayoutBuilder(builder: (context, box) {
        return Stack(clipBehavior: Clip.none, children: [
          Container(height: 6, decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(3))),
          if (has)
            Container(
              height: 6,
              width: box.maxWidth * (p.pct / 100).clamp(0, 1),
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
            ),
          if (has && p.monthShare > 0 && p.monthShare < 1)
            Positioned(
              left: (box.maxWidth * p.monthShare - 1).clamp(0, box.maxWidth - 2),
              top: -3,
              child: Container(width: 2, height: 12, color: AppColors.text.withValues(alpha: 0.45)),
            ),
        ]);
      }),
    ]);
  }

  Widget _paceChip(Pace pace) {
    final (String text, Color fg, Color bg) = switch (pace) {
      Pace.done => ('Done', AppColors.green, AppColors.greenBg),
      Pace.ahead => ('Ahead', AppColors.green, AppColors.greenBg),
      Pace.onTrack => ('On track', AppColors.blue, AppColors.blueBg),
      Pace.behind => ('Behind', AppColors.red, AppColors.redBg),
      Pace.none => ('No target', AppColors.muted, AppColors.bg),
    };
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
        child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg)),
      ),
    );
  }

  Widget _panel({required Widget child, EdgeInsets padding = const EdgeInsets.fromLTRB(20, 18, 20, 12)}) =>
      Container(decoration: kpiCardDecoration(), clipBehavior: Clip.antiAlias, padding: padding, child: child);

  Widget _empty(IconData icon, String title, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 36, color: AppColors.muted),
          const SizedBox(height: 10),
          Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.text)),
          const SizedBox(height: 4),
          Text(text, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
        ]),
      );
}

String _paceLabel(Pace p) => switch (p) {
      Pace.done => 'Done',
      Pace.ahead => 'Ahead',
      Pace.onTrack => 'On track',
      Pace.behind => 'Behind',
      Pace.none => 'No target',
    };

class _TargetDialog extends StatefulWidget {
  final DateTime month;
  final BookerMonth booker;
  const _TargetDialog({required this.month, required this.booker});

  @override
  State<_TargetDialog> createState() => _TargetDialogState();
}

class _TargetDialogState extends State<_TargetDialog> {
  late final _sales = TextEditingController(text: widget.booker.target.sales > 0 ? widget.booker.target.sales.round().toString() : '');
  late final _recovery =
      TextEditingController(text: widget.booker.target.recovery > 0 ? widget.booker.target.recovery.round().toString() : '');
  bool _saving = false;

  @override
  void dispose() {
    _sales.dispose();
    _recovery.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await saveTarget(
        widget.month,
        widget.booker.uid,
        sales: double.tryParse(_sales.text.trim()) ?? 0,
        recovery: double.tryParse(_recovery.text.trim()) ?? 0,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Couldn't save: $e")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget field(TextEditingController c, String label, String hint) => TextField(
          controller: c,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(labelText: label, prefixText: 'Rs  ', hintText: hint),
          onChanged: (_) => setState(() {}),
        );
    final s = double.tryParse(_sales.text.trim()) ?? 0;
    final days = DateTime(widget.month.year, widget.month.month + 1, 0).day;
    return AlertDialog(
      title: Text('${widget.booker.name} · ${DateFormat('MMMM yyyy').format(widget.month)}'),
      content: SizedBox(
        width: 380,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          field(_sales, 'Sales target', 'e.g. 1500000'),
          if (s > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('About Rs ${_money.format(s / days)} a day', style: const TextStyle(fontSize: 12, color: AppColors.muted)),
            ),
          const SizedBox(height: 14),
          field(_recovery, 'Recovery target', 'e.g. 1200000'),
          const SizedBox(height: 10),
          const Text('Leave a box empty for no target. Achieved so far is worked out from invoices and payments.',
              style: TextStyle(fontSize: 12, color: AppColors.muted)),
        ]),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Save'),
        ),
      ],
    );
  }
}
