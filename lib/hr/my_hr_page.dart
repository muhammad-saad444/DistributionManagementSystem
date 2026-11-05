// The booker's own HR: check in / out (with location), this month's attendance, leave, payslips.
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../crm/crm_ui.dart';
import '../print_preview.dart';
import 'hr_attendance.dart';
import 'hr_data.dart';
import 'hr_pdf.dart';
import 'hr_ui.dart';

/// Where the phone is, or null if location is off, refused or slow. Check-in still works without.
Future<Position?> _whereAmI() async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
    if (p == LocationPermission.denied || p == LocationPermission.deniedForever) return null;
    return await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)),
    );
  } catch (e) {
    debugPrint('Location: $e');
    return null;
  }
}

/// The check-in card on the booker's dashboard. Shows nothing if HR hasn't linked this login.
class HrCheckInCard extends StatefulWidget {
  const HrCheckInCard({super.key});

  @override
  State<HrCheckInCard> createState() => _HrCheckInCardState();
}

class _HrCheckInCardState extends State<HrCheckInCard> {
  ({String employeeId, String name})? _link;
  Attendance? _today;
  HrSettings _settings = const HrSettings();
  bool _loaded = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final link = await myEmployeeLink();
      Attendance? today;
      HrSettings settings = const HrSettings();
      if (link != null) {
        final r = await Future.wait<Object?>([loadMyDay(link.employeeId, DateTime.now()), loadHrSettings()]);
        today = r[0] as Attendance?;
        settings = r[1] as HrSettings;
      }
      if (mounted) {
        setState(() {
          _link = link;
          _today = today;
          _settings = settings;
          _loaded = true;
        });
      }
    } catch (e) {
      debugPrint('HR check-in card: $e');
      if (mounted) setState(() => _loaded = true);
    }
  }

  Future<void> _check(bool checkIn) async {
    final link = _link!;
    setState(() => _busy = true);
    final pos = await _whereAmI();
    try {
      await selfCheck(
          employeeId: link.employeeId, checkIn: checkIn, settings: _settings, lat: pos?.latitude, lng: pos?.longitude);
      if (mounted) {
        crmSnack(
            context,
            '${checkIn ? 'Checked in' : 'Checked out'} at ${hrTime.format(DateTime.now())}'
            '${pos == null ? ' (location not available)' : ''}');
      }
      await _load();
    } catch (e) {
      debugPrint('Check in/out failed: $e');
      if (mounted) crmSnack(context, "Couldn't save. Check your connection.", error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || _link == null) return const SizedBox.shrink();
    final t = _today;
    final adminMarked = t != null && t.markedBy != 'self';
    final String text;
    if (adminMarked) {
      text = 'Today: ${attendanceLabel(t.status)}${t.status == 'leave' && t.leaveType.isNotEmpty ? ' (${t.leaveType})' : ''}';
    } else if (t?.checkOut != null) {
      text = 'In ${hrTime.format(t!.checkIn!)}  ·  out ${hrTime.format(t.checkOut!)}';
    } else if (t?.checkIn != null) {
      text = 'Checked in at ${hrTime.format(t!.checkIn!)}${t.status == 'late' ? ' (late)' : ''}';
    } else {
      text = 'Not checked in yet today';
    }
    final canIn = !adminMarked && t?.checkIn == null;
    final canOut = !adminMarked && t?.checkIn != null && t?.checkOut == null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: CrmCard(
        child: Row(children: [
          Icon(canIn ? Icons.login : Icons.how_to_reg, color: canIn ? CrmTokens.amber : CrmTokens.green),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Attendance', style: CrmTokens.body(w: FontWeight.w700)),
              Text(text, style: CrmTokens.body(size: 12, color: CrmTokens.muted)),
            ]),
          ),
          if (canIn || canOut)
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: canIn ? CrmTokens.amber : CrmTokens.navy, elevation: 0),
              onPressed: _busy ? null : () => _check(canIn),
              child: _busy
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(canIn ? 'Check in' : 'Check out',
                      style: CrmTokens.body(color: canIn ? CrmTokens.navyDark : Colors.white, w: FontWeight.w700)),
            ),
          IconButton(
            tooltip: 'My attendance, leave and payslips',
            icon: const Icon(Icons.chevron_right),
            onPressed: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const MyHrPage()));
              _load();
            },
          ),
        ]),
      ),
    );
  }
}

class MyHrPage extends StatefulWidget {
  const MyHrPage({super.key});

  @override
  State<MyHrPage> createState() => _MyHrPageState();
}

