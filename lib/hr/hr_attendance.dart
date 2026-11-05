// Attendance (a day's register and the month sheet) and leave requests, for admins.
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../crm/crm_ui.dart';
import 'hr_data.dart';
import 'hr_ui.dart';

class AttendanceTab extends StatefulWidget {
  const AttendanceTab({super.key});

  @override
  State<AttendanceTab> createState() => _AttendanceTabState();
}

class _AttendanceTabState extends State<AttendanceTab> {
  bool _sheet = false; // false: one day; true: month sheet
  DateTime _day = dateOnly(DateTime.now());
  String _month = monthKey(DateTime.now());
  List<Employee>? _staff;
  HrSettings _settings = const HrSettings();
  Map<String, Map<String, Attendance>> _att = const {};
  Object? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String get _loadedMonth => _sheet ? _month : monthKey(_day);

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final r = await Future.wait<Object>([loadEmployees(), loadHrSettings(), loadMonthAttendance(_loadedMonth)]);
      if (!mounted) return;
      setState(() {
        _staff = (r[0] as List<Employee>);
        _settings = r[1] as HrSettings;
        _att = r[2] as Map<String, Map<String, Attendance>>;
      });
    } catch (e) {
      debugPrint('HR attendance: $e');
      if (mounted) setState(() => _error = e);
    }
  }

  /// People employed on [d].
  List<Employee> _onRoll(DateTime d) => (_staff ?? const <Employee>[]).where((e) {
        if (e.joinDate != null && d.isBefore(dateOnly(e.joinDate!))) return false;
        if (e.leftDate != null && d.isAfter(dateOnly(e.leftDate!))) return false;
        return e.isActive || e.leftDate != null;
      }).toList();

  Future<void> _set(Employee e, String date, String? status) async {
    setState(() => _busy = true);
    try {
      await markAttendance(e, date, status);
      await _load();
    } catch (_) {
      if (mounted) crmSnack(context, "Couldn't save. Check your connection.", error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _allPresent() async {
    final date = dayKey(_day);
    final day = {for (final e in _att.entries) if (e.value[date] != null) e.key: e.value[date]!};
    setState(() => _busy = true);
    try {
      final n = await markAllPresent(_onRoll(_day), date, day);
      if (mounted) crmSnack(context, n == 0 ? 'Everyone is already marked' : 'Marked $n present');
      await _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_staff == null) return hrLoading(_error, _load, what: 'attendance');
    return Column(children: [
      if (_busy) const LinearProgressIndicator(minHeight: 2, color: CrmTokens.amber),
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
        child: SizedBox(
          width: double.infinity,
          child: SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: false, label: Text('Day register'), icon: Icon(Icons.today)),
              ButtonSegment(value: true, label: Text('Month sheet'), icon: Icon(Icons.grid_on)),
            ],
            selected: {_sheet},
            onSelectionChanged: (v) {
              setState(() => _sheet = v.first);
              _load();
            },
          ),
        ),
      ),
      Expanded(child: _sheet ? _monthSheet() : _dayRegister()),
    ]);
  }

  Widget _dayRegister() {
    final date = dayKey(_day);
    final staff = _onRoll(_day);
    final off = _settings.weeklyOff.contains(_day.weekday);
    final marked = staff.where((e) => _att[e.id]?[date] != null).length;
    return RefreshIndicator(
      color: CrmTokens.navy,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 40),
        children: [
          Row(children: [
            Expanded(
              child: HrDateField('Date', _day, (d) {
                if (d == null) return;
                setState(() => _day = d);
                _load();
              }, clearable: false, last: DateTime.now()),
            ),
            const SizedBox(width: 10),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: CrmTokens.navy, elevation: 0),
              onPressed: _busy || staff.isEmpty ? null : _allPresent,
              icon: const Icon(Icons.done_all, color: Colors.white, size: 18),
              label: Text('Mark rest present', style: CrmTokens.body(color: Colors.white, w: FontWeight.w600)),
            ),
          ]),
          const SizedBox(height: 8),
          Text(
            off
                ? 'This is a weekly off day.'
                : '$marked of ${staff.length} marked. Bookers with the app check in themselves; unmarked working days '
                    'count as present on the salary sheet.',
            style: CrmTokens.body(size: 12, color: CrmTokens.muted),
          ),
          const SizedBox(height: 10),
          if (staff.isEmpty) const CrmEmpty(icon: Icons.badge_outlined, text: 'Add staff first, in the Staff tab.'),
          for (final e in staff) _dayRow(e, date, _att[e.id]?[date]),
        ],
      ),
    );
  }

  Widget _dayRow(Employee e, String date, Attendance? a) {
    String loc(num? lat, num? lng) => lat == null || lng == null ? '' : ' (${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)})';
    final times = [
      if (a?.checkIn != null) 'In ${hrTime.format(a!.checkIn!)}${loc(a.inLat, a.inLng)}',
      if (a?.checkOut != null) 'Out ${hrTime.format(a!.checkOut!)}${loc(a.outLat, a.outLng)}',
      if (a?.status == 'leave' && a!.leaveType.isNotEmpty) '${a.leaveType} leave${a.paidLeave ? '' : ' (unpaid)'}',
    ].join('  ·  ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: CrmCard(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text('${e.name}  ·  ${e.designation}', style: CrmTokens.body(w: FontWeight.w600)),
            ),
            if (a?.markedBy == 'self') const CrmPill('Self', icon: Icons.phone_android, color: CrmTokens.blue, background: CrmTokens.blueBg),
          ]),
          if (times.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(times, style: CrmTokens.body(size: 11.5, color: CrmTokens.muted)),
            ),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final s in ['present', 'late', 'half', 'absent', 'off'])
              ChoiceChip(
                label: Text(attendanceLabel(s)),
                labelStyle: CrmTokens.body(
                    size: 12, color: a?.status == s ? Colors.white : attendanceColor(s), w: FontWeight.w600),
                selected: a?.status == s,
                selectedColor: attendanceColor(s),
                backgroundColor: attendanceBg(s),
                showCheckmark: false,
                onSelected: _busy ? null : (on) => _set(e, date, on ? s : null),
              ),
          ]),
        ]),
      ),
    );
  }

  Widget _monthSheet() {
    final start = monthStart(_month);
    final days = DateTime(start.year, start.month + 1, 0).day;
    final staff = _onRoll(DateTime(start.year, start.month + 1, 0))
        .where((e) => e.leftDate == null || !e.leftDate!.isBefore(start))
        .toList();
    const cell = 30.0;
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 40),
      children: [
        HrMonthBar(_month, (m) {
          setState(() => _month = m);
          _load();
        }),
        const SizedBox(height: 8),
        Wrap(spacing: 10, runSpacing: 4, children: [
          for (final s in attendanceStatuses)
            Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 22,
                height: 18,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: attendanceBg(s), borderRadius: BorderRadius.circular(4)),
                child: Text(attendanceLetter(s),
                    style: CrmTokens.body(size: 10, w: FontWeight.w700, color: attendanceColor(s))),
              ),
              const SizedBox(width: 4),
              Text(attendanceLabel(s), style: CrmTokens.body(size: 11.5, color: CrmTokens.muted)),
            ]),
          Text('·  blank = not marked (counts as present)', style: CrmTokens.body(size: 11.5, color: CrmTokens.muted)),
        ]),
        const SizedBox(height: 10),
        if (staff.isEmpty)
          const CrmEmpty(icon: Icons.badge_outlined, text: 'No staff in this month.')
        else
          CrmCard(
            padding: const EdgeInsets.all(8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const SizedBox(width: 150),
                  for (var d = 1; d <= days; d++)
                    SizedBox(
                      width: cell,
                      child: Text('$d',
                          textAlign: TextAlign.center,
                          style: CrmTokens.body(
                              size: 11,
                              w: FontWeight.w600,
                              color: _settings.weeklyOff.contains(DateTime(start.year, start.month, d).weekday)
                                  ? CrmTokens.red
                                  : CrmTokens.muted)),
                    ),
                  const SizedBox(width: 8),
                  SizedBox(width: 70, child: Text('P / A / LV', style: CrmTokens.body(size: 11, color: CrmTokens.muted))),
                ]),
                const Divider(height: 10),
                for (final e in staff) _sheetRow(e, start, days, cell),
              ]),
            ),
          ),
        const SizedBox(height: 8),
        Text('Tap a box to change that day.', style: CrmTokens.body(size: 12, color: CrmTokens.muted)),
      ],
    );
  }

  Widget _sheetRow(Employee e, DateTime start, int days, double cell) {
    final mine = _att[e.id] ?? const {};
    final sum = summarise(e, _month, mine, _settings);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        SizedBox(
          width: 150,
          child: Text(e.name, style: CrmTokens.body(size: 12.5, w: FontWeight.w600), overflow: TextOverflow.ellipsis),
        ),
        for (var d = 1; d <= days; d++) _sheetCell(e, DateTime(start.year, start.month, d), mine, cell),
        const SizedBox(width: 8),
        SizedBox(
          width: 70,
          child: Text(
              '${hrPlain(sum.daysAtWork + sum.unmarked)} / ${hrPlain(sum.absent)} / ${hrPlain(sum.paidLeave + sum.unpaidLeave)}',
              style: CrmTokens.body(size: 11.5, w: FontWeight.w600)),
        ),
      ]),
    );
  }

  Widget _sheetCell(Employee e, DateTime d, Map<String, Attendance> mine, double cell) {
    final a = mine[dayKey(d)];
    final employed =
        !(e.joinDate != null && d.isBefore(dateOnly(e.joinDate!))) && !(e.leftDate != null && d.isAfter(dateOnly(e.leftDate!)));
    final future = d.isAfter(DateTime.now());
    final off = _settings.weeklyOff.contains(d.weekday);
    return SizedBox(
      width: cell,
      height: 26,
      child: Padding(
        padding: const EdgeInsets.all(1.5),
        child: InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: !employed || future || _busy ? null : () => _pick(e, d, a),
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: !employed ? Colors.transparent : (a == null ? (off ? CrmTokens.bg : Colors.white) : attendanceBg(a.status)),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: employed ? CrmTokens.border : Colors.transparent),
            ),
            child: Text(a == null ? '' : attendanceLetter(a.status),
                style: CrmTokens.body(size: 10, w: FontWeight.w700, color: a == null ? CrmTokens.muted : attendanceColor(a.status))),
          ),
        ),
      ),
    );
  }

  Future<void> _pick(Employee e, DateTime d, Attendance? a) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (s) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(title: Text('${e.name}  ·  ${crmDay.format(d)}', style: CrmTokens.display(size: 15))),
          for (final st in ['present', 'late', 'half', 'absent', 'off'])
            ListTile(
              leading: CircleAvatar(
                radius: 14,
                backgroundColor: attendanceBg(st),
                child: Text(attendanceLetter(st), style: CrmTokens.body(size: 11, w: FontWeight.w700, color: attendanceColor(st))),
              ),
              title: Text(attendanceLabel(st), style: CrmTokens.body()),
              selected: a?.status == st,
              onTap: () => Navigator.pop(s, st),
            ),
          ListTile(
            leading: const Icon(Icons.clear),
            title: Text('Clear (not marked)', style: CrmTokens.body()),
            onTap: () => Navigator.pop(s, ''),
          ),
          if (a?.status == 'leave')
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text('This day is approved leave. Change it from the Leave tab.',
                  style: CrmTokens.body(size: 12, color: CrmTokens.muted)),
            ),
        ]),
      ),
    );
    if (choice == null) return;
    await _set(e, dayKey(d), choice.isEmpty ? null : choice);
  }
}

