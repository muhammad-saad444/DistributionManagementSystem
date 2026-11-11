// Admin: cash the bookers have collected from shops and not yet handed over. Who holds how much
// and for how long, receive cash from a booker (into cash in hand or the bank), and the history.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../Admin/dashboard_overview.dart' show dashRs;
import '../ui/app_theme.dart';
import '../ui/kpi_card.dart';
import 'cashbook_data.dart' show MoneyAccount, MoneyAccountX;
import 'handover_data.dart';

final _money = NumberFormat('#,##0');
String _rs(num v) => '${v < 0 ? '−' : ''}Rs ${_money.format(v.abs().round())}';
final _dm = DateFormat('d MMM');

enum _Period { today, week, month }

class HandoverScreen extends StatefulWidget {
  const HandoverScreen({super.key});

  @override
  State<HandoverScreen> createState() => _HandoverScreenState();
}

class _HandoverScreenState extends State<HandoverScreen> {
  List<Map<String, dynamic>>? _payments;
  List<Handover> _handovers = const [];
  Map<String, String> _names = const {};
  Object? _error;
  bool _loading = false;
  _Period _period = _Period.today;

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
      final (p, h, n) = await loadHandoverData();
      if (mounted) {
        setState(() {
          _payments = p;
          _handovers = h;
          _names = n;
        });
      }
    } catch (e) {
      debugPrint('Handover: $e');
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  (DateTime, DateTime) get _range {
    final n = DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    return switch (_period) {
      _Period.today => (today, today.add(const Duration(days: 1))),
      _Period.week => (today.subtract(Duration(days: today.weekday - 1)), today.add(const Duration(days: 1))),
      _Period.month => (DateTime(n.year, n.month), DateTime(n.year, n.month + 1)),
    };
  }

  String get _periodWord => switch (_period) {
        _Period.today => 'today',
        _Period.week => 'this week',
        _Period.month => 'this month',
      };

  Future<void> _receive({BookerCash? booker, Handover? edit}) async {
    final rows = bookerCash(_payments ?? const [], _handovers, _names);
    final done = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ReceiveSheet(bookers: rows, booker: booker, edit: edit),
    );
    if (done != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final payments = _payments;
    final (start, end) = _range;
    final rows = payments == null ? null : bookerCash(payments, _handovers, _names, start: start, end: end);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cash handover'),
        actions: [
          IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh), onPressed: _loading ? null : _load),
          const SizedBox(width: 6),
        ],
        bottom: _loading && payments != null
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
                    if (rows == null)
                      _error != null
                          ? _panel(
                              child: _message(Icons.cloud_off, "Couldn't load cash handovers", 'Check the connection and try again.',
                                  action: TextButton(onPressed: _load, child: const Text('Try again'))))
                          : const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator()))
                    else ...[
                      _kpis(rows, wide),
                      const SizedBox(height: 16),
                      if (wide)
                        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Expanded(flex: 7, child: _bookers(rows)),
                          const SizedBox(width: 16),
                          Expanded(flex: 5, child: _history()),
                        ])
                      else ...[
                        _bookers(rows),
                        const SizedBox(height: 16),
                        _history(),
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
    const labels = {_Period.today: 'Today', _Period.week: 'This week', _Period.month: 'This month'};
    final chips = Wrap(spacing: 8, runSpacing: 8, children: [
      for (final p in _Period.values)
        ChoiceChip(label: Text(labels[p]!), selected: _period == p, showCheckmark: false, onSelected: (_) => setState(() => _period = p)),
    ]);
    final add = FilledButton.icon(
      onPressed: _payments == null ? null : () => _receive(),
      icon: const Icon(Icons.handshake_outlined),
      label: const Text('Receive cash'),
    );
    if (wide) return Row(children: [Expanded(child: chips), add]);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [chips, const SizedBox(height: 10), add]);
  }

  // ---------------------------------------------------------------------------
  // Figures
  // ---------------------------------------------------------------------------

  Widget _kpis(List<BookerCash> rows, bool wide) {
    final holding = rows.fold<double>(0, (s, r) => s + (r.holding > 0 ? r.holding : 0));
    final holders = rows.where((r) => r.holding > 0.5).length;
    final collected = rows.fold<double>(0, (s, r) => s + r.collectedInPeriod);
    final handed = rows.fold<double>(0, (s, r) => s + r.handedInPeriod);
    BookerCash? oldest;
    for (final r in rows) {
      if (r.holding > 0.5 && r.oldestUnhanded != null && (oldest == null || r.oldestUnhanded!.isBefore(oldest.oldestUnhanded!))) {
        oldest = r;
      }
    }
    final days = oldest == null ? 0 : _daysSince(oldest.oldestUnhanded!);
    final cards = [
      KpiCard(
        label: 'CASH WITH BOOKERS',
        icon: Icons.account_balance_wallet_outlined,
        tint: holding > 0.5 ? AppColors.amber : AppColors.green,
        tintBg: holding > 0.5 ? AppColors.amberBg : AppColors.greenBg,
        value: dashRs(holding),
        sub: holders == 0 ? 'everything handed over' : '$holders booker${holders == 1 ? '' : 's'} holding cash',
      ),
      KpiCard(
        label: 'COLLECTED ${_periodWord.toUpperCase()}',
        icon: Icons.storefront_outlined,
        tint: AppColors.blue,
        tintBg: AppColors.blueBg,
        value: dashRs(collected),
        sub: 'cash from shops',
      ),
      KpiCard(
        label: 'HANDED OVER ${_periodWord.toUpperCase()}',
        icon: Icons.handshake_outlined,
        tint: AppColors.green,
        tintBg: AppColors.greenBg,
        value: dashRs(handed),
        sub: collected < 0.5 ? 'received by the office' : '${(handed / collected * 100).clamp(0, 999).toStringAsFixed(0)}% of what came in',
        progress: collected < 0.5 ? null : handed / collected,
      ),
      KpiCard(
        label: 'OLDEST CASH OUT',
        icon: Icons.schedule_outlined,
        tint: days > 2 ? AppColors.red : AppColors.navy,
        tintBg: days > 2 ? AppColors.redBg : AppColors.brandSoft,
        value: oldest == null ? '—' : '$days day${days == 1 ? '' : 's'}',
        valueColor: days > 2 ? AppColors.red : null,
        sub: oldest == null ? 'nothing waiting' : 'with ${oldest.name} since ${_dm.format(oldest.oldestUnhanded!)}',
      ),
    ];
    return kpiGrid(cards, wide ? 4 : 2);
  }

  int _daysSince(DateTime d) {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day).difference(DateTime(d.year, d.month, d.day)).inDays;
  }

  // ---------------------------------------------------------------------------
  // Bookers
  // ---------------------------------------------------------------------------

  Widget _bookers(List<BookerCash> rows) => _panel(
        padding: const EdgeInsets.fromLTRB(0, 18, 0, 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _panelTitle(Icons.people_outline, 'Bookers', 'cash in hand now · collected and handed over $_periodWord'),
          ),
          const SizedBox(height: 10),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text('No booker has collected cash yet. Cash payments bookers record in the khata show up here.',
                  textAlign: TextAlign.center, style: _small()),
            ),
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 66),
            _bookerRow(rows[i]),
          ],
        ]),
      );

  Widget _bookerRow(BookerCash r) {
    final holds = r.holding > 0.5;
    final days = r.oldestUnhanded == null ? 0 : _daysSince(r.oldestUnhanded!);
    final late = holds && days > 2;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(children: [
        CircleAvatar(
          radius: 17,
          backgroundColor: holds ? AppColors.amberBg : AppColors.greenBg,
          child: Text(r.name.isEmpty ? 'B' : r.name[0].toUpperCase(),
              style: TextStyle(fontWeight: FontWeight.w700, color: holds ? AppColors.amberDark : AppColors.green)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(child: Text(r.name, overflow: TextOverflow.ellipsis, style: _small(color: AppColors.text, w: FontWeight.w600, size: 13.5))),
              if (holds && r.oldestUnhanded != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1.5),
                  decoration: BoxDecoration(color: late ? AppColors.redBg : AppColors.amberBg, borderRadius: BorderRadius.circular(20)),
                  child: Text(days == 0 ? 'since today' : '$days day${days == 1 ? '' : 's'} out',
                      style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: late ? AppColors.red : AppColors.amberDark)),
                ),
              ],
            ]),
            const SizedBox(height: 2),
            Text(
              'Collected ${_rs(r.collectedInPeriod)} · handed ${_rs(r.handedInPeriod)} $_periodWord'
              '${r.lastHandover == null ? ' · never handed over' : ' · last ${_dm.format(r.lastHandover!)}'}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: _small(size: 11.5),
            ),
          ]),
        ),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(_rs(r.holding), style: _small(color: holds ? AppColors.text : AppColors.green, w: FontWeight.w700, size: 14)),
          Text(holds ? 'with booker' : 'all handed over', style: _small(size: 11)),
        ]),
        const SizedBox(width: 10),
        OutlinedButton(
          onPressed: () => _receive(booker: r),
          style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), visualDensity: VisualDensity.compact),
          child: const Text('Receive'),
        ),
      ]),
    );
  }

  // ---------------------------------------------------------------------------
  // History
  // ---------------------------------------------------------------------------

  Widget _history() {
    final list = _handovers.take(40).toList();
    return _panel(
      padding: const EdgeInsets.fromLTRB(0, 18, 0, 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: _panelTitle(Icons.history, 'Handovers', list.isEmpty ? 'none yet' : 'latest first · tap to edit'),
        ),
        const SizedBox(height: 10),
        if (list.isEmpty)
          Padding(
            padding: const EdgeInsets.all(20),
            child: Text('When a booker brings cash to the office, press Receive next to their name.', textAlign: TextAlign.center, style: _small()),
          ),
        for (var i = 0; i < list.length; i++) ...[
          if (i > 0) const Divider(height: 1, indent: 20, endIndent: 20),
          InkWell(
            onTap: () => _receive(edit: list[i]),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(list[i].bookerName.isEmpty ? (_names[list[i].bookerUid] ?? 'Booker') : list[i].bookerName,
                        style: _small(color: AppColors.text, w: FontWeight.w600, size: 13)),
                    Text(
                      [
                        _dm.format(list[i].date),
                        'into ${list[i].into.short.toLowerCase()}',
                        if (list[i].receivedBy.isNotEmpty) 'by ${list[i].receivedBy}',
                        if (list[i].note.isNotEmpty) list[i].note,
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _small(size: 11.5),
                    ),
                  ]),
                ),
                Text(_rs(list[i].amount), style: _small(color: AppColors.green, w: FontWeight.w700, size: 13)),
              ]),
            ),
          ),
        ],
      ]),
    );
  }

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
          Text(text, textAlign: TextAlign.center, style: _small()),
          if (action != null) ...[const SizedBox(height: 14), action],
        ]),
      );
}

