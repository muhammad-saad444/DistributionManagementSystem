// Audit log (Accounts → Audit log): who changed or deleted what, and when, with the reason for a
// locked record. At the top, the closed books: close them up to a date, or reopen them.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../Admin/dashboard_overview.dart' show dashRs;
import '../ui/app_theme.dart';
import '../ui/excel_export.dart';
import '../ui/kpi_card.dart';
import 'audit.dart';

final _dayHead = DateFormat('EEE, d MMM yyyy');
final _dayShort = DateFormat('d MMM yyyy');
final _time = DateFormat('h:mm a');

enum _Period { thisMonth, lastMonth, thisYear }

const _periodNames = {_Period.thisMonth: 'This month', _Period.lastMonth: 'Last month', _Period.thisYear: 'This year'};

class AuditLogScreen extends StatefulWidget {
  const AuditLogScreen({super.key});

  @override
  State<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends State<AuditLogScreen> {
  _Period _period = _Period.thisMonth;
  List<AuditEntry>? _list;
  Object? _error;
  AuditArea? _area; // null = all
  String? _person; // null = everyone
  DateTime? _closedUntil;
  bool _closedLoaded = false;
  bool _busy = false;

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
      _Period.thisYear => (DateTime(n.year), DateTime(n.year + 1)),
    };
  }

  Future<void> _load() async {
    setState(() {
      _error = null;
      _list = null;
    });
    try {
      final (from, to) = _range;
      final results = await Future.wait([loadAudit(from, to), booksClosedUntil(fresh: true)]);
      if (!mounted) return;
      setState(() {
        _list = results[0] as List<AuditEntry>;
        _closedUntil = results[1] as DateTime?;
        _closedLoaded = true;
      });
    } catch (e) {
      debugPrint('Audit log: $e');
      if (mounted) setState(() => _error = e);
    }
  }

  List<AuditEntry> get _shown => [
        for (final e in _list ?? const <AuditEntry>[])
          if ((_area == null || e.area == _area) && (_person == null || e.byName == _person)) e,
      ];

  // ---------------------------------------------------------------------------
  // Closed books
  // ---------------------------------------------------------------------------

  Future<void> _closeBooks() async {
    final n = DateTime.now();
    final suggested = DateTime(n.year, n.month, 0); // last day of last month
    final day = await showDatePicker(
      context: context,
      initialDate: _closedUntil != null && _closedUntil!.isAfter(suggested) ? _closedUntil! : suggested,
      firstDate: DateTime(2020),
      lastDate: DateTime(n.year, n.month, n.day),
      helpText: 'Close the books up to',
    );
    if (day == null || !mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        icon: const Icon(Icons.lock_outline, color: AppColors.navy),
        title: Text('Close the books up to ${_dayShort.format(day)}?'),
        content: const SizedBox(
          width: 440,
          child: Text(
            'Invoices, payments, expenses and cash entries dated on or before this day can no longer be added, '
            'changed or deleted, by anyone. Do this once the month\'s figures are checked. You can reopen the books '
            'here later; that is kept in the log too.',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Close books')),
        ],
      ),
    );
    if (ok == true) await _setClosed(day);
  }

  Future<void> _reopen() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Reopen the books?'),
        content: const Text('Every past record can be changed again until you close the books once more. '
            'Reopening is kept in the audit log with your name.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Reopen'),
          ),
        ],
      ),
    );
    if (ok == true) await _setClosed(null);
  }

  Future<void> _setClosed(DateTime? day) async {
    setState(() => _busy = true);
    try {
      await setBooksClosedUntil(day);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(day == null ? 'Books reopened' : 'Books closed up to ${_dayShort.format(day)}'),
      ));
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Couldn't save: $e")));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------------------------------------------------------------------------

  void _export(List<AuditEntry> list) => exportToExcel(
        context,
        fileName: exportFileName('audit-log'),
        title: 'Audit log',
        subtitle: _periodNames[_period]!,
        sheets: [
          ExportSheet(
            name: 'Audit log',
            headers: ['When', 'Who', 'Area', 'Action', 'Record', 'Amount (Rs)', 'What changed', 'Reason'],
            rows: [
              for (final e in list)
                [
                  e.at,
                  e.byName,
                  e.area.label,
                  AuditAction.label(e.action),
                  e.title,
                  e.amount,
                  e.changes.map((c) => c.toString()).join('\n'),
                  e.reason,
                ],
            ],
          ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final list = _list == null ? null : _shown;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Audit log'),
        actions: [
          ExcelButton(onPressed: list == null || list.isEmpty ? null : () => _export(list)),
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
                  _booksPanel(wide),
                  const SizedBox(height: 16),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final p in _Period.values)
                      ChoiceChip(
                        label: Text(_periodNames[p]!),
                        selected: _period == p,
                        showCheckmark: false,
                        onSelected: (_) {
                          setState(() => _period = p);
                          _load();
                        },
                      ),
                  ]),
                  const SizedBox(height: 16),
                  if (_list == null)
                    _error != null
                        ? _panel(child: _empty(Icons.cloud_off, "Couldn't load the log", 'Check the connection and try again.'))
                        : const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator()))
                  else ...[
                    _kpis(_list!, wide),
                    const SizedBox(height: 16),
                    _logPanel(list!),
                  ],
                ]),
              ),
            ),
          ],
        );
      }),
    );
  }

  Widget _booksPanel(bool wide) {
    final closed = _closedUntil;
    final text = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(
        !_closedLoaded
            ? 'Closed books'
            : closed == null
                ? 'The books are open'
                : 'Books closed up to ${_dayShort.format(closed)}',
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.text),
      ),
      const SizedBox(height: 3),
      Text(
        closed == null
            ? 'Close a month once its figures are checked: nothing dated in it can be changed after that.'
            : 'Nothing dated on or before this day can be added, changed or deleted. Paid and delivered invoices '
                'need a reason to change, which shows below.',
        style: const TextStyle(fontSize: 12.5, color: AppColors.muted),
      ),
    ]);
    final buttons = Wrap(spacing: 8, runSpacing: 8, children: [
      if (closed != null)
        OutlinedButton.icon(
          onPressed: _busy || !_closedLoaded ? null : _reopen,
          icon: const Icon(Icons.lock_open_outlined, size: 18),
          label: const Text('Reopen'),
        ),
      FilledButton.icon(
        onPressed: _busy || !_closedLoaded ? null : _closeBooks,
        icon: _busy
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.lock_outline, size: 18),
        label: Text(closed == null ? 'Close books…' : 'Change date…'),
      ),
    ]);
    final icon = Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: closed == null ? AppColors.amberBg : AppColors.brandSoft, borderRadius: BorderRadius.circular(10)),
      child: Icon(closed == null ? Icons.lock_open_outlined : Icons.lock_outline,
          color: closed == null ? AppColors.amberDark : AppColors.navy, size: 22),
    );
    return _panel(
      padding: const EdgeInsets.all(18),
      child: wide
          ? Row(children: [icon, const SizedBox(width: 14), Expanded(child: text), const SizedBox(width: 14), buttons])
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [icon, const SizedBox(width: 12), Expanded(child: text)]),
              const SizedBox(height: 12),
              buttons,
            ]),
    );
  }

  Widget _kpis(List<AuditEntry> all, bool wide) {
    final edits = all.where((e) => e.action == AuditAction.edit).length;
    final deletes = all.where((e) => e.action == AuditAction.delete).toList();
    final deletedValue = deletes.fold<double>(0, (s, e) => s + (e.amount ?? 0));
    final withReason = all.where((e) => e.reason.isNotEmpty && e.area != AuditArea.returns).length;
    final people = <String, int>{};
    for (final e in all) {
      people[e.byName.isEmpty ? 'Unknown' : e.byName] = (people[e.byName.isEmpty ? 'Unknown' : e.byName] ?? 0) + 1;
    }
    final top = people.entries.isEmpty ? null : (people.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first;
    return kpiGrid([
      KpiCard(
        label: 'CHANGES',
        icon: Icons.edit_note,
        tint: AppColors.amber,
        tintBg: AppColors.amberBg,
        value: '$edits',
        sub: '${all.length} entr${all.length == 1 ? 'y' : 'ies'} in all',
      ),
      KpiCard(
        label: 'DELETED',
        icon: Icons.delete_outline,
        tint: deletes.isEmpty ? AppColors.navy : AppColors.red,
        tintBg: deletes.isEmpty ? AppColors.brandSoft : AppColors.redBg,
        value: '${deletes.length}',
        valueColor: deletes.isEmpty ? null : AppColors.red,
        sub: deletes.isEmpty ? 'nothing deleted' : '${dashRs(deletedValue)} of records',
      ),
      KpiCard(
        label: 'LOCKED, CHANGED',
        icon: Icons.lock_outline,
        tint: AppColors.blue,
        tintBg: AppColors.blueBg,
        value: '$withReason',
        sub: 'paid or delivered, with a reason',
      ),
      KpiCard(
        label: 'PEOPLE',
        icon: Icons.people_outline,
        tint: AppColors.green,
        tintBg: AppColors.greenBg,
        value: '${people.length}',
        sub: top == null ? 'nobody changed anything' : 'most: ${top.key} (${top.value})',
      ),
    ], wide ? 4 : 2);
  }

  Widget _logPanel(List<AuditEntry> list) {
    final areas = {for (final e in _list!) e.area}.toList()..sort((a, b) => a.index.compareTo(b.index));
    final people = {for (final e in _list!) e.byName}.where((s) => s.isNotEmpty).toList()..sort();
    final rows = <Widget>[];
    DateTime? day;
    for (final e in list) {
      final d = DateTime(e.at.year, e.at.month, e.at.day);
      if (day != d) {
        day = d;
        rows.add(Container(
          color: AppColors.bg,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 7),
          child: Text(_dayHead.format(d).toUpperCase(),
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.muted, letterSpacing: .4)),
        ));
      } else {
        rows.add(const Divider(height: 1, indent: 20, endIndent: 20));
      }
      rows.add(_row(e));
    }
    return _panel(
      padding: const EdgeInsets.fromLTRB(0, 18, 0, 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(children: [
            Expanded(child: _title(Icons.fact_check_outlined, 'What changed', 'newest first')),
            if (people.length > 1)
              DropdownButton<String?>(
                value: _person,
                underline: const SizedBox(),
                style: const TextStyle(fontSize: 13, color: AppColors.text),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Everyone')),
                  for (final p in people) DropdownMenuItem(value: p, child: Text(p)),
                ],
                onChanged: (v) => setState(() => _person = v),
              ),
          ]),
        ),
        if (areas.length > 1) ...[
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Wrap(spacing: 6, runSpacing: 6, children: [
              ChoiceChip(
                label: const Text('All'),
                selected: _area == null,
                showCheckmark: false,
                visualDensity: VisualDensity.compact,
                onSelected: (_) => setState(() => _area = null),
              ),
              for (final a in areas)
                ChoiceChip(
                  avatar: Icon(a.icon, size: 15),
                  label: Text(a.label),
                  selected: _area == a,
                  showCheckmark: false,
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) => setState(() => _area = _area == a ? null : a),
                ),
            ]),
          ),
        ],
        const SizedBox(height: 10),
        if (list.isEmpty)
          _empty(Icons.fact_check_outlined, 'Nothing changed in this period',
              'Edits and deletions of invoices, payments, expenses, stock and prices show here.')
        else
          ...rows,
      ]),
    );
  }

  Widget _row(AuditEntry e) {
    final (Color fg, Color bg) = switch (e.action) {
      AuditAction.delete => (AppColors.red, AppColors.redBg),
      AuditAction.edit => (AppColors.amberDark, AppColors.amberBg),
      AuditAction.create => (AppColors.blue, AppColors.blueBg),
      _ => (AppColors.navy, AppColors.brandSoft),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
          child: Icon(e.area.icon, size: 16, color: fg),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text(e.title, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.text)),
              _pill(AuditAction.label(e.action), fg, bg),
            ]),
            const SizedBox(height: 3),
            Text('${e.byName.isEmpty ? 'Unknown' : e.byName} · ${_time.format(e.at)} · ${e.area.label}',
                style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
            if (e.changes.isNotEmpty) ...[
              const SizedBox(height: 5),
              for (final c in e.changes)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: _change(c),
                ),
            ],
            if (e.reason.isNotEmpty) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: AppColors.amberBg, borderRadius: BorderRadius.circular(6)),
                child: Text.rich(TextSpan(children: [
                  const TextSpan(text: 'Reason: ', style: TextStyle(fontWeight: FontWeight.w700)),
                  TextSpan(text: e.reason),
                ]), style: const TextStyle(fontSize: 12, color: AppColors.amberDark)),
              ),
            ],
          ]),
        ),
        if (e.amount != null) ...[
          const SizedBox(width: 10),
          Text('Rs ${NumberFormat('#,##0').format(e.amount!.round())}',
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: e.action == AuditAction.delete ? AppColors.red : AppColors.text,
                decoration: e.action == AuditAction.delete ? TextDecoration.lineThrough : null,
              )),
        ],
      ]),
    );
  }

  /// "Soap qty: 10 → 12", with the old value struck through.
  Widget _change(AuditChange c) {
    const base = TextStyle(fontSize: 12, color: AppColors.text);
    return Text.rich(
      TextSpan(style: base, children: [
        TextSpan(text: '${c.field}: ', style: const TextStyle(color: AppColors.muted)),
        if (c.from.isNotEmpty)
          TextSpan(
            text: c.from,
            style: c.to.isEmpty ? null : const TextStyle(color: AppColors.muted, decoration: TextDecoration.lineThrough),
          ),
        if (c.from.isNotEmpty && c.to.isNotEmpty) const TextSpan(text: '  →  ', style: TextStyle(color: AppColors.muted)),
        if (c.to.isNotEmpty) TextSpan(text: c.to, style: const TextStyle(fontWeight: FontWeight.w600)),
      ]),
    );
  }

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
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 38, color: AppColors.muted),
          const SizedBox(height: 10),
          Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.text)),
          const SizedBox(height: 4),
          Text(text, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
        ]),
      );
}
