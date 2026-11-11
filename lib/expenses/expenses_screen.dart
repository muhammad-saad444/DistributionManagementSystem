// Admin: the company's expenses, a month at a time. Totals by category and against last month,
// a day-by-day list, add / edit / delete, and a printable monthly statement.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../account/account.dart';
import '../print_preview.dart';
import '../ui/app_theme.dart';
import 'expenses_data.dart';

final _money = NumberFormat('#,##0');
String _rs(num v) => 'Rs ${_money.format(v.round())}';
final _monthName = DateFormat('MMMM yyyy');
final _dayName = DateFormat('EEE, d MMM');

class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  DateTime _month = monthStart(DateTime.now());
  StreamSubscription<List<Expense>>? _sub;
  List<Expense>? _this; // this month
  List<Expense> _last = const []; // the month before, for comparison
  Object? _error;

  @override
  void initState() {
    super.initState();
    _watch();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _watch() {
    _sub?.cancel();
    setState(() {
      _this = null;
      _error = null;
    });
    final prev = DateTime(_month.year, _month.month - 1);
    final month = _month;
    _sub = watchExpenses(prev, nextMonth(month)).listen((all) {
      if (!mounted) return;
      setState(() {
        _this = all.where((e) => !e.date.isBefore(month)).toList();
        _last = all.where((e) => e.date.isBefore(month)).toList();
      });
    }, onError: (Object e) {
      debugPrint('Expenses: $e');
      if (mounted) setState(() => _error = e);
    });
  }

  void _shiftMonth(int by) {
    _month = DateTime(_month.year, _month.month + by);
    _watch();
  }

  bool get _isCurrentMonth => _month == monthStart(DateTime.now());

  /// Categories to offer: the defaults plus any the company has used.
  List<String> get _categories {
    final used = {for (final e in [...?_this, ..._last]) e.category};
    return [
      ...defaultExpenseCategories.where((c) => c != 'Other'),
      ...used.where((c) => !defaultExpenseCategories.contains(c)),
      'Other',
    ];
  }

  Future<void> _edit([Expense? e]) async {
    final saved = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ExpenseSheet(
        expense: e,
        categories: _categories,
        defaultDate: _isCurrentMonth ? DateTime.now() : DateTime(_month.year, _month.month + 1, 0),
      ),
    );
    if (saved != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(saved)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = _this;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Expenses'),
        actions: [
          IconButton(
            tooltip: 'Print this month',
            icon: const Icon(Icons.print_outlined),
            onPressed: list == null || list.isEmpty
                ? null
                : () => showPrintPreview(
                      context,
                      title: 'Expenses · ${_monthName.format(_month)}',
                      fileName: 'expenses-${DateFormat('yyyy-MM').format(_month)}.pdf',
                      buildPdf: () => _expensesPdf(list, _month),
                    ),
          ),
          const SizedBox(width: 6),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        icon: const Icon(Icons.add),
        label: const Text('Add expense'),
      ),
      body: LayoutBuilder(builder: (context, box) {
        final wide = box.maxWidth >= 760;
        return ListView(
          padding: EdgeInsets.fromLTRB(wide ? 24 : 14, 16, wide ? 24 : 14, 96),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1000),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  _monthBar(),
                  const SizedBox(height: 12),
                  if (list == null)
                    _error != null
                        ? _message(Icons.cloud_off, "Couldn't load expenses", 'Check the connection and try again.',
                            action: TextButton(onPressed: _watch, child: const Text('Try again')))
                        : const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator()))
                  else ...[
                    _summary(ExpenseSummary.of(list), ExpenseSummary.of(_last), wide),
                    const SizedBox(height: 14),
                    if (list.isEmpty)
                      _message(Icons.receipt_long_outlined, 'No expenses in ${_monthName.format(_month)}',
                          'Add rent, fuel, wages, bills and other running costs here. Profit & loss takes them off gross profit.')
                    else
                      _dayList(list),
                  ],
                ]),
              ),
            ),
          ],
        );
      }),
    );
  }

  Widget _monthBar() => Row(children: [
        IconButton(tooltip: 'Previous month', icon: const Icon(Icons.chevron_left), onPressed: () => _shiftMonth(-1)),
        Expanded(
          child: Text(_monthName.format(_month),
              textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text)),
        ),
        IconButton(
          tooltip: 'Next month',
          icon: const Icon(Icons.chevron_right),
          onPressed: _isCurrentMonth ? null : () => _shiftMonth(1),
        ),
      ]);

  Widget _summary(ExpenseSummary s, ExpenseSummary last, bool wide) {
    String change() {
      if (last.total < 0.5) return s.total < 0.5 ? '' : 'Nothing spent the month before';
      final pct = (s.total - last.total) / last.total * 100;
      return '${pct >= 0 ? '▲' : '▼'} ${pct.abs().toStringAsFixed(0)}% vs ${DateFormat('MMMM').format(DateTime(_month.year, _month.month - 1))} (${_rs(last.total)})';
    }

    final headline = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('SPENT IN ${DateFormat('MMMM').format(_month).toUpperCase()}', style: _caps()),
      const SizedBox(height: 6),
      Text(_rs(s.total), style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
      const SizedBox(height: 4),
      Text('${s.count} expense${s.count == 1 ? '' : 's'}', style: _small()),
      if (change().isNotEmpty) ...[
        const SizedBox(height: 2),
        Text(change(), style: _small(color: s.total > last.total && last.total > 0.5 ? AppColors.red : AppColors.green)),
      ],
      if (s.byMethod.isNotEmpty) ...[
        const SizedBox(height: 12),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final e in s.byMethod.entries)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(20)),
              child: Text('${e.key}: ${_rs(e.value)}', style: _small(size: 11.5, color: AppColors.text)),
            ),
        ]),
      ],
    ]);

    final cats = s.byCategory.take(6).toList();
    final breakdown = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('BY CATEGORY', style: _caps()),
      const SizedBox(height: 10),
      if (cats.isEmpty) Text('—', style: _small()),
      for (final c in cats) ...[
        Row(children: [
          Icon(expenseIcon(c.key), size: 15, color: AppColors.muted),
          const SizedBox(width: 6),
          Expanded(child: Text(c.key, overflow: TextOverflow.ellipsis, style: _small(color: AppColors.text))),
          Text(_rs(c.value), style: _small(color: AppColors.text, w: FontWeight.w600)),
        ]),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: s.total < 0.5 ? 0 : c.value / s.total,
            minHeight: 5,
            backgroundColor: AppColors.bg,
            color: AppColors.navy,
          ),
        ),
        const SizedBox(height: 9),
      ],
      if (s.byCategory.length > cats.length)
        Text('+ ${s.byCategory.length - cats.length} more categor${s.byCategory.length - cats.length == 1 ? 'y' : 'ies'}',
            style: _small(size: 11.5)),
    ]);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: wide
            ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(flex: 4, child: headline),
                const SizedBox(width: 24),
                Expanded(flex: 5, child: breakdown),
              ])
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                headline,
                const SizedBox(height: 18),
                breakdown,
              ]),
      ),
    );
  }

  Widget _dayList(List<Expense> list) {
    final byDay = <DateTime, List<Expense>>{};
    for (final e in list) {
      byDay.putIfAbsent(DateTime(e.date.year, e.date.month, e.date.day), () => []).add(e);
    }
    final days = byDay.keys.toList()..sort((a, b) => b.compareTo(a));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final d in days) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
          child: Row(children: [
            Expanded(child: Text(_dayName.format(d), style: _small(color: AppColors.text, w: FontWeight.w600))),
            Text(_rs(byDay[d]!.fold<double>(0, (s, e) => s + e.amount)), style: _small(w: FontWeight.w600)),
          ]),
        ),
        Card(
          margin: const EdgeInsets.only(bottom: 6),
          clipBehavior: Clip.antiAlias,
          child: Column(children: [
            for (var i = 0; i < byDay[d]!.length; i++) ...[
              if (i > 0) const Divider(height: 1, indent: 60),
              _row(byDay[d]![i]),
            ],
          ]),
        ),
      ],
    ]);
  }

  Widget _row(Expense e) {
    final title = e.paidTo.isNotEmpty ? e.paidTo : e.category;
    final sub = [
      if (e.paidTo.isNotEmpty) e.category,
      e.method,
      if (e.note.isNotEmpty) e.note,
    ].join(' · ');
    return ListTile(
      onTap: () => _edit(e),
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: AppColors.brandSoft,
        child: Icon(expenseIcon(e.category), size: 18, color: AppColors.navy),
      ),
      title: Text(title, overflow: TextOverflow.ellipsis),
      subtitle: Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: Text(_rs(e.amount), style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.text)),
    );
  }

  Widget _message(IconData icon, String title, String text, {Widget? action}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 40, color: AppColors.muted),
          const SizedBox(height: 12),
          Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text)),
          const SizedBox(height: 4),
          Text(text, textAlign: TextAlign.center, style: _small()),
          if (action != null) ...[const SizedBox(height: 12), action],
        ]),
      );
}

