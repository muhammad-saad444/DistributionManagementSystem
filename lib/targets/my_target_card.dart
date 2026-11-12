// The booker's own "this month's target" card on their home screen: sales and recovery against the
// targets the office set, whether they're keeping up, and what's needed per day. Shows nothing when
// no target is set.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../ui/app_theme.dart';
import '../ui/kpi_card.dart';
import 'targets_data.dart';

final _money = NumberFormat('#,##0');

class MyTargetCard extends StatefulWidget {
  /// This month's sales, already worked out by the home screen from the booker's invoices.
  final double monthSales;
  const MyTargetCard({super.key, required this.monthSales});

  @override
  State<MyTargetCard> createState() => _MyTargetCardState();
}

class _MyTargetCardState extends State<MyTargetCard> {
  BookerTarget? _target;
  double _recovered = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final month = DateTime(DateTime.now().year, DateTime.now().month);
    final t = await loadMyTarget(month);
    final r = t == null ? 0.0 : await loadMyRecovery(month);
    if (mounted) {
      setState(() {
        _target = t;
        _recovered = r;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = _target;
    if (t == null) return const SizedBox.shrink();
    final now = DateTime.now();
    final month = DateTime(now.year, now.month);
    final share = monthShare(month, now);
    final left = daysLeft(month, now);
    final sales = TargetProgress(t.sales, widget.monthSales, share);
    final rec = TargetProgress(t.recovery, _recovered, share);
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: kpiCardDecoration(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(color: AppColors.brandSoft, borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.flag_outlined, size: 15, color: AppColors.navy),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text('${DateFormat('MMMM').format(now)} target',
                style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: AppColors.text)),
          ),
          Text('$left day${left == 1 ? '' : 's'} left', style: const TextStyle(fontSize: 12, color: AppColors.muted)),
        ]),
        if (t.sales > 0) ...[const SizedBox(height: 12), _line('Sales', sales, left)],
        if (t.recovery > 0) ...[const SizedBox(height: 12), _line('Recovery', rec, left)],
      ]),
    );
  }

  Widget _line(String label, TargetProgress p, int left) {
    final color = switch (p.pace) {
      Pace.done || Pace.ahead => AppColors.green,
      Pace.onTrack => AppColors.blue,
      Pace.behind => AppColors.red,
      Pace.none => AppColors.muted,
    };
    final note = switch (p.pace) {
      Pace.done => 'Target reached. Well done!',
      Pace.none => '',
      _ when left > 0 => 'Rs ${_money.format(p.perDayNeeded(left).round())} a day to reach it'
          '${p.pace == Pace.behind ? ' · behind' : (p.pace == Pace.ahead ? ' · ahead' : ' · on track')}',
      _ => 'Rs ${_money.format(p.left.round())} short',
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Text(label, style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
        const SizedBox(width: 8),
        Expanded(
          child: Text('Rs ${_money.format(p.achieved.round())} of Rs ${_money.format(p.target.round())}',
              overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.text)),
        ),
        Text('${p.pct.toStringAsFixed(0)}%', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: color)),
      ]),
      const SizedBox(height: 6),
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(value: (p.pct / 100).clamp(0, 1).toDouble(), minHeight: 7, backgroundColor: AppColors.bg, color: color),
      ),
      if (note.isNotEmpty) ...[
        const SizedBox(height: 4),
        Text(note, style: TextStyle(fontSize: 11.5, color: p.pace == Pace.behind ? AppColors.red : AppColors.muted)),
      ],
    ]);
  }
}