class _MyHrPageState extends State<MyHrPage> {
  ({String employeeId, String name})? _link;
  bool _loaded = false;
  Object? _error;
  HrSettings _settings = const HrSettings();
  String _month = monthKey(DateTime.now());
  List<Attendance> _days = const [];
  List<LeaveRequest> _leave = const [];
  List<(String, PayLine)> _slips = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final link = await myEmployeeLink();
      if (link == null) {
        if (mounted) {
          setState(() {
            _link = null;
            _loaded = true;
          });
        }
        return;
      }
      final r = await Future.wait<Object>([loadHrSettings(), loadMyAttendance(_month), loadMyLeaveRequests(), loadMyPayslips()]);
      if (!mounted) return;
      setState(() {
        _link = link;
        _settings = r[0] as HrSettings;
        _days = r[1] as List<Attendance>;
        _leave = r[2] as List<LeaveRequest>;
        _slips = r[3] as List<(String, PayLine)>;
        _loaded = true;
      });
    } catch (e) {
      debugPrint('My HR: $e');
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _apply() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => LeaveApplyDialog(settings: _settings, self: _link),
    );
    if (ok == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CrmTokens.bg,
      appBar: AppBar(
        backgroundColor: CrmTokens.navy,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text('My attendance and pay', style: CrmTokens.display(size: 18, color: Colors.white, w: FontWeight.w600)),
      ),
      floatingActionButton: _link == null
          ? null
          : FloatingActionButton.extended(
              backgroundColor: CrmTokens.amber,
              foregroundColor: CrmTokens.navyDark,
              onPressed: _apply,
              icon: const Icon(Icons.event_busy),
              label: Text('Apply for leave', style: CrmTokens.body(color: CrmTokens.navyDark, w: FontWeight.w700)),
            ),
      body: !_loaded
          ? hrLoading(_error, _load, what: 'your HR details')
          : _link == null
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CrmEmpty(
                        icon: Icons.badge_outlined,
                        text: 'Your login isn\'t linked to a staff record yet. Ask your office to add you in HR.'),
                  ),
                )
              : RefreshIndicator(color: CrmTokens.navy, onRefresh: _load, child: _body()),
    );
  }

  Widget _body() {
    final year = DateTime.now().year;
    final used = <String, num>{};
    for (final r in _leave) {
      if (r.status == 'approved' && r.from.year == year) used[r.type] = (used[r.type] ?? 0) + r.days;
    }
    num count(String s) => _days.where((d) => d.status == s).length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 96),
      children: [
        const HrCheckInCard(),
        HrMonthBar(_month, (m) {
          setState(() => _month = m);
          _load();
        }),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: CrmStat(label: 'Present', value: hrPlain(count('present') + count('late')))),
          const SizedBox(width: 8),
          Expanded(child: CrmStat(label: 'Late', value: hrPlain(count('late')))),
          const SizedBox(width: 8),
          Expanded(child: CrmStat(label: 'Absent', value: hrPlain(count('absent')))),
          const SizedBox(width: 8),
          Expanded(child: CrmStat(label: 'Leave', value: hrPlain(count('leave')))),
        ]),
        const SizedBox(height: 8),
        for (final d in _days.take(31))
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: CrmCard(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(children: [
                Expanded(child: Text(crmDay.format(DateTime.parse(d.date)), style: CrmTokens.body())),
                if (d.checkIn != null)
                  Text('${hrTime.format(d.checkIn!)}${d.checkOut != null ? ' – ${hrTime.format(d.checkOut!)}' : ''}  ',
                      style: CrmTokens.body(size: 12, color: CrmTokens.muted)),
                CrmPill(attendanceLabel(d.status), color: attendanceColor(d.status), background: attendanceBg(d.status)),
              ]),
            ),
          ),
        CrmSectionTitle('Leave in $year'),
        CrmCard(
          child: Column(children: [
            for (final t in _settings.leaveTypes.where((t) => t.daysPerYear > 0))
              HrInfoRow(t.name, '${hrPlain(t.daysPerYear - (used[t.name] ?? 0))} left of ${hrPlain(t.daysPerYear)}'),
          ]),
        ),
        const SizedBox(height: 8),
        for (final r in _leave.take(20))
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: CrmCard(
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${r.type}  ·  ${hrPlain(r.days)} day${r.days == 1 ? '' : 's'}', style: CrmTokens.body(w: FontWeight.w600)),
                    Text(r.from == r.to ? crmDay.format(r.from) : '${crmDay.format(r.from)} – ${crmDay.format(r.to)}',
                        style: CrmTokens.body(size: 12, color: CrmTokens.muted)),
                  ]),
                ),
                CrmPill(r.status[0].toUpperCase() + r.status.substring(1),
                    color: r.status == 'approved'
                        ? CrmTokens.green
                        : r.status == 'rejected'
                            ? CrmTokens.red
                            : r.status == 'pending'
                                ? CrmTokens.amber
                                : CrmTokens.muted,
                    background: CrmTokens.bg),
                if (r.status == 'pending')
                  IconButton(
                    tooltip: 'Cancel request',
                    icon: const Icon(Icons.close, size: 18, color: CrmTokens.muted),
                    onPressed: () async {
                      await cancelMyLeave(r);
                      _load();
                    },
                  ),
              ]),
            ),
          ),
        const CrmSectionTitle('Payslips'),
        if (_slips.isEmpty) Text('Payslips appear here once the office finalises a month.', style: CrmTokens.body(color: CrmTokens.muted)),
        for (final (month, l) in _slips)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: CrmCard(
              onTap: () => showPrintPreview(context,
                  title: 'Payslip ${hrMonthLabel.format(monthStart(month))}',
                  buildPdf: () => payslipPdf(month, l),
                  fileName: 'Payslip_$month.pdf'),
              child: Row(children: [
                const Icon(Icons.receipt_long_outlined, color: CrmTokens.navy),
                const SizedBox(width: 10),
                Expanded(child: Text(hrMonthLabel.format(monthStart(month)), style: CrmTokens.body(w: FontWeight.w600))),
                Text(crmRs(l.net), style: CrmTokens.body(w: FontWeight.w700)),
              ]),
            ),
          ),
      ],
    );
  }
}
