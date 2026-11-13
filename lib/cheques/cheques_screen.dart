// Accounts → Cheques: every cheque from shops, from in hand to cleared. Which ones can be deposited
// today, which are in the bank, which bounced; deposit, clear, bounce or return each one.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../Admin/dashboard_overview.dart' show dashRs;
import '../account/account.dart';
import '../audit/audit.dart';
import '../ui/app_theme.dart';
import '../ui/excel_export.dart';
import '../ui/kpi_card.dart';
import 'cheques_data.dart';

final _money = NumberFormat('#,##0');
final _date = DateFormat('d MMM yyyy');

enum _Filter { open, inHand, deposited, cleared, bounced, returned, all }

const _filterNames = {
  _Filter.open: 'Not cleared yet',
  _Filter.inHand: 'In hand',
  _Filter.deposited: 'In the bank',
  _Filter.cleared: 'Cleared',
  _Filter.bounced: 'Bounced',
  _Filter.returned: 'Returned',
  _Filter.all: 'All',
};

class ChequesScreen extends StatefulWidget {
  const ChequesScreen({super.key});

  @override
  State<ChequesScreen> createState() => _ChequesScreenState();
}

class _ChequesScreenState extends State<ChequesScreen> {
  List<Cheque>? _all;
  Object? _error;
  _Filter _filter = _Filter.open;
  String _search = '';
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final list = await loadCheques();
      if (mounted) setState(() => _all = list);
    } catch (e) {
      debugPrint('Cheques: $e');
      if (mounted) setState(() => _error = e);
    }
  }

  List<Cheque> get _shown {
    final q = _search.trim().toLowerCase();
    final list = [
      for (final c in _all ?? const <Cheque>[])
        if (switch (_filter) {
              _Filter.open => c.status.open,
              _Filter.inHand => c.status == ChequeStatus.inHand,
              _Filter.deposited => c.status == ChequeStatus.deposited,
              _Filter.cleared => c.status == ChequeStatus.cleared,
              _Filter.bounced => c.status == ChequeStatus.bounced,
              _Filter.returned => c.status == ChequeStatus.returned,
              _Filter.all => true,
            } &&
            (q.isEmpty || '${c.customer} ${c.bank} ${c.number}'.toLowerCase().contains(q)))
          c,
    ];
    // Open cheques: soonest date first (what to deposit next); the rest: latest first.
    if (_filter == _Filter.open || _filter == _Filter.inHand || _filter == _Filter.deposited) {
      list.sort((a, b) => a.chequeDate.compareTo(b.chequeDate));
    }
    return list;
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  Future<void> _act(Cheque c, Future<void> Function() job, String done) async {
    setState(() => _busy.add(c.id));
    try {
      await job();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Couldn't save: $e")));
    } finally {
      if (mounted) setState(() => _busy.remove(c.id));
    }
  }

  Future<DateTime?> _pickDay(String help, {DateTime? first}) => showDatePicker(
        context: context,
        initialDate: DateTime.now(),
        firstDate: first ?? DateTime(2020),
        lastDate: DateTime.now(),
        helpText: help,
      );

  Future<void> _deposit(Cheque c) async {
    if (c.daysToDate(DateTime.now()) > 0) {
      final go = await _confirm('The cheque is dated ${_date.format(c.chequeDate)}',
          'The bank won\'t pay it before that date. Deposit it anyway?', 'Deposit');
      if (go != true) return;
    }
    final day = await _pickDay('Deposited on', first: c.receivedOn);
    if (day == null) return;
    await _act(c, () => depositCheque(c, day), '${c.title} deposited');
  }

  Future<void> _clear(Cheque c) async {
    final day = await _pickDay('Money received on', first: c.depositedOn ?? c.receivedOn);
    if (day == null || !mounted) return;
    if (!await ensureOpenPeriod(context, day)) return;
    await _act(c, () => clearCheque(c, day), 'Cleared: Rs ${_money.format(c.amount)} paid in ${c.customer}\'s khata');
  }

  Future<void> _bounce(Cheque c) async {
    final r = await showDialog<(DateTime, String, double)>(context: context, builder: (_) => _BounceDialog(cheque: c));
    if (r == null || !mounted) return;
    if (r.$3 > 0 && !await ensureOpenPeriod(context, r.$1)) return;
    await _act(c, () => bounceCheque(c, r.$1, reason: r.$2, charge: r.$3),
        'Bounced: ${c.customer} still owes Rs ${_money.format(c.amount)}${r.$3 > 0 ? ' + Rs ${_money.format(r.$3)} charge' : ''}');
  }

  Future<void> _return(Cheque c) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Give the cheque back to the shop?'),
        content: SizedBox(
          width: 400,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('${c.title} · Rs ${_money.format(c.amount)}. Nothing changes in the khata.',
                style: const TextStyle(fontSize: 13, color: AppColors.muted)),
            const SizedBox(height: 12),
            TextField(controller: ctrl, decoration: const InputDecoration(labelText: 'Why (e.g. paid in cash instead)')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Returned')),
        ],
      ),
    );
    if (ok != true) return;
    await _act(c, () => returnCheque(c, reason: ctrl.text), '${c.title} marked returned');
  }

  Future<void> _delete(Cheque c) async {
    final ok = await _confirm('Delete this cheque?', '${c.title} · ${c.customer} · Rs ${_money.format(c.amount)}. '
        'Only for a cheque entered by mistake; the audit log keeps a record.', 'Delete', danger: true);
    if (ok != true) return;
    await _act(c, () => deleteCheque(c), 'Cheque deleted');
  }

  Future<bool?> _confirm(String title, String text, String yes, {bool danger = false}) => showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: Text(title),
          content: Text(text),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
            FilledButton(
              style: danger ? FilledButton.styleFrom(backgroundColor: AppColors.red) : null,
              onPressed: () => Navigator.pop(d, true),
              child: Text(yes),
            ),
          ],
        ),
      );

  Future<void> _add() async {
    final saved = await showDialog<bool>(context: context, builder: (_) => const _AddChequeDialog());
    if (saved == true) _load();
  }

  void _export(List<Cheque> list) => exportToExcel(
        context,
        fileName: exportFileName('cheques'),
        title: 'Cheques',
        subtitle: _filterNames[_filter]!,
        sheets: [
          ExportSheet(
            name: 'Cheques',
            headers: ['Cheque date', 'Shop', 'Bank', 'Cheque #', 'Amount (Rs)', 'Status', 'Received', 'Deposited', 'Cleared', 'Bounced', 'Reason', 'Note'],
            rows: [
              for (final c in list)
                [c.chequeDate, c.customer, c.bank, c.number, c.amount, c.status.label, c.receivedOn, c.depositedOn, c.clearedOn, c.bouncedOn, c.bounceReason, c.note],
            ],
            totals: ['Total', null, null, null, list.fold<double>(0, (s, c) => s + c.amount)],
          ),
        ],
      );

  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final list = _all == null ? null : _shown;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cheques'),
        actions: [
          ExcelButton(onPressed: list == null || list.isEmpty ? null : () => _export(list)),
          IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh), onPressed: _load),
          const SizedBox(width: 4),
          FilledButton.icon(onPressed: _add, icon: const Icon(Icons.add, size: 18), label: const Text('Add cheque')),
          const SizedBox(width: 12),
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
                  if (_all == null)
                    _error != null
                        ? _panel(child: _empty(Icons.cloud_off, "Couldn't load cheques", 'Check the connection and try again.'))
                        : const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator()))
                  else ...[
                    _kpis(wide),
                    const SizedBox(height: 16),
                    _listPanel(list!, wide),
                  ],
                ]),
              ),
            ),
          ],
        );
      }),
    );
  }

  Widget _kpis(bool wide) {
    final s = ChequeSummary.of(_all!, DateTime.now());
    return kpiGrid([
      KpiCard(
        label: 'IN HAND',
        icon: Icons.money_outlined,
        tint: AppColors.navy,
        tintBg: AppColors.brandSoft,
        value: dashRs(s.inHandAmount),
        sub: '${s.inHand} cheque${s.inHand == 1 ? '' : 's'} not deposited',
        onTap: () => setState(() => _filter = _Filter.inHand),
      ),
      KpiCard(
        label: 'DEPOSIT NOW',
        icon: Icons.event_available_outlined,
        tint: s.due > 0 ? AppColors.amber : AppColors.green,
        tintBg: s.due > 0 ? AppColors.amberBg : AppColors.greenBg,
        value: dashRs(s.dueAmount),
        sub: s.due == 0 ? 'nothing dated today or earlier' : '${s.due} dated today or earlier',
        onTap: () => setState(() => _filter = _Filter.inHand),
      ),
      KpiCard(
        label: 'IN THE BANK',
        icon: Icons.account_balance_outlined,
        tint: AppColors.blue,
        tintBg: AppColors.blueBg,
        value: dashRs(s.depositedAmount),
        sub: '${s.deposited} waiting to clear',
        onTap: () => setState(() => _filter = _Filter.deposited),
      ),
      KpiCard(
        label: 'BOUNCED THIS MONTH',
        icon: Icons.report_gmailerrorred_outlined,
        tint: s.bounced > 0 ? AppColors.red : AppColors.navy,
        tintBg: s.bounced > 0 ? AppColors.redBg : AppColors.brandSoft,
        value: '${s.bounced}',
        valueColor: s.bounced > 0 ? AppColors.red : null,
        sub: s.bounced == 0 ? 'none' : '${dashRs(s.bouncedAmount)} still owed',
        onTap: () => setState(() => _filter = _Filter.bounced),
      ),
    ], wide ? 4 : 2);
  }

  Widget _listPanel(List<Cheque> list, bool wide) => _panel(
        padding: const EdgeInsets.fromLTRB(0, 16, 0, 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              for (final f in _Filter.values)
                ChoiceChip(
                  label: Text(_filterNames[f]!),
                  selected: _filter == f,
                  showCheckmark: false,
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) => setState(() => _filter = f),
                ),
              SizedBox(
                width: wide ? 220 : double.infinity,
                child: TextField(
                  decoration: const InputDecoration(isDense: true, prefixIcon: Icon(Icons.search, size: 18), hintText: 'Shop, bank or cheque #'),
                  onChanged: (v) => setState(() => _search = v),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 8),
          if (list.isEmpty)
            _empty(Icons.money_outlined, 'No cheques here',
                'Cheques come in from the khata (payment by cheque) or with Add cheque. They count as paid only once they clear.')
          else
            for (var i = 0; i < list.length; i++) ...[
              if (i > 0) const Divider(height: 1, indent: 20, endIndent: 20),
              _row(list[i], wide),
            ],
        ]),
      );

  Widget _row(Cheque c, bool wide) {
    final today = DateTime.now();
    final days = c.daysToDate(today);
    final (Color fg, Color bg) = switch (c.status) {
      ChequeStatus.inHand => (AppColors.navy, AppColors.brandSoft),
      ChequeStatus.deposited => (AppColors.blue, AppColors.blueBg),
      ChequeStatus.cleared => (AppColors.green, AppColors.greenBg),
      ChequeStatus.bounced => (AppColors.red, AppColors.redBg),
      ChequeStatus.returned => (AppColors.muted, AppColors.bg),
    };
    final when = switch (c.status) {
      ChequeStatus.inHand => days > 0
          ? 'dated ${_date.format(c.chequeDate)} · in $days day${days == 1 ? '' : 's'}'
          : days == 0
              ? 'dated today · deposit it'
              : 'dated ${_date.format(c.chequeDate)} · deposit it',
      ChequeStatus.deposited => 'deposited ${_date.format(c.depositedOn ?? c.chequeDate)}',
      ChequeStatus.cleared => 'cleared ${_date.format(c.clearedOn ?? c.chequeDate)}',
      ChequeStatus.bounced => 'bounced ${_date.format(c.bouncedOn ?? c.chequeDate)}'
          '${c.bounceReason.isEmpty ? '' : ' · ${c.bounceReason}'}${c.bounceCharge > 0 ? ' · charge Rs ${_money.format(c.bounceCharge)}' : ''}',
      ChequeStatus.returned => 'given back${c.note.isEmpty ? '' : ' · ${c.note}'}',
    };
    final busy = _busy.contains(c.id);
    final actions = <Widget>[
      if (busy)
        const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
      else ...[
        if (c.status == ChequeStatus.inHand) ...[
          FilledButton.tonal(onPressed: () => _deposit(c), child: const Text('Deposit')),
          TextButton(onPressed: () => _return(c), child: const Text('Return')),
        ],
        if (c.status == ChequeStatus.deposited) ...[
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.green),
            onPressed: () => _clear(c),
            child: const Text('Cleared'),
          ),
          OutlinedButton(
            style: OutlinedButton.styleFrom(foregroundColor: AppColors.red),
            onPressed: () => _bounce(c),
            child: const Text('Bounced'),
          ),
        ],
        if (c.status == ChequeStatus.inHand || c.status == ChequeStatus.returned)
          IconButton(tooltip: 'Delete', icon: const Icon(Icons.delete_outline, size: 19, color: AppColors.muted), onPressed: () => _delete(c)),
      ],
    ];
    final info = Expanded(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text(c.customer, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.text)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
            child: Text(c.status.label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg)),
          ),
        ]),
        const SizedBox(height: 2),
        Text('${c.title}${c.userEmail.isEmpty ? '' : ' · ${c.userEmail}'}', style: const TextStyle(fontSize: 12, color: AppColors.muted)),
        Text(when,
            style: TextStyle(
              fontSize: 12,
              color: c.dueToDeposit(today) ? AppColors.amberDark : (c.status == ChequeStatus.bounced ? AppColors.red : AppColors.muted),
              fontWeight: c.dueToDeposit(today) ? FontWeight.w600 : null,
            )),
      ]),
    );
    final amount = Text('Rs ${_money.format(c.amount)}',
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: c.status == ChequeStatus.returned ? AppColors.muted : AppColors.text,
          decoration: c.status == ChequeStatus.returned ? TextDecoration.lineThrough : null,
        ));
    final icon = Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Icon(Icons.money_outlined, size: 18, color: fg),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
      child: wide
          ? Row(children: [
              icon,
              const SizedBox(width: 12),
              info,
              const SizedBox(width: 12),
              amount,
              const SizedBox(width: 16),
              SizedBox(width: 230, child: Wrap(alignment: WrapAlignment.end, spacing: 6, children: actions)),
            ])
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [icon, const SizedBox(width: 12), info, const SizedBox(width: 8), amount]),
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 6),
                Wrap(alignment: WrapAlignment.end, spacing: 6, children: actions),
              ],
            ]),
    );
  }

  Widget _panel({required Widget child, EdgeInsets padding = const EdgeInsets.fromLTRB(20, 18, 20, 12)}) =>
      Container(decoration: kpiCardDecoration(), clipBehavior: Clip.antiAlias, padding: padding, child: child);

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