TextStyle _caps() => const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: AppColors.muted);
TextStyle _small({Color color = AppColors.muted, FontWeight w = FontWeight.w400, double size = 12.5}) =>
    TextStyle(fontSize: size, fontWeight: w, color: color);

// =============================================================================
// Add / edit
// =============================================================================

class _ExpenseSheet extends StatefulWidget {
  final Expense? expense;
  final List<String> categories;
  final DateTime defaultDate;
  const _ExpenseSheet({this.expense, required this.categories, required this.defaultDate});

  @override
  State<_ExpenseSheet> createState() => _ExpenseSheetState();
}

class _ExpenseSheetState extends State<_ExpenseSheet> {
  final _form = GlobalKey<FormState>();
  late final _amount = TextEditingController(
      text: widget.expense == null ? '' : (widget.expense!.amount == widget.expense!.amount.roundToDouble()
          ? widget.expense!.amount.toStringAsFixed(0)
          : widget.expense!.amount.toString()));
  late final _paidTo = TextEditingController(text: widget.expense?.paidTo ?? '');
  late final _note = TextEditingController(text: widget.expense?.note ?? '');
  late final _custom = TextEditingController();
  late DateTime _date = widget.expense?.date ?? widget.defaultDate;
  late String _category = widget.expense?.category ?? widget.categories.first;
  late String _method = widget.expense?.method ?? 'Cash';
  bool _saving = false;