// -----------------------------------------------------------------------------
// Leave
// -----------------------------------------------------------------------------

class LeaveTab extends StatefulWidget {
  const LeaveTab({super.key});

  @override
  State<LeaveTab> createState() => _LeaveTabState();
}

class _LeaveTabState extends State<LeaveTab> {
  List<LeaveRequest>? _requests;
  List<Employee> _staff = const [];
  HrSettings _settings = const HrSettings();
  Object? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final r = await Future.wait<Object>([loadLeaveRequests(), loadEmployees(), loadHrSettings()]);
      if (!mounted) return;
      setState(() {
        _requests = r[0] as List<LeaveRequest>;
        _staff = r[1] as List<Employee>;
        _settings = r[2] as HrSettings;
      });
    } catch (e) {
      debugPrint('HR leave: $e');
      if (mounted) setState(() => _error = e);
    }
  }

  Employee? _emp(String id) => _staff.where((e) => e.id == id).firstOrNull;

  Future<void> _decide(LeaveRequest r, bool approve) async {
    final e = _emp(r.employeeId);
    if (e == null) return crmSnack(context, 'This person is no longer in Staff.', error: true);
    if (approve) {
      final type = _settings.leaveType(r.type);
      final used = leaveUsed(_requests!, e.id, r.from.year)[r.type] ?? 0;
      if (type != null && type.daysPerYear > 0 && used + r.days > type.daysPerYear) {
        if (!await hrConfirm(
            context,
            'More than their ${r.type} leave',
            '${e.name} has used ${hrPlain(used)} of ${hrPlain(type.daysPerYear)} ${r.type} days this year. '
                'This request is ${hrPlain(r.days)} days. Approve anyway?',
            'Approve')) {
          return;
        }
      }
    }
    setState(() => _busy = true);
    try {
      await decideLeave(r, e, approve: approve, settings: _settings);
      if (mounted) crmSnack(context, approve ? 'Approved. The days are marked as leave.' : 'Rejected');
      await _load();
    } catch (_) {
      if (mounted) crmSnack(context, "Couldn't save. Check your connection.", error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel(LeaveRequest r) async {
    final e = _emp(r.employeeId);
    if (e == null) return;
    if (!await hrConfirm(context, 'Cancel this leave?', 'Its days are cleared from attendance.', 'Cancel leave',
        danger: true)) {
      return;
    }
    setState(() => _busy = true);
    try {
      await cancelApprovedLeave(r, e, _settings);
      await _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addForSomeone() async {
    final active = _staff.where((e) => e.isActive).toList();
    if (active.isEmpty) return crmSnack(context, 'Add staff first.', error: true);
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => LeaveApplyDialog(settings: _settings, staff: active),
    );
    if (saved == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final all = _requests;
    if (all == null) return hrLoading(_error, _load, what: 'leave');
    final pending = all.where((r) => r.status == 'pending').toList();
    final rest = all.where((r) => r.status != 'pending').toList();
    return Scaffold(
      backgroundColor: CrmTokens.bg,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: CrmTokens.amber,
        foregroundColor: CrmTokens.navyDark,
        onPressed: _addForSomeone,
        icon: const Icon(Icons.event_busy),
        label: Text('Record leave', style: CrmTokens.body(color: CrmTokens.navyDark, w: FontWeight.w700)),
      ),
      body: RefreshIndicator(
        color: CrmTokens.navy,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 6, 14, 96),
          children: [
            if (_busy) const LinearProgressIndicator(minHeight: 2, color: CrmTokens.amber),
            CrmSectionTitle('Waiting for approval',
                trailing: Text('${pending.length}', style: CrmTokens.body(color: CrmTokens.muted))),
            if (pending.isEmpty) Text('Nothing waiting.', style: CrmTokens.body(color: CrmTokens.muted)),
            for (final r in pending) _card(r, actions: true),
            const CrmSectionTitle('Decided'),
            if (rest.isEmpty) Text('No leave yet.', style: CrmTokens.body(color: CrmTokens.muted)),
            for (final r in rest.take(60)) _card(r),
          ],
        ),
      ),
    );
  }

  Widget _card(LeaveRequest r, {bool actions = false}) {
    final (label, color, bg) = switch (r.status) {
      'approved' => ('Approved', CrmTokens.green, CrmTokens.greenBg),
      'rejected' => ('Rejected', CrmTokens.red, CrmTokens.redBg),
      'cancelled' => ('Cancelled', CrmTokens.muted, CrmTokens.bg),
      _ => ('Pending', CrmTokens.amber, CrmTokens.amberBg),
    };
    final range = r.from == r.to ? crmDay.format(r.from) : '${crmDay.format(r.from)} – ${crmDay.format(r.to)}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: CrmCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(r.employeeName, style: CrmTokens.display(size: 15))),
            CrmPill(label, color: color, background: bg),
          ]),
          const SizedBox(height: 3),
          Text('${r.type} leave  ·  $range  ·  ${hrPlain(r.days)} working day${r.days == 1 ? '' : 's'}',
              style: CrmTokens.body(size: 12.5)),
          if (r.reason.isNotEmpty)
            Text(r.reason, style: CrmTokens.body(size: 12, color: CrmTokens.muted)),
          if (actions)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                TextButton(
                  onPressed: _busy ? null : () => _decide(r, false),
                  child: Text('Reject', style: CrmTokens.body(color: CrmTokens.red, w: FontWeight.w600)),
                ),
                const SizedBox(width: 6),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: CrmTokens.green, elevation: 0),
                  onPressed: _busy ? null : () => _decide(r, true),
                  child: Text('Approve', style: CrmTokens.body(color: Colors.white, w: FontWeight.w600)),
                ),
              ]),
            )
          else if (r.status == 'approved')
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _busy ? null : () => _cancel(r),
                child: Text('Cancel leave', style: CrmTokens.body(color: CrmTokens.muted)),
              ),
            ),
        ]),
      ),
    );
  }
}

