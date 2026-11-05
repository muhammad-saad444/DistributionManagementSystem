// Small pieces shared by the HR screens.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../crm/crm_ui.dart';

final hrMonthLabel = DateFormat('MMMM yyyy');
final hrTime = DateFormat('hh:mm a');

String hrPlain(num v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

Color attendanceColor(String status) => switch (status) {
      'present' => CrmTokens.green,
      'late' => CrmTokens.amber,
      'half' => CrmTokens.blue,
      'absent' => CrmTokens.red,
      'leave' => const Color(0xFF7C4DBA),
      'off' => CrmTokens.muted,
      _ => CrmTokens.muted,
    };

Color attendanceBg(String status) => switch (status) {
      'present' => CrmTokens.greenBg,
      'late' => CrmTokens.amberBg,
      'half' => CrmTokens.blueBg,
      'absent' => CrmTokens.redBg,
      'leave' => const Color(0xFFF0E8FA),
      _ => CrmTokens.bg,
    };

/// A text field for forms: number fields only take digits.
class HrField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData? icon;
  final String? hint;
  final bool number;
  final int lines;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;
  const HrField(this.controller, this.label,
      {super.key, this.icon, this.hint, this.number = false, this.lines = 1, this.validator, this.onChanged});

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: controller,
        maxLines: lines,
        onChanged: onChanged,
        style: CrmTokens.body(),
        keyboardType: number ? const TextInputType.numberWithOptions(decimal: true) : null,
        inputFormatters: number ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))] : null,
        decoration: crmInput(label, icon: icon, hint: hint),
        validator: validator,
      );
}

/// A tappable date box. [onPicked] gets null when cleared (if [clearable]).
class HrDateField extends StatelessWidget {
  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onPicked;
  final bool clearable;
  final DateTime? first;
  final DateTime? last;
  const HrDateField(this.label, this.value, this.onPicked, {super.key, this.clearable = true, this.first, this.last});

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: () async {
          final now = DateTime.now();
          final d = await showDatePicker(
            context: context,
            initialDate: value ?? now,
            firstDate: first ?? DateTime(1950),
            lastDate: last ?? DateTime(now.year + 2),
          );
          if (d != null) onPicked(d);
        },
        child: InputDecorator(
          decoration: crmInput(label, icon: Icons.calendar_today_outlined).copyWith(
            suffixIcon: clearable && value != null
                ? IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => onPicked(null))
                : null,
          ),
          child: Text(value == null ? 'Not set' : crmDay.format(value!),
              style: CrmTokens.body(color: value == null ? CrmTokens.muted : CrmTokens.textDark)),
        ),
      );
}

/// Two widgets side by side on wide screens, stacked on phones.
Widget hrPair(BuildContext context, Widget a, Widget b) {
  if (MediaQuery.of(context).size.width < 600) return Column(children: [a, const SizedBox(height: 12), b]);
  return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Expanded(child: a),
    const SizedBox(width: 12),
    Expanded(child: b),
  ]);
}

/// Previous / next month picker.
class HrMonthBar extends StatelessWidget {
  final String month; // yyyy-MM
  final ValueChanged<String> onChanged;
  const HrMonthBar(this.month, this.onChanged, {super.key});

  @override
  Widget build(BuildContext context) {
    final d = DateTime.parse('$month-01');
    String key(DateTime x) => DateFormat('yyyy-MM').format(x);
    final next = DateTime(d.year, d.month + 1);
    final canNext = !next.isAfter(DateTime(DateTime.now().year, DateTime.now().month + 1));
    return CrmCard(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: Row(children: [
        IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => onChanged(key(DateTime(d.year, d.month - 1)))),
        Expanded(child: Center(child: Text(hrMonthLabel.format(d), style: CrmTokens.display(size: 15)))),
        IconButton(icon: const Icon(Icons.chevron_right), onPressed: canNext ? () => onChanged(key(next)) : null),
      ]),
    );
  }
}

Future<bool> hrConfirm(BuildContext context, String title, String text, String yes, {bool danger = false}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      title: Text(title, style: CrmTokens.display(size: 17)),
      content: Text(text, style: CrmTokens.body()),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d, false), child: Text('Cancel', style: CrmTokens.body())),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: danger ? CrmTokens.red : CrmTokens.navy, elevation: 0),
          onPressed: () => Navigator.pop(d, true),
          child: Text(yes, style: CrmTokens.body(color: Colors.white, w: FontWeight.w600)),
        ),
      ],
    ),
  );
  return ok == true;
}

/// Loading / error / content for a screen part that loads once.
Widget hrLoading(Object? error, VoidCallback retry, {String what = 'HR data'}) {
  if (error == null) return const Center(child: CircularProgressIndicator(color: CrmTokens.navy));
  return Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      CrmEmpty(icon: Icons.cloud_off, text: "Couldn't load $what. Check your connection."),
      OutlinedButton(onPressed: retry, child: Text('Try again', style: CrmTokens.body(color: CrmTokens.navy))),
    ]),
  );
}

/// Label: value rows in detail views.
class HrInfoRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;
  final Color? color;
  const HrInfoRow(this.label, this.value, {super.key, this.bold = false, this.color});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Text(label, style: CrmTokens.body(color: CrmTokens.muted))),
          const SizedBox(width: 10),
          Flexible(
            child: Text(value.isEmpty ? '—' : value,
                textAlign: TextAlign.right,
                style: CrmTokens.body(w: bold ? FontWeight.w700 : FontWeight.w500, color: color ?? CrmTokens.textDark)),
          ),
        ]),
      );
}
