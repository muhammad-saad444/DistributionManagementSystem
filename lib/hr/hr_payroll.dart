// Payroll: one salary sheet a month. Prepare (from salaries, attendance, sales, advances and
// statutory settings) → adjust bonuses/deductions → finalise (payslips issued, advances repaid) →
// mark paid.
import 'package:flutter/material.dart';

import '../crm/crm_ui.dart';
import '../print_preview.dart';
import 'hr_data.dart';
import 'hr_pdf.dart';
import 'hr_ui.dart';

class PayrollTab extends StatefulWidget {
  const PayrollTab({super.key});

  @override
  State<PayrollTab> createState() => _PayrollTabState();
}

class _PayrollTabState extends State<PayrollTab> {
  // Salaries are usually made for the month just finished.
  String _month = monthKey(DateTime(DateTime.now().year, DateTime.now().month - 1));
  PayrollRun? _run;
  bool _loaded = false;
  Object? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _error = null;
      _loaded = false;
    });
    try {
      final r = await loadPayrollRun(_month);
      if (mounted) {
        setState(() {
          _run = r;
          _loaded = true;
        });
      }
    } catch (e) {
      debugPrint('Payroll: $e');
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _work(Future<void> Function() job, String done) async {
    setState(() => _busy = true);
    try {
      await job();
      if (mounted && done.isNotEmpty) crmSnack(context, done);
      await _load();
    } catch (e) {
      debugPrint('Payroll action failed: $e');
      if (mounted) crmSnack(context, "Couldn't finish. Check your connection and try again.", error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _prepare() => _work(() async {
        final run = await calculatePayroll(_month, previous: _run);
        await savePayrollDraft(run);
      }, _run == null ? 'Salary sheet prepared' : 'Recalculated from the latest attendance and sales');

  Future<void> _finalise() async {
    final run = _run!;
    if (!await hrConfirm(
        context,
        'Finalise ${hrMonthLabel.format(monthStart(_month))}?',
        'Payslips are issued (bookers see theirs in the app) and advance installments are recorded as repaid. '
            'Total net pay: ${crmRs(run.totalNet)}.',
        'Finalise')) {
      return;
    }
    await _work(() => finalisePayroll(run), 'Finalised. Payslips issued.');
  }

  Future<void> _reopen() async {
    if (!await hrConfirm(context, 'Reopen this month?',
        'Payslips are withdrawn and advance repayments undone, so you can change the sheet.', 'Reopen',
        danger: true)) {
      return;
    }
    await _work(() => reopenPayroll(_run!), 'Back to draft');
  }

  Future<void> _paid() async {
    var method = 'Bank transfer';
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, set) => AlertDialog(
          title: Text('Mark salaries paid', style: CrmTokens.display(size: 17)),
          content: DropdownButtonFormField<String>(
            initialValue: method,
            decoration: crmInput('Paid by'),
            items: [
              for (final m in ['Bank transfer', 'Cash', 'Cheque'])
                DropdownMenuItem(value: m, child: Text(m, style: CrmTokens.body())),
            ],
            onChanged: (v) => set(() => method = v ?? method),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: Text('Cancel', style: CrmTokens.body())),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: CrmTokens.green, elevation: 0),
              onPressed: () => Navigator.pop(d, true),
              child: Text('Paid', style: CrmTokens.body(color: Colors.white, w: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
    if (ok == true) await _work(() => markPayrollPaid(_month, method), 'Marked as paid');
  }

  Future<void> _edit(PayLine l) async {
    final bonus = TextEditingController(text: l.bonus == 0 ? '' : hrPlain(l.bonus));
    final other = TextEditingController(text: l.otherDeduction == 0 ? '' : hrPlain(l.otherDeduction));
    final note = TextEditingController(text: l.note);
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(l.name, style: CrmTokens.display(size: 17)),
        content: SizedBox(
          width: 380,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            HrField(bonus, 'Bonus / overtime / other earnings (Rs.)', number: true, icon: Icons.add_circle_outline),
            const SizedBox(height: 10),
            HrField(other, 'Other deduction (Rs.)', number: true, icon: Icons.remove_circle_outline,
                hint: 'Damages, shortages…'),
            const SizedBox(height: 10),
            HrField(note, 'Note on payslip'),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: Text('Cancel', style: CrmTokens.body())),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: CrmTokens.navy, elevation: 0),
            onPressed: () => Navigator.pop(d, true),
            child: Text('Save', style: CrmTokens.body(color: Colors.white, w: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final run = _run!;
    final changed = l.withManual(
      bonus: num.tryParse(bonus.text.trim()) ?? 0,
      otherDeduction: num.tryParse(other.text.trim()) ?? 0,
      note: note.text.trim(),
    );
    // Tax depends on the bonus, so the whole sheet is re-worked out with the new manual figures.
    final updated = PayrollRun(
        month: run.month, lines: [for (final x in run.lines) x.employeeId == l.employeeId ? changed : x]);
    await _work(() async => savePayrollDraft(await calculatePayroll(_month, previous: updated)), '');
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: CrmTokens.navy,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 40),
        children: [
          HrMonthBar(_month, (m) {
            setState(() => _month = m);
            _load();
          }),
          if (_busy) const LinearProgressIndicator(minHeight: 2, color: CrmTokens.amber),
          const SizedBox(height: 12),
          if (!_loaded)
            SizedBox(height: 200, child: hrLoading(_error, _load, what: 'the salary sheet'))
          else if (_run == null)
            _empty()
          else
            ..._sheet(_run!),
        ],
      ),
    );
  }

  Widget _empty() => CrmCard(
        child: Column(children: [
          const Icon(Icons.request_quote_outlined, size: 40, color: CrmTokens.muted),
          const SizedBox(height: 8),
          Text('No salary sheet for ${hrMonthLabel.format(monthStart(_month))} yet.', style: CrmTokens.body()),
          const SizedBox(height: 4),
          Text(
            'It is worked out from each person\'s salary and allowances, this month\'s attendance and leave, '
            'bookers\' sales (commission and target bonus), advances, EOBI and income tax.',
            textAlign: TextAlign.center,
            style: CrmTokens.body(size: 12, color: CrmTokens.muted),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: CrmTokens.amber, elevation: 0),
            onPressed: _busy ? null : _prepare,
            icon: const Icon(Icons.calculate_outlined, color: CrmTokens.navyDark),
            label: Text('Prepare salary sheet', style: CrmTokens.body(color: CrmTokens.navyDark, w: FontWeight.w700)),
          ),
        ]),
      );

  List<Widget> _sheet(PayrollRun run) {
    final (label, color, bg) = switch (run.status) {
      'final' => ('Final — not paid yet', CrmTokens.blue, CrmTokens.blueBg),
      'paid' => ('Paid${run.paidMethod.isNotEmpty ? ' (${run.paidMethod})' : ''}', CrmTokens.green, CrmTokens.greenBg),
      _ => ('Draft', CrmTokens.amber, CrmTokens.amberBg),
    };
    num sum(num Function(PayLine) f) => run.lines.fold<num>(0, (s, l) => s + f(l));
    return [
      Row(children: [
        CrmPill(label, color: color, background: bg),
        const Spacer(),
        IconButton(
          tooltip: 'Print all payslips',
          onPressed: run.lines.isEmpty
              ? null
              : () => showPrintPreview(context,
                  title: 'Payslips ${hrMonthLabel.format(monthStart(run.month))}',
                  buildPdf: () => payslipsPdf(run.month, run.lines),
                  fileName: 'Payslips_${run.month}.pdf'),
          icon: const Icon(Icons.print_outlined, color: CrmTokens.navy),
        ),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: CrmStat(label: 'Net salaries', value: crmRs(run.totalNet))),
        const SizedBox(width: 8),
        Expanded(child: CrmStat(label: 'Cost to company', value: crmRs(run.totalEmployerCost))),
      ]),
      const SizedBox(height: 8),
      CrmCard(
        child: Column(children: [
          HrInfoRow('Earned salaries', crmRs(sum((l) => l.earned))),
          HrInfoRow('Commission and target bonus', crmRs(sum((l) => l.commission + l.targetBonus))),
          HrInfoRow('Bonuses', crmRs(sum((l) => l.bonus))),
          HrInfoRow('Advances recovered', crmRs(sum((l) => l.advanceDeduction))),
          HrInfoRow('Income tax withheld', crmRs(sum((l) => l.tax))),
          HrInfoRow('EOBI (employee / employer)', '${crmRs(sum((l) => l.eobiEmployee))} / ${crmRs(sum((l) => l.eobiEmployer))}'),
          HrInfoRow('Social security (employer)', crmRs(sum((l) => l.socialSecurityEmployer))),
        ]),
      ),
      const SizedBox(height: 10),
      Wrap(spacing: 8, runSpacing: 8, children: [
        if (run.isDraft) ...[
          OutlinedButton.icon(
            onPressed: _busy ? null : _prepare,
            icon: const Icon(Icons.refresh, color: CrmTokens.navy),
            label: Text('Recalculate', style: CrmTokens.body(color: CrmTokens.navy, w: FontWeight.w600)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: CrmTokens.navy, elevation: 0),
            onPressed: _busy || run.lines.isEmpty ? null : _finalise,
            icon: const Icon(Icons.lock_outline, color: Colors.white),
            label: Text('Finalise and issue payslips', style: CrmTokens.body(color: Colors.white, w: FontWeight.w600)),
          ),
        ] else ...[
          if (run.status == 'final')
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: CrmTokens.green, elevation: 0),
              onPressed: _busy ? null : _paid,
              icon: const Icon(Icons.payments_outlined, color: Colors.white),
              label: Text('Mark salaries paid', style: CrmTokens.body(color: Colors.white, w: FontWeight.w600)),
            ),
          OutlinedButton.icon(
            onPressed: _busy ? null : _reopen,
            icon: const Icon(Icons.lock_open, color: CrmTokens.muted),
            label: Text('Reopen', style: CrmTokens.body(color: CrmTokens.muted)),
          ),
        ],
      ]),
      CrmSectionTitle('People', trailing: Text('${run.lines.length}', style: CrmTokens.body(color: CrmTokens.muted))),
      if (run.lines.isEmpty)
        Text('Nobody with a salary was employed this month.', style: CrmTokens.body(color: CrmTokens.muted)),
      for (final l in run.lines) _line(run, l),
    ];
  }

  Widget _line(PayrollRun run, PayLine l) {
    final details = [
      '${hrPlain(l.daysAtWork)}/${l.workingDays} days',
      if (l.unpaidDays > 0) '${hrPlain(l.unpaidDays)} unpaid',
      if (l.lates > 0) '${hrPlain(l.lates)} late',
      if (l.commission + l.targetBonus > 0) 'commission ${crmRs(l.commission + l.targetBonus)}',
      if (l.advanceDeduction > 0) 'advance −${crmRs(l.advanceDeduction)}',
      if (l.tax > 0) 'tax −${crmRs(l.tax)}',
      if (l.bonus > 0) 'bonus ${crmRs(l.bonus)}',
      if (l.otherDeduction > 0) 'other −${crmRs(l.otherDeduction)}',
    ].join('  ·  ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: CrmCard(
        onTap: run.isDraft ? () => _edit(l) : null,
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${l.name}  ·  ${l.designation}', style: CrmTokens.body(w: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(details, style: CrmTokens.body(size: 11.5, color: CrmTokens.muted)),
            ]),
          ),
          Text(crmRs(l.net), style: CrmTokens.body(size: 14, w: FontWeight.w700)),
          IconButton(
            tooltip: 'Payslip',
            icon: const Icon(Icons.receipt_long_outlined, color: CrmTokens.navy, size: 20),
            onPressed: () => showPrintPreview(context,
                title: 'Payslip — ${l.name}',
                buildPdf: () => payslipPdf(run.month, l),
                fileName: 'Payslip_${l.name.replaceAll(' ', '_')}_${run.month}.pdf'),
          ),
        ]),
      ),
    );
  }
}
