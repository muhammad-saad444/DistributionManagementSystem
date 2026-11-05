// The admin HR area: Staff, Attendance, Leave, Payroll, Reports, Settings.
import 'package:flutter/material.dart';

import '../crm/crm_ui.dart';
import 'hr_attendance.dart';
import 'hr_data.dart';
import 'hr_payroll.dart';
import 'hr_reports.dart';
import 'hr_staff.dart';
import 'hr_ui.dart';

class AdminHrScreen extends StatelessWidget {
  const AdminHrScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 6,
      child: Scaffold(
        backgroundColor: CrmTokens.bg,
        appBar: AppBar(
          backgroundColor: CrmTokens.navy,
          elevation: 0,
          automaticallyImplyLeading: false,
          title: Text('HR', style: CrmTokens.display(size: 18, color: Colors.white, w: FontWeight.w600)),
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            indicatorColor: CrmTokens.amber,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            labelStyle: CrmTokens.body(w: FontWeight.w600, color: Colors.white),
            tabs: const [
              Tab(text: 'Staff'),
              Tab(text: 'Attendance'),
              Tab(text: 'Leave'),
              Tab(text: 'Payroll'),
              Tab(text: 'Reports'),
              Tab(text: 'Settings'),
            ],
          ),
        ),
        body: const TabBarView(children: [
          StaffTab(),
          AttendanceTab(),
          LeaveTab(),
          PayrollTab(),
          HrReportsTab(),
          HrSettingsTab(),
        ]),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Settings
// -----------------------------------------------------------------------------

class HrSettingsTab extends StatefulWidget {
  const HrSettingsTab({super.key});

  @override
  State<HrSettingsTab> createState() => _HrSettingsTabState();
}

class _HrSettingsTabState extends State<HrSettingsTab> {
  HrSettings? _s;
  Object? _error;
  bool _saving = false;
  // Editable copies
  final List<(TextEditingController, TextEditingController, bool)> _leave = [];
  final List<(TextEditingController, TextEditingController, TextEditingController)> _slabs = [];
  Set<int> _off = {};
  final _lateAfter = TextEditingController();
  final _latesPerDay = TextEditingController();
  final _minWage = TextEditingController();
  final _eobiEmp = TextEditingController();
  final _eobiEr = TextEditingController();
  final _ssPct = TextEditingController();
  final _ssCeiling = TextEditingController();
  bool _encash = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final s = await loadHrSettings();
      if (!mounted) return;
      setState(() => _fill(s));
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  void _fill(HrSettings s) {
    _s = s;
    _leave
      ..clear()
      ..addAll([
        for (final l in s.leaveTypes) (TextEditingController(text: l.name), TextEditingController(text: hrPlain(l.daysPerYear)), l.paid),
      ]);
    _slabs
      ..clear()
      ..addAll([
        for (final t in s.taxSlabs)
          (
            TextEditingController(text: hrPlain(t.from)),
            TextEditingController(text: hrPlain(t.fixed)),
            TextEditingController(text: hrPlain(t.rate)),
          ),
      ]);
    _off = {...s.weeklyOff};
    _lateAfter.text = s.lateAfter;
    _latesPerDay.text = '${s.latesPerDay}';
    _minWage.text = hrPlain(s.minimumWage);
    _eobiEmp.text = hrPlain(s.eobiEmployeePct);
    _eobiEr.text = hrPlain(s.eobiEmployerPct);
    _ssPct.text = hrPlain(s.socialSecurityPct);
    _ssCeiling.text = s.socialSecurityCeiling == 0 ? '' : hrPlain(s.socialSecurityCeiling);
    _encash = s.encashLeave;
  }

  num _n(TextEditingController c) => num.tryParse(c.text.trim()) ?? 0;