  bool get _editing => widget.expense?.id != null;

  @override
  void initState() {
    super.initState();
    if (!widget.categories.contains(_category)) _category = 'Other';
  }

  @override
  void dispose() {
    _amount.dispose();
    _paidTo.dispose();
    _note.dispose();
    _custom.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _date.isAfter(now) ? now : _date,
      firstDate: DateTime(now.year - 3),
      lastDate: now,
    );
    if (d != null) setState(() => _date = d);
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final category = _category == 'Other' && _custom.text.trim().isNotEmpty ? _custom.text.trim() : _category;
    setState(() => _saving = true);
    try {
      await saveExpense(Expense(
        id: widget.expense?.id,
        date: _date,
        category: category,
        amount: double.parse(_amount.text.trim()),
        method: _method,
        paidTo: _paidTo.text,
        note: _note.text,
      ));
      if (mounted) Navigator.pop(context, _editing ? 'Expense updated' : 'Expense added');
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Couldn't save: $e")));
      }
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete this expense?'),
        content: Text('${widget.expense!.category} · ${_rs(widget.expense!.amount)} on ${_dayName.format(widget.expense!.date)}. '
            'This can\'t be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _saving = true);
    try {
      await deleteExpense(widget.expense!.id!);
      if (mounted) Navigator.pop(context, 'Expense deleted');
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Couldn't delete: $e")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Form(
              key: _form,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(_editing ? 'Edit expense' : 'Add expense',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.text)),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _amount,
                  autofocus: !_editing,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  decoration: const InputDecoration(labelText: 'Amount (Rs)', prefixText: 'Rs  '),
                  validator: (v) {
                    final n = double.tryParse((v ?? '').trim());
                    if (n == null || n <= 0) return 'Enter the amount';
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                Text('Category', style: _small(w: FontWeight.w600)),
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final c in widget.categories)
                    ChoiceChip(
                      avatar: Icon(expenseIcon(c), size: 16, color: _category == c ? AppColors.navy : AppColors.muted),
                      label: Text(c),
                      selected: _category == c,
                      showCheckmark: false,
                      onSelected: (_) => setState(() => _category = c),
                    ),
                ]),
                if (_category == 'Other') ...[
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _custom,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(labelText: 'Category name (optional)', hintText: 'e.g. Godown security'),
                  ),
                ],
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(AppRadius.field),
                      onTap: _pickDate,
                      child: InputDecorator(
                        decoration: const InputDecoration(labelText: 'Date', prefixIcon: Icon(Icons.event_outlined, size: 20)),
                        child: Text(DateFormat('d MMM yyyy').format(_date)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: expenseMethods.contains(_method) ? _method : 'Cash',
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Paid by'),
                      items: [for (final m in expenseMethods) DropdownMenuItem(value: m, child: Text(m, overflow: TextOverflow.ellipsis))],
                      onChanged: (v) => setState(() => _method = v ?? 'Cash'),
                    ),
                  ),
                ]),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _paidTo,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Paid to (optional)', hintText: 'e.g. PSO pump, landlord, K-Electric'),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _note,
                  textCapitalization: TextCapitalization.sentences,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Note (optional)'),
                ),
                const SizedBox(height: 20),
                Row(children: [
                  if (_editing)
                    TextButton.icon(
                      onPressed: _saving ? null : _delete,
                      style: TextButton.styleFrom(foregroundColor: AppColors.red),
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('Delete'),
                    ),
                  const Spacer(),
                  TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text(_editing ? 'Save' : 'Add expense'),
                  ),
                ]),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Printed monthly statement
