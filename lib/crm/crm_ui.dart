// Design tokens and small widgets shared by the CRM screens (same palette as khata.dart).
import 'package:flutter/material.dart';
import 'package:an_agency/ui/app_theme.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import 'crm_data.dart';

class CrmTokens {
  static const navy = AppColors.navy;
  static const navyDark = AppColors.navyDark;
  static const amber = AppColors.amber;
  static const amberBg = AppColors.amberBg;
  static const bg = AppColors.bg;
  static const border = AppColors.border;
  static const textDark = AppColors.text;
  static const muted = AppColors.muted;
  static const red = AppColors.red;
  static const redBg = AppColors.redBg;
  static const green = AppColors.green;
  static const greenBg = AppColors.greenBg;
  static const blue = AppColors.blue;
  static const blueBg = AppColors.blueBg;

  static TextStyle display({double size = 18, Color? color, FontWeight w = FontWeight.w700}) =>
      GoogleFonts.inter(fontSize: size, fontWeight: w, color: color ?? textDark);
  static TextStyle body({double size = 13, Color? color, FontWeight w = FontWeight.w400}) =>
      GoogleFonts.inter(fontSize: size, fontWeight: w, color: color ?? textDark);
}

final _money = NumberFormat('#,##0');
final crmDay = DateFormat('dd MMM yyyy');
String crmRs(num v) => 'Rs. ${_money.format(v.round())}';

/// "Today", "Yesterday", "5 days ago", or the date once it is over a month old.
String crmAgo(DateTime? d, {String never = 'Never'}) {
  if (d == null) return never;
  final days = daysSince(d);
  if (days < 0) return 'In ${-days} day${days == -1 ? '' : 's'}';
  if (days == 0) return 'Today';
  if (days == 1) return 'Yesterday';
  if (days < 31) return '$days days ago';
  return crmDay.format(d);
}

/// "Overdue 3 days", "Due today", "Due tomorrow", "Due 12 Nov 2026".
String crmDue(CrmFollowUp f) {
  final days = daysSince(f.dueDate);
  if (days > 0) return 'Overdue $days day${days == 1 ? '' : 's'}';
  if (days == 0) return 'Due today';
  if (days == -1) return 'Due tomorrow';
  return 'Due ${crmDay.format(f.dueDate)}';
}

(Color, Color) outcomeColors(VisitOutcome o) {
  switch (o.key) {
    case 'order':
      return (CrmTokens.green, CrmTokens.greenBg);
    case 'payment':
      return (CrmTokens.blue, CrmTokens.blueBg);
    case 'complaint':
    case 'closed':
      return (CrmTokens.red, CrmTokens.redBg);
    default:
      return (CrmTokens.muted, CrmTokens.bg);
  }
}

IconData outcomeIcon(VisitOutcome o) {
  switch (o.key) {
    case 'order':
      return Icons.shopping_bag_outlined;
    case 'no_order':
      return Icons.remove_shopping_cart_outlined;
    case 'payment':
      return Icons.payments_outlined;
    case 'closed':
      return Icons.store_mall_directory_outlined;
    case 'complaint':
      return Icons.report_problem_outlined;
    case 'call':
      return Icons.phone_outlined;
    default:
      return Icons.directions_walk;
  }
}

class CrmPill extends StatelessWidget {
  final String text;
  final Color color;
  final Color background;
  final IconData? icon;
  const CrmPill(this.text, {super.key, this.color = CrmTokens.navy, this.background = CrmTokens.bg, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 12, color: color), const SizedBox(width: 4)],
          Text(text, style: CrmTokens.body(size: 11, color: color, w: FontWeight.w600)),
        ],
      ),
    );
  }
}

class CrmCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  const CrmCard({super.key, required this.child, this.padding = const EdgeInsets.all(14), this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: CrmTokens.border),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// A small labelled number, used in stat rows.
class CrmStat extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  final VoidCallback? onTap;
  const CrmStat({super.key, required this.label, required this.value, this.color, this.onTap});

  @override
  Widget build(BuildContext context) {
    return CrmCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: CrmTokens.body(size: 11, color: CrmTokens.muted)),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: CrmTokens.display(size: 16, color: color ?? CrmTokens.navy)),
          ),
        ],
      ),
    );
  }
}

class CrmSectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const CrmSectionTitle(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 18, 2, 8),
      child: Row(
        children: [
          Expanded(child: Text(text, style: CrmTokens.display(size: 14, w: FontWeight.w600))),
          ?trailing,
        ],
      ),
    );
  }
}

class CrmEmpty extends StatelessWidget {
  final IconData icon;
  final String text;
  const CrmEmpty({super.key, required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
      child: Column(
        children: [
          Icon(icon, size: 36, color: CrmTokens.border),
          const SizedBox(height: 10),
          Text(text, textAlign: TextAlign.center, style: CrmTokens.body(color: CrmTokens.muted)),
        ],
      ),
    );
  }
}

InputDecoration crmInput(String label, {IconData? icon, String? hint}) => InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: CrmTokens.body(color: CrmTokens.muted),
      prefixIcon: icon == null ? null : Icon(icon, size: 20, color: CrmTokens.muted),
      filled: true,
      fillColor: Colors.white,
      isDense: true,
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: CrmTokens.border)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: CrmTokens.amber, width: 1.5)),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
    );

void crmSnack(BuildContext context, String text, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(text),
    backgroundColor: error ? CrmTokens.red : CrmTokens.navy,
  ));
}