  Future<void> _save() async {
    if (!RegExp(r'^\d{1,2}:\d{2}$').hasMatch(_lateAfter.text.trim())) {
      return crmSnack(context, 'Late after: use HH:mm, e.g. 09:30', error: true);
    }
    final leave = [
      for (final l in _leave)
        if (l.$1.text.trim().isNotEmpty) LeaveType(l.$1.text.trim(), _n(l.$2), paid: l.$3),
    ];
    if (leave.isEmpty) return crmSnack(context, 'Keep at least one leave type', error: true);
    final s = HrSettings(
      leaveTypes: leave,
      weeklyOff: _off,
      lateAfter: _lateAfter.text.trim().padLeft(5, '0'),
      latesPerDay: _n(_latesPerDay).toInt(),
      taxSlabs: [for (final t in _slabs) TaxSlab(_n(t.$1), _n(t.$2), _n(t.$3))]..sort((a, b) => a.from.compareTo(b.from)),
      minimumWage: _n(_minWage),
      eobiEmployeePct: _n(_eobiEmp),
      eobiEmployerPct: _n(_eobiEr),
      socialSecurityPct: _n(_ssPct),
      socialSecurityCeiling: _n(_ssCeiling),
      encashLeave: _encash,
    );
    setState(() => _saving = true);
    try {
      await saveHrSettings(s);
      if (mounted) crmSnack(context, 'HR settings saved');
    } catch (_) {
      if (mounted) crmSnack(context, "Couldn't save. Check your connection.", error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_s == null) return hrLoading(_error, _load, what: 'HR settings');
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 6, 14, 40),
          children: [
            const CrmSectionTitle('Working days'),
            CrmCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Weekly off', style: CrmTokens.body(w: FontWeight.w600)),
                const SizedBox(height: 6),
                Wrap(spacing: 6, children: [
                  for (var i = 0; i < 7; i++)
                    FilterChip(
                      label: Text(days[i]),
                      selected: _off.contains(i + 1),
                      onSelected: (v) => setState(() => v ? _off.add(i + 1) : _off.remove(i + 1)),
                    ),
                ]),
                const SizedBox(height: 12),
                hrPair(context, HrField(_lateAfter, 'Late after (HH:mm)', icon: Icons.schedule),
                    HrField(_latesPerDay, 'Lates that cost one day\'s pay (0 = none)', icon: Icons.timer_off_outlined, number: true)),
              ]),
            ),
            const CrmSectionTitle('Leave types (days a year)'),
            CrmCard(
              child: Column(children: [
                for (var i = 0; i < _leave.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(children: [
                      Expanded(flex: 3, child: HrField(_leave[i].$1, 'Type')),
                      const SizedBox(width: 8),
                      Expanded(flex: 2, child: HrField(_leave[i].$2, 'Days', number: true)),
                      const SizedBox(width: 6),
                      FilterChip(
                        label: Text(_leave[i].$3 ? 'Paid' : 'Unpaid'),
                        selected: _leave[i].$3,
                        onSelected: (v) => setState(() => _leave[i] = (_leave[i].$1, _leave[i].$2, v)),
                      ),
                      IconButton(
                          icon: const Icon(Icons.close, color: CrmTokens.muted),
                          onPressed: () => setState(() => _leave.removeAt(i))),
                    ]),
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => setState(() => _leave.add((TextEditingController(), TextEditingController(), true))),
                    icon: const Icon(Icons.add, color: CrmTokens.navy),
                    label: Text('Add leave type', style: CrmTokens.body(color: CrmTokens.navy, w: FontWeight.w600)),
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _encash,
                  onChanged: (v) => setState(() => _encash = v),
                  title: Text('Pay unused annual leave in final settlement', style: CrmTokens.body()),
                ),
              ]),
            ),
            const CrmSectionTitle('EOBI and social security'),
            CrmCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                HrField(_minWage, 'Minimum wage (Rs. a month)', icon: Icons.gavel_outlined, number: true),
                const SizedBox(height: 12),
                hrPair(context, HrField(_eobiEmp, 'EOBI employee %', number: true),
                    HrField(_eobiEr, 'EOBI employer %', number: true)),
                const SizedBox(height: 12),
                hrPair(context, HrField(_ssPct, 'Social security employer %', number: true),
                    HrField(_ssCeiling, 'Social security wage ceiling (Rs., empty = none)', number: true)),
                const SizedBox(height: 6),
                Text(
                  'EOBI is worked out on the minimum wage, not the salary. Minimum wage differs by province and changes '
                  'every budget: check the latest notification.',
                  style: CrmTokens.body(size: 11.5, color: CrmTokens.muted),
                ),
              ]),
            ),
            const CrmSectionTitle('Income tax on salary (yearly slabs)'),
            CrmCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Yearly income above → fixed tax + % of the amount above it',
                    style: CrmTokens.body(size: 12, color: CrmTokens.muted)),
                const SizedBox(height: 8),
                for (var i = 0; i < _slabs.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(children: [
                      Expanded(child: HrField(_slabs[i].$1, 'Above (Rs.)', number: true)),
                      const SizedBox(width: 6),
                      Expanded(child: HrField(_slabs[i].$2, 'Fixed (Rs.)', number: true)),
                      const SizedBox(width: 6),
                      SizedBox(width: 90, child: HrField(_slabs[i].$3, '%', number: true)),
                      IconButton(
                          icon: const Icon(Icons.close, color: CrmTokens.muted),
                          onPressed: () => setState(() => _slabs.removeAt(i))),
                    ]),
                  ),
                Row(children: [
                  TextButton.icon(
                    onPressed: () => setState(() => _slabs.add((TextEditingController(), TextEditingController(), TextEditingController()))),
                    icon: const Icon(Icons.add, color: CrmTokens.navy),
                    label: Text('Add slab', style: CrmTokens.body(color: CrmTokens.navy, w: FontWeight.w600)),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => setState(() {
                      _slabs
                        ..clear()
                        ..addAll([
                          for (final t in defaultTaxSlabs)
                            (
                              TextEditingController(text: hrPlain(t.from)),
                              TextEditingController(text: hrPlain(t.fixed)),
                              TextEditingController(text: hrPlain(t.rate)),
                            ),
                        ]);
                    }),
                    child: Text('Reset to FY 2026-27', style: CrmTokens.body(color: CrmTokens.muted)),
                  ),
                ]),
                Text('Income up to the first slab is tax free. Slabs change every budget: check FBR before July payroll.',
                    style: CrmTokens.body(size: 11.5, color: CrmTokens.muted)),
              ]),
            ),
            const SizedBox(height: 18),
            SizedBox(
              height: 48,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: CrmTokens.amber, elevation: 0),
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.check, color: CrmTokens.navyDark),
                label: Text('Save settings', style: CrmTokens.body(size: 14, color: CrmTokens.navyDark, w: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