TextStyle _small({Color color = AppColors.muted, FontWeight w = FontWeight.w400, double size = 12.5}) =>
    TextStyle(fontSize: size, fontWeight: w, color: color);

// =============================================================================
// Receive cash / edit a handover
// =============================================================================

class _ReceiveSheet extends StatefulWidget {
  final List<BookerCash> bookers;
  final BookerCash? booker;
  final Handover? edit;
  const _ReceiveSheet({required this.bookers, this.booker, this.edit});

  @override
  State<_ReceiveSheet> createState() => _ReceiveSheetState();
}

class _ReceiveSheetState extends State<_ReceiveSheet> {
  final _form = GlobalKey<FormState>();
  late String? _uid = widget.edit?.bookerUid ?? widget.booker?.uid ?? widget.bookers.where((b) => b.holding > 0.5).firstOrNull?.uid;
  late final _amount = TextEditingController(text: _initialAmount());
  late final _note = TextEditingController(text: widget.edit?.note ?? '');
  late DateTime _date = widget.edit?.date ?? DateTime.now();
  late MoneyAccount _into = widget.edit?.into ?? MoneyAccount.cash;
  bool _saving = false;

  bool get _editing => widget.edit?.id != null;

  String _initialAmount() {
    if (widget.edit != null) return widget.edit!.amount.round().toString();
    final b = widget.booker ?? widget.bookers.where((b) => b.uid == _uid).firstOrNull;
    return b != null && b.holding > 0.5 ? b.holding.round().toString() : '';
  }