/// Applying for leave: a booker for themselves ([staff] null, [self] given), or an admin
/// recording it for someone (approved straight away).
class LeaveApplyDialog extends StatefulWidget {
  final HrSettings settings;
  final List<Employee>? staff;
  final ({String employeeId, String name})? self;
  const LeaveApplyDialog({super.key, required this.settings, this.staff, this.self});

  @override
  State<LeaveApplyDialog> createState() => _LeaveApplyDialogState();
}

class _LeaveApplyDialogState extends State<LeaveApplyDialog> {
  String? _employeeId;
  late String _type = widget.settings.leaveTypes.first.name;
  DateTime _from = DateTime.now();
  DateTime _to = DateTime.now();
  final _reason = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_to.isBefore(_from)) return crmSnack(context, '"To" is before "From"', error: true);
    final days = leaveDays(_from, _to, widget.settings).length;
    if (days == 0) return crmSnack(context, 'Those dates are all weekly off days', error: true);
    final self = widget.self;
    final e = widget.staff?.where((x) => x.id == _employeeId).firstOrNull;
    if (self == null && e == null) return crmSnack(context, 'Choose who is on leave', error: true);
    setState(() => _saving = true);
    try {
      await applyLeave(
        employeeId: self?.employeeId ?? e!.id,
        employeeName: self?.name ?? e!.name,
        userUid: self != null ? FirebaseAuth.instance.currentUser!.uid : e!.userUid,
        type: _type,
        from: _from,
        to: _to,
        reason: _reason.text.trim(),
        settings: widget.settings,
        approveFor: e,
      );
      if (!mounted) return;
      crmSnack(context, self != null ? 'Leave request sent' : 'Leave recorded');
      Navigator.pop(context, true);
    } catch (err) {
      debugPrint('Leave failed: $err');
      if (!mounted) return;
      setState(() => _saving = false);
      crmSnack(context, "Couldn't save. Check your connection.", error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final days = _to.isBefore(_from) ? 0 : leaveDays(_from, _to, widget.settings).length;
    return AlertDialog(
      title: Text(widget.self != null ? 'Apply for leave' : 'Record leave', style: CrmTokens.display(size: 17)),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (widget.staff != null) ...[
              DropdownButtonFormField<String>(
                initialValue: _employeeId,
                isExpanded: true,
                decoration: crmInput('Staff member', icon: Icons.person_outline),
                items: [
                  for (final e in widget.staff!)
                    DropdownMenuItem(value: e.id, child: Text('${e.name}  ·  ${e.designation}', style: CrmTokens.body())),
                ],
                onChanged: (v) => setState(() => _employeeId = v),
              ),
              const SizedBox(height: 10),
            ],
            DropdownButtonFormField<String>(
              initialValue: _type,
              isExpanded: true,
              decoration: crmInput('Leave type', icon: Icons.category_outlined),
              items: [
                for (final t in widget.settings.leaveTypes)
                  DropdownMenuItem(
                      value: t.name,
                      child: Text('${t.name}${t.paid ? '' : ' (unpaid)'}', style: CrmTokens.body())),
              ],
              onChanged: (v) => setState(() => _type = v ?? _type),
            ),
            const SizedBox(height: 10),
            HrDateField('From', _from, (d) => setState(() {
                  _from = d ?? _from;
                  if (_to.isBefore(_from)) _to = _from;
                }), clearable: false, first: DateTime(DateTime.now().year - 1)),
            const SizedBox(height: 10),
            HrDateField('To', _to, (d) => setState(() => _to = d ?? _to), clearable: false, first: _from),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('$days working day${days == 1 ? '' : 's'}', style: CrmTokens.body(size: 12, color: CrmTokens.muted)),
            ),
            const SizedBox(height: 10),
            HrField(_reason, 'Reason', lines: 2),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Cancel', style: CrmTokens.body())),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: CrmTokens.navy, elevation: 0),
          onPressed: _saving ? null : _save,
          child: Text(widget.self != null ? 'Send request' : 'Save (approved)',
              style: CrmTokens.body(color: Colors.white, w: FontWeight.w600)),
        ),
      ],
    );
  }
}