// =============================================================================
// Dialogs
// =============================================================================

class _BounceDialog extends StatefulWidget {
  final Cheque cheque;
  const _BounceDialog({required this.cheque});
  @override
  State<_BounceDialog> createState() => _BounceDialogState();
}

class _BounceDialogState extends State<_BounceDialog> {
  static const _reasons = ['Insufficient funds', 'Signature mismatch', 'Stopped by the shop', 'Account closed'];
  String _reason = _reasons.first;
  final _other = TextEditingController();
  final _charge = TextEditingController();
  DateTime _day = DateTime.now();

  @override
  void dispose() {
    _other.dispose();
    _charge.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.cheque;
    return AlertDialog(
      icon: const Icon(Icons.report_gmailerrorred_outlined, color: AppColors.red),
      title: const Text('Cheque bounced'),
      content: SizedBox(
        width: 440,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('${c.title} · ${c.customer} · Rs ${_money.format(c.amount)}. Nothing comes off the khata: the shop still owes it.',
              style: const TextStyle(fontSize: 13, color: AppColors.muted)),
          const SizedBox(height: 14),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final r in [..._reasons, 'Other'])
              ChoiceChip(
                label: Text(r),
                selected: _reason == r,
                showCheckmark: false,
                visualDensity: VisualDensity.compact,
                onSelected: (_) => setState(() => _reason = r),
              ),
          ]),
          if (_reason == 'Other') ...[
            const SizedBox(height: 10),
            TextField(controller: _other, decoration: const InputDecoration(labelText: 'Reason')),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _charge,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Bounce charge (optional)',
              prefixText: 'Rs  ',
              helperText: 'Added to the shop\'s khata as udhaar',
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            icon: const Icon(Icons.calendar_today_outlined, size: 16),
            label: Text('Bounced on ${_date.format(_day)}'),
            onPressed: () async {
              final d = await showDatePicker(
                  context: context, initialDate: _day, firstDate: c.depositedOn ?? c.receivedOn, lastDate: DateTime.now());
              if (d != null) setState(() => _day = d);
            },
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.red),
          onPressed: () {
            final reason = _reason == 'Other' ? _other.text.trim() : _reason;
            Navigator.pop(context, (_day, reason, double.tryParse(_charge.text.trim()) ?? 0));
          },
          child: const Text('Mark bounced'),
        ),
      ],
    );
  }
}