  BookerCash? get _selected => widget.bookers.where((b) => b.uid == _uid).firstOrNull;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final b = _selected;
    setState(() => _saving = true);
    try {
      await saveHandover(Handover(
        id: widget.edit?.id,
        bookerUid: _uid!,
        bookerName: b?.name ?? widget.edit?.bookerName ?? '',
        amount: double.parse(_amount.text.trim()),
        date: _date,
        into: _into,
        note: _note.text,
      ));
      if (mounted) Navigator.pop(context, _editing ? 'Handover updated' : 'Cash received from ${b?.name ?? 'booker'}');
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Couldn't save: $e")));
      }
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete this handover?'),
        content: Text('${_rs(widget.edit!.amount)} on ${_dm.format(widget.edit!.date)}. The booker will show as holding this cash again. '
            'This can\'t be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: AppColors.red), onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _saving = true);
    try {
      await deleteHandover(widget.edit!.id!);
      if (mounted) Navigator.pop(context, 'Handover deleted');
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Couldn't delete: $e")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = _selected;
    final amount = double.tryParse(_amount.text.trim()) ?? 0;
    final over = !_editing && b != null && amount > b.holding + 0.5;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Form(
              key: _form,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(_editing ? 'Edit handover' : 'Receive cash from a booker',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.text)),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _uid,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Booker'),
                  items: [
                    for (final x in widget.bookers)
                      DropdownMenuItem(value: x.uid, child: Text('${x.name}  ·  holding ${_rs(x.holding)}', overflow: TextOverflow.ellipsis)),
                    if (_uid != null && widget.bookers.every((x) => x.uid != _uid))
                      DropdownMenuItem(value: _uid, child: Text(widget.edit?.bookerName ?? 'Booker')),
                  ],
                  onChanged: _editing
                      ? null
                      : (v) => setState(() {
                            _uid = v;
                            final nb = _selected;
                            _amount.text = nb != null && nb.holding > 0.5 ? nb.holding.round().toString() : '';
                          }),
                  validator: (v) => v == null ? 'Choose the booker' : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _amount,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  decoration: InputDecoration(
                    labelText: 'Amount received (Rs)',
                    prefixText: 'Rs  ',
                    helperText: b == null || _editing ? null : 'Holding ${_rs(b.holding)}',
                  ),
                  onChanged: (_) => setState(() {}),
                  validator: (v) {
                    final n = double.tryParse((v ?? '').trim());
                    if (n == null || n <= 0) return 'Enter the amount';
                    return null;
                  },
                ),
                if (over) ...[
                  const SizedBox(height: 6),
                  Text('That is more than the cash this booker has recorded. Check their khata entries.',
                      style: _small(color: AppColors.amberDark, size: 12)),
                ],
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(AppRadius.field),
                      onTap: () async {
                        final n = DateTime.now();
                        final d = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime(n.year - 2), lastDate: n);
                        if (d != null) setState(() => _date = d);
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(labelText: 'Date', prefixIcon: Icon(Icons.event_outlined, size: 20)),
                        child: Text(DateFormat('d MMM yyyy').format(_date)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<MoneyAccount>(
                      initialValue: _into,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Put into'),
                      items: [for (final a in MoneyAccount.values) DropdownMenuItem(value: a, child: Text(a.label, overflow: TextOverflow.ellipsis))],
                      onChanged: (v) => setState(() => _into = v ?? MoneyAccount.cash),
                    ),
                  ),
                ]),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _note,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Note (optional)', hintText: 'e.g. Short by Rs 200, will bring tomorrow'),
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
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text(_editing ? 'Save' : 'Receive'),
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
