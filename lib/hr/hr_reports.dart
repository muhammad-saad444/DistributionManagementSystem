// HR reports: booker scorecards, headcount and salary cost, the month's attendance, leave balances.
import 'package:flutter/material.dart';

import '../crm/crm_ui.dart';
import 'hr_data.dart';
import 'hr_ui.dart';

class HrReportsTab extends StatefulWidget {
  const HrReportsTab({super.key});

  @override
  State<HrReportsTab> createState() => _HrReportsTabState();
}

enum _Report { scorecards, headcount, attendance, leave }

class _HrReportsTabState extends State<HrReportsTab> {
  _Report _report = _Report.scorecards;
  String _month = monthKey(DateTime.now());
  List<Employee>? _staff;
  HrSettings _settings = const HrSettings();
  Map<String, BookerMonth> _sales = const {};
  Map<String, Map<String, Attendance>> _att = const {};
  List<PayrollRun> _runs = const [];
  List<LeaveRequest> _leave = const [];
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _error = null;
      _staff = null;
    });
    try {
      final r = await Future.wait<Object>([
        loadEmployees(),
        loadHrSettings(),
        loadBookerMonth(_month),
        loadMonthAttendance(_month),
        loadPayrollRuns(),
        loadLeaveRequests(),
      ]);
      if (!mounted) return;
      setState(() {
        _staff = r[0] as List<Employee>;
        _settings = r[1] as HrSettings;
        _sales = r[2] as Map<String, BookerMonth>;
        _att = r[3] as Map<String, Map<String, Attendance>>;
        _runs = r[4] as List<PayrollRun>;
        _leave = r[5] as List<LeaveRequest>;
      });
    } catch (e) {
      debugPrint('HR reports: $e');
      if (mounted) setState(() => _error = e);
    }
  }

  List<Employee> get _inMonth {
    final start = monthStart(_month);
    final end = DateTime(start.year, start.month + 1, 0);
    return (_staff ?? const <Employee>[]).where((e) {
      if (e.joinDate != null && e.joinDate!.isAfter(end)) return false;
      if (!e.isActive && (e.leftDate == null || e.leftDate!.isBefore(start))) return false;
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 40),
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<_Report>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: _Report.scorecards, label: Text('Booker scorecards'), icon: Icon(Icons.leaderboard_outlined)),
              ButtonSegment(value: _Report.headcount, label: Text('Headcount & cost'), icon: Icon(Icons.groups_outlined)),
              ButtonSegment(value: _Report.attendance, label: Text('Attendance'), icon: Icon(Icons.fact_check_outlined)),
              ButtonSegment(value: _Report.leave, label: Text('Leave balances'), icon: Icon(Icons.beach_access_outlined)),
            ],
            selected: {_report},
            onSelectionChanged: (v) => setState(() => _report = v.first),
          ),
        ),
        const SizedBox(height: 12),
        if (_report == _Report.scorecards || _report == _Report.attendance) ...[
          HrMonthBar(_month, (m) {
            setState(() => _month = m);
            _load();
          }),
          const SizedBox(height: 12),
        ],
        if (_staff == null)
          SizedBox(height: 220, child: hrLoading(_error, _load, what: 'reports'))
        else
          ...switch (_report) {
            _Report.scorecards => _scorecards(),
            _Report.headcount => _headcount(),
            _Report.attendance => _attendance(),
            _Report.leave => _leaveBalances(),
          },
      ],
    );
  }

  // ------------------------------------------------------------------ scorecards

  List<Widget> _scorecards() {
    final bookers = _inMonth.where((e) => e.hasApp).toList();
    if (bookers.isEmpty) {
      return const [
        CrmEmpty(
            icon: Icons.leaderboard_outlined,
            text: 'Link bookers\' app logins to their staff records (Staff → edit) to see their scorecards.'),
      ];
    }
    final rows = [
      for (final e in bookers)
        (e, _sales[e.userUid] ?? BookerMonth(), summarise(e, _month, _att[e.id] ?? const {}, _settings)),
    ]..sort((a, b) => b.$2.sales.compareTo(a.$2.sales));
    final total = rows.fold<num>(0, (s, r) => s + r.$2.sales);
    return [
      Row(children: [
        Expanded(child: CrmStat(label: 'Bookers', value: '${rows.length}')),
        const SizedBox(width: 8),
        Expanded(child: CrmStat(label: 'Their sales', value: crmRs(total))),
      ]),
      const SizedBox(height: 10),
      for (var i = 0; i < rows.length; i++) _scoreCard(i + 1, rows[i].$1, rows[i].$2, rows[i].$3),
    ];
  }

  Widget _scoreCard(int rank, Employee e, BookerMonth m, AttendanceSummary a) {
    final pct = e.monthlyTarget > 0 ? (m.sales / e.monthlyTarget * 100) : null;
    final attendancePct = a.workingDays == 0 ? 100 : ((a.daysAtWork + a.unmarked + a.paidLeave) / a.workingDays * 100);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: CrmCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(
              radius: 14,
              backgroundColor: rank == 1 ? CrmTokens.amberBg : CrmTokens.bg,
              child: Text('$rank', style: CrmTokens.body(size: 12, w: FontWeight.w700, color: CrmTokens.navy)),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(e.name, style: CrmTokens.display(size: 15))),
            Text(crmRs(m.sales), style: CrmTokens.body(size: 14, w: FontWeight.w700)),
          ]),
          if (pct != null) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: (pct / 100).clamp(0, 1).toDouble(),
                minHeight: 8,
                backgroundColor: CrmTokens.bg,
                color: pct >= 100 ? CrmTokens.green : (pct >= 70 ? CrmTokens.amber : CrmTokens.red),
              ),
            ),
            const SizedBox(height: 3),
            Text('${pct.toStringAsFixed(0)}% of ${crmRs(e.monthlyTarget)} target',
                style: CrmTokens.body(size: 11.5, color: CrmTokens.muted)),
          ],
          const SizedBox(height: 8),
          Wrap(spacing: 14, runSpacing: 4, children: [
            _metric('Invoices', '${m.invoices}'),
            if (m.visits > 0 || m.shopsVisited > 0) _metric('Shops visited', '${m.shopsVisited}'),
            if (m.recoveries > 0) _metric('Recovered', crmRs(m.recoveries)),
            _metric('Attendance', '${attendancePct.toStringAsFixed(0)}%'),
            _metric('Late', hrPlain(a.late)),
            _metric('Absent', hrPlain(a.absent)),
          ]),
        ]),
      ),
    );
  }

  Widget _metric(String label, String value) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: CrmTokens.body(size: 11, color: CrmTokens.muted)),
        Text(value, style: CrmTokens.body(w: FontWeight.w700)),
      ]);

  // ------------------------------------------------------------------ headcount & cost

  List<Widget> _headcount() {
    final staff = _staff!;
    final active = staff.where((e) => e.isActive).toList();
    final year = DateTime.now().year;
    final joined = staff.where((e) => e.joinDate?.year == year).length;
    final left = staff.where((e) => !e.isActive && e.leftDate?.year == year).length;
    Map<String, int> count(String Function(Employee) key) {
      final m = <String, int>{};
      for (final e in active) {
        final k = key(e).isEmpty ? 'Not set' : key(e);
        m[k] = (m[k] ?? 0) + 1;
      }
      return Map.fromEntries(m.entries.toList()..sort((a, b) => b.value.compareTo(a.value)));
    }

    final runs = _runs.where((r) => !r.isDraft).take(12).toList();
    final maxCost = runs.fold<num>(0, (m, r) => r.totalEmployerCost > m ? r.totalEmployerCost : m);
    return [
      Row(children: [
        Expanded(child: CrmStat(label: 'Active', value: '${active.length}')),
        const SizedBox(width: 8),
        Expanded(child: CrmStat(label: 'Joined in $year', value: '$joined')),
        const SizedBox(width: 8),
        Expanded(child: CrmStat(label: 'Left in $year', value: '$left')),
      ]),
      const CrmSectionTitle('By designation'),
      CrmCard(child: Column(children: [for (final e in count((e) => e.designation).entries) HrInfoRow(e.key, '${e.value}')])),
      const CrmSectionTitle('By department'),
      CrmCard(child: Column(children: [for (final e in count((e) => e.department).entries) HrInfoRow(e.key, '${e.value}')])),
      const CrmSectionTitle('Salary cost by month'),
      if (runs.isEmpty)
        Text('Finalised salary sheets show here.', style: CrmTokens.body(color: CrmTokens.muted))
      else
        CrmCard(
          child: Column(children: [
            for (final r in runs)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(children: [
                  SizedBox(width: 90, child: Text(hrMonthLabel.format(monthStart(r.month)), style: CrmTokens.body(size: 12))),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: maxCost == 0 ? 0 : (r.totalEmployerCost / maxCost).toDouble(),
                        minHeight: 12,
                        backgroundColor: CrmTokens.bg,
                        color: CrmTokens.navy,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 190,
                    child: Text('net ${crmRs(r.totalNet)}  ·  cost ${crmRs(r.totalEmployerCost)}',
                        textAlign: TextAlign.right, style: CrmTokens.body(size: 12, w: FontWeight.w600)),
                  ),
                ]),
              ),
          ]),
        ),
    ];
  }

  // ------------------------------------------------------------------ attendance

  List<Widget> _attendance() {
    final staff = _inMonth;
    if (staff.isEmpty) return const [CrmEmpty(icon: Icons.badge_outlined, text: 'No staff this month.')];
    return [
      CrmCard(
        padding: const EdgeInsets.all(8),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingTextStyle: CrmTokens.body(w: FontWeight.w700, size: 12),
            dataTextStyle: CrmTokens.body(size: 12.5),
            columnSpacing: 22,
            columns: const [
              DataColumn(label: Text('Name')),
              DataColumn(label: Text('Working days'), numeric: true),
              DataColumn(label: Text('Present'), numeric: true),
              DataColumn(label: Text('Late'), numeric: true),
              DataColumn(label: Text('Half'), numeric: true),
              DataColumn(label: Text('Absent'), numeric: true),
              DataColumn(label: Text('Paid leave'), numeric: true),
              DataColumn(label: Text('Unpaid leave'), numeric: true),
              DataColumn(label: Text('Not marked'), numeric: true),
            ],
            rows: [
              for (final e in staff)
                () {
                  final s = summarise(e, _month, _att[e.id] ?? const {}, _settings);
                  DataCell n(num v, [Color? c]) =>
                      DataCell(Text(hrPlain(v), style: CrmTokens.body(size: 12.5, color: v > 0 ? c : null)));
                  return DataRow(cells: [
                    DataCell(Text(e.name)),
                    n(s.workingDays),
                    n(s.present),
                    n(s.late, CrmTokens.amber),
                    n(s.half),
                    n(s.absent, CrmTokens.red),
                    n(s.paidLeave),
                    n(s.unpaidLeave, CrmTokens.red),
                    n(s.unmarked, CrmTokens.muted),
                  ]);
                }(),
            ],
          ),
        ),
      ),
    ];
  }

  // ------------------------------------------------------------------ leave balances

  List<Widget> _leaveBalances() {
    final year = DateTime.now().year;
    final staff = _staff!.where((e) => e.isActive).toList();
    final types = _settings.leaveTypes.where((t) => t.daysPerYear > 0).toList();
    if (staff.isEmpty) return const [CrmEmpty(icon: Icons.badge_outlined, text: 'No active staff.')];
    return [
      Text('Days left in $year (used / allowed)', style: CrmTokens.body(color: CrmTokens.muted)),
      const SizedBox(height: 8),
      CrmCard(
        padding: const EdgeInsets.all(8),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingTextStyle: CrmTokens.body(w: FontWeight.w700, size: 12),
            dataTextStyle: CrmTokens.body(size: 12.5),
            columnSpacing: 26,
            columns: [
              const DataColumn(label: Text('Name')),
              for (final t in types) DataColumn(label: Text(t.name), numeric: true),
            ],
            rows: [
              for (final e in staff)
                () {
                  final used = leaveUsed(_leave, e.id, year);
                  return DataRow(cells: [
                    DataCell(Text(e.name)),
                    for (final t in types)
                      DataCell(Text(
                        '${hrPlain(t.daysPerYear - (used[t.name] ?? 0))}  (${hrPlain(used[t.name] ?? 0)}/${hrPlain(t.daysPerYear)})',
                        style: CrmTokens.body(
                            size: 12.5, color: t.daysPerYear - (used[t.name] ?? 0) < 0 ? CrmTokens.red : null),
                      )),
                  ]);
                }(),
            ],
          ),
        ),
      ),
    ];
  }
}
