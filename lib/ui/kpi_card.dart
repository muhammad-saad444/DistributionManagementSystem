// The figure card used on the dashboard and the accounts pages: a tinted icon, a small caps label,
// a big number, a line under it, and a trend line or progress bar at the bottom. Cards sit in rows
// of equal, fixed height (kpiGrid), so a page of them lines up.
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_theme.dart';

/// White card with a hairline border and a soft shadow (the dashboard's card).
BoxDecoration kpiCardDecoration({Color color = Colors.white}) => BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: color == Colors.white ? AppColors.border : Colors.transparent),
      boxShadow: [
        BoxShadow(color: AppColors.navyDark.withValues(alpha: 0.06), blurRadius: 18, offset: const Offset(0, 8)),
      ],
    );

TextStyle _caps(Color c) => GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w700, color: c, letterSpacing: 0.9);
TextStyle _body(double size, {Color color = AppColors.text, FontWeight w = FontWeight.w400}) =>
    GoogleFonts.inter(fontSize: size, fontWeight: w, color: color);

class KpiCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color tint;
  final Color tintBg;
  final String value;
  final Color? valueColor;
  final String sub;
  final Color? subColor;
  final (String, bool)? trend; // text, and whether it's good news (green) or not (red)
  final List<double>? spark;
  final double? progress;
  final String? progressLabel;
  final VoidCallback? onTap;

  const KpiCard({
    super.key,
    required this.label,
    required this.icon,
    required this.tint,
    required this.tintBg,
    required this.value,
    required this.sub,
    this.valueColor,
    this.subColor,
    this.trend,
    this.spark,
    this.progress,
    this.progressLabel,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final s = spark;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Ink(
          decoration: kpiCardDecoration(),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: tintBg, borderRadius: BorderRadius.circular(8)),
                child: Icon(icon, size: 15, color: tint),
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(label, style: _caps(AppColors.muted), maxLines: 2, overflow: TextOverflow.ellipsis)),
              if (onTap != null) const Icon(Icons.chevron_right, size: 18, color: AppColors.muted),
            ]),
            const SizedBox(height: 12),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value,
                  style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.w700, color: valueColor ?? AppColors.text, height: 1.15)),
            ),
            const SizedBox(height: 4),
            Text(sub, style: _body(11.5, color: subColor ?? AppColors.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
            if (trend != null) ...[
              const SizedBox(height: 2),
              Text(trend!.$1, style: _body(11.5, color: trend!.$2 ? AppColors.green : AppColors.red, w: FontWeight.w600)),
            ],
            const Spacer(),
            if (s != null && s.any((v) => v.abs() > 0)) ...[
              const SizedBox(height: 10),
              SizedBox(height: 30, child: KpiSparkline(values: s, color: tint)),
            ] else if (progress != null) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress!.clamp(0, 1).toDouble(),
                  minHeight: 6,
                  backgroundColor: AppColors.bg,
                  valueColor: AlwaysStoppedAnimation(tint == AppColors.navy ? AppColors.amber : tint),
                ),
              ),
              if (progressLabel != null) ...[
                const SizedBox(height: 4),
                Text(progressLabel!, style: _body(11, color: AppColors.muted)),
              ],
            ] else
              const SizedBox(height: 4),
          ]),
        ),
      ),
    );
  }
}

/// A small filled trend line; dips below zero when a value does (e.g. a month's loss).
class KpiSparkline extends StatelessWidget {
  final List<double> values;
  final Color color;
  const KpiSparkline({super.key, required this.values, required this.color});

  @override
  Widget build(BuildContext context) {
    final maxY = values.fold<double>(0, math.max);
    final minY = values.fold<double>(0, math.min);
    final span = (maxY - minY) <= 0 ? 1.0 : maxY - minY;
    return LineChart(LineChartData(
      minY: minY < 0 ? minY - span * 0.1 : 0,
      maxY: maxY <= 0 ? (minY < 0 ? span * 0.1 : 1) : maxY + span * 0.15,
      gridData: const FlGridData(show: false),
      titlesData: const FlTitlesData(show: false),
      borderData: FlBorderData(show: false),
      lineTouchData: const LineTouchData(enabled: false),
      lineBarsData: [
        LineChartBarData(
          spots: [for (var i = 0; i < values.length; i++) FlSpot(i.toDouble(), values[i])],
          isCurved: true,
          preventCurveOverShooting: true,
          color: color,
          barWidth: 2,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(
            show: true,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [color.withValues(alpha: 0.22), color.withValues(alpha: 0)],
            ),
          ),
        ),
      ],
    ));
  }
}

/// Cards in rows of [cols], each row [height] tall. A fixed height (not IntrinsicHeight) because the
/// trend lines can't report an intrinsic size.
Widget kpiGrid(List<Widget> items, int cols, {double height = 176, double gap = 14}) {
  final rows = <Widget>[];
  for (var i = 0; i < items.length; i += cols) {
    final row = items.sublist(i, math.min(i + cols, items.length));
    rows.add(SizedBox(
      height: height,
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var j = 0; j < cols; j++) ...[
          if (j > 0) SizedBox(width: gap),
          Expanded(child: j < row.length ? row[j] : const SizedBox.shrink()),
        ],
      ]),
    ));
    if (i + cols < items.length) rows.add(SizedBox(height: gap));
  }
  return Column(children: rows);
}