// =============================================================================

Future<Uint8List> _expensesPdf(List<Expense> list, DateTime month) async {
  final doc = pw.Document();
  final s = ExpenseSummary.of(list);
  final rows = [...list]..sort((a, b) => a.date.compareTo(b.date));
  pw.Widget cell(String t, {bool right = false, bool bold = false}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        child: pw.Text(t,
            textAlign: right ? pw.TextAlign.right : pw.TextAlign.left,
            style: pw.TextStyle(fontSize: 9, fontWeight: bold ? pw.FontWeight.bold : null)),
      );

  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4.copyWith(marginLeft: 36, marginRight: 36, marginTop: 36, marginBottom: 36),
    footer: (ctx) => pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
    ),
    build: (_) => [
      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
        pw.Text(Account.companyName, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
        pw.Text('Expenses · ${_monthName.format(month)}', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
      ]),
      pw.SizedBox(height: 12),
      pw.Text('By category', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 4),
      pw.Table(
        border: pw.TableBorder.all(color: PdfColors.grey500, width: 0.5),
        columnWidths: const {0: pw.FlexColumnWidth(4), 1: pw.FlexColumnWidth(2), 2: pw.FlexColumnWidth(1)},
        children: [
          pw.TableRow(decoration: const pw.BoxDecoration(color: PdfColors.grey300), children: [
            cell('Category', bold: true),
            cell('Amount (Rs)', bold: true, right: true),
            cell('Share', bold: true, right: true),
          ]),
          for (final c in s.byCategory)
            pw.TableRow(children: [
              cell(c.key),
              cell(_money.format(c.value.round()), right: true),
              cell('${(c.value / s.total * 100).toStringAsFixed(0)}%', right: true),
            ]),
          pw.TableRow(decoration: const pw.BoxDecoration(color: PdfColors.grey200), children: [
            cell('Total', bold: true),
            cell(_money.format(s.total.round()), bold: true, right: true),
            cell('100%', bold: true, right: true),
          ]),
        ],
      ),
      pw.SizedBox(height: 14),
      pw.Text('All expenses', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 4),
      pw.Table(
        border: pw.TableBorder.all(color: PdfColors.grey500, width: 0.5),
        columnWidths: const {
          0: pw.FixedColumnWidth(58),
          1: pw.FlexColumnWidth(2.2),
          2: pw.FlexColumnWidth(2.4),
          3: pw.FlexColumnWidth(1.6),
          4: pw.FlexColumnWidth(2.4),
          5: pw.FlexColumnWidth(1.6),
        },
        children: [
          pw.TableRow(repeat: true, decoration: const pw.BoxDecoration(color: PdfColors.grey300), children: [
            cell('Date', bold: true),
            cell('Category', bold: true),
            cell('Paid to', bold: true),
            cell('Paid by', bold: true),
            cell('Note', bold: true),
            cell('Amount (Rs)', bold: true, right: true),
          ]),
          for (final e in rows)
            pw.TableRow(children: [
              cell(DateFormat('dd-MM-yyyy').format(e.date)),
              cell(e.category),
              cell(e.paidTo),
              cell(e.method),
              cell(e.note),
              cell(_money.format(e.amount.round()), right: true),
            ]),
          pw.TableRow(decoration: const pw.BoxDecoration(color: PdfColors.grey200), children: [
            cell(''),
            cell('Total (${s.count})', bold: true),
            cell(''),
            cell(''),
            cell(''),
            cell(_money.format(s.total.round()), bold: true, right: true),
          ]),
        ],
      ),
    ],
  ));
  return doc.save();
}