class _AddChequeDialog extends StatefulWidget {
  const _AddChequeDialog();
  @override
  State<_AddChequeDialog> createState() => _AddChequeDialogState();
}

class _AddChequeDialogState extends State<_AddChequeDialog> {
  final _form = GlobalKey<FormState>();
  final _bank = TextEditingController();
  final _number = TextEditingController();
  final _amount = TextEditingController();
  final _note = TextEditingController();
  TextEditingController? _shop;
  DateTime _chequeDate = DateTime.now();
  DateTime _received = DateTime.now();
  // Shop name → the booker whose khata it is in.
  Map<String, (String, String)> _shops = {};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    companyCol('customers').get().then((s) {
      if (!mounted) return;
      setState(() => _shops = {
            for (final d in s.docs)
              if ('${d.data()['name'] ?? ''}'.trim().isNotEmpty)
                '${d.data()['name']}'.trim(): ('${d.data()['salesmanUid'] ?? ''}', '${d.data()['salesman'] ?? ''}'),
          });
    }).catchError((Object e) {
      debugPrint('Shops: $e');
    });
  }

  @override
  void dispose() {
    for (final c in [_bank, _number, _amount, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final shop = _shop!.text.trim();
    final booker = _shops[shop];
    setState(() => _saving = true);
    try {
      await addCheque(
        customer: shop,
        bank: _bank.text,
        number: _number.text,
        amount: double.parse(_amount.text.trim()),
        chequeDate: _chequeDate,
        receivedOn: _received,
        note: _note.text,
        // the shop's booker's khata, so the payment lands where the shop's invoices are
        userId: (booker?.$1 ?? '').isEmpty ? null : booker!.$1,
        userEmail: (booker?.$1 ?? '').isEmpty ? null : booker!.$2,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Couldn't save: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget dateBtn(String label, DateTime value, ValueChanged<DateTime> set, {DateTime? last}) => OutlinedButton.icon(
          icon: const Icon(Icons.calendar_today_outlined, size: 16),
          label: Text('$label ${_date.format(value)}'),
          onPressed: () async {
            final d = await showDatePicker(context: context, initialDate: value, firstDate: DateTime(2020), lastDate: last ?? DateTime(2100));
            if (d != null) setState(() => set(d));
          },
        );
    return AlertDialog(
      title: const Text('Add a cheque'),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Autocomplete<String>(
                optionsBuilder: (v) => _shops.keys.where((n) => n.toLowerCase().contains(v.text.toLowerCase())),
                fieldViewBuilder: (context, ctrl, focus, onSubmit) {
                  _shop = ctrl;
                  return TextFormField(
                    controller: ctrl,
                    focusNode: focus,
                    decoration: const InputDecoration(labelText: 'Shop'),
                    validator: (v) => (v ?? '').trim().isEmpty ? 'Which shop gave it?' : null,
                  );
                },
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: TextFormField(controller: _bank, decoration: const InputDecoration(labelText: 'Bank'))),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _number,
                    decoration: const InputDecoration(labelText: 'Cheque #'),
                    validator: (v) => (v ?? '').trim().isEmpty ? 'Cheque number' : null,
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              TextFormField(
                controller: _amount,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                decoration: const InputDecoration(labelText: 'Amount', prefixText: 'Rs  '),
                validator: (v) => (double.tryParse((v ?? '').trim()) ?? 0) <= 0 ? 'Enter the amount' : null,
              ),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
                dateBtn('Dated', _chequeDate, (d) => _chequeDate = d),
                dateBtn('Received', _received, (d) => _received = d, last: DateTime.now()),
              ]),
              const SizedBox(height: 12),
              TextFormField(controller: _note, decoration: const InputDecoration(labelText: 'Note (optional)')),
              const SizedBox(height: 10),
              const Text('It counts in the shop\'s khata only once it clears.', style: TextStyle(fontSize: 12, color: AppColors.muted)),
            ]),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _saving ? null : _save, child: const Text('Add cheque')),
      ],
    );
  }
}
