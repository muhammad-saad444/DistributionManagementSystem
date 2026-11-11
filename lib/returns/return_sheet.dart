// The return form, used from the admin's Invoices page and the booker's invoice screen: each item
// with how many came back and in what condition, the refund worked out as you type, and a note.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../ui/app_theme.dart';
import 'returns_data.dart';

final _money = NumberFormat('#,##0');

/// Opens the form for [invoice] (its Firestore data) and saves the return. Returns the refund when
/// a return was saved, null when cancelled.
Future<double?> showReturnSheet(BuildContext context, {required String invoiceId, required Map<String, dynamic> invoice}) {
  return showModalBottomSheet<double>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _ReturnSheet(invoiceId: invoiceId, invoice: invoice),
  );
}

class _ReturnSheet extends StatefulWidget {
  final String invoiceId;
  final Map<String, dynamic> invoice;
  const _ReturnSheet({required this.invoiceId, required this.invoice});

  @override
  State<_ReturnSheet> createState() => _ReturnSheetState();
}

class _ReturnSheetState extends State<_ReturnSheet> {
  late final List<Map<String, dynamic>> _items = [
    for (final it in (widget.invoice['items'] as List? ?? const [])) Map<String, dynamic>.from(it as Map),
  ];
  late final List<TextEditingController> _qty = [for (final _ in _items) TextEditingController()];
  late final List<ReturnCondition> _cond = [for (final _ in _items) ReturnCondition.good];
  final _note = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final c in _qty) {
      c.dispose();
    }
    _note.dispose();
    super.dispose();
  }

  double _num(dynamic v) => (num.tryParse('${v ?? 0}') ?? 0).toDouble();

  List<ReturnLine> get _lines => [
        for (var i = 0; i < _items.length; i++)
          if ((double.tryParse(_qty[i].text.trim()) ?? 0) > 0) ReturnLine(i, double.parse(_qty[i].text.trim()), _cond[i]),
      ];

  /// The refund so far, or null with the reason when the quantities aren't valid yet.
  (double?, String?) get _preview {
    final lines = _lines;
    if (lines.isEmpty) return (null, null);
    try {
      return (applyReturn(widget.invoice, lines).refund, null);
    } on ArgumentError catch (e) {
      return (null, e.message.toString());
    }
  }

  Future<void> _save() async {
    final (refund, problem) = _preview;
    if (refund == null) {
      setState(() => _error = problem ?? 'Enter how many units came back');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await saveReturn(invoiceId: widget.invoiceId, lines: _lines, note: _note.text);
      if (mounted) Navigator.pop(context, saved);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e is ArgumentError ? e.message.toString() : "Couldn't save: $e";
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final factor = invoiceDiscountFactor(widget.invoice);
    final (refund, problem) = _preview;
    final damaged = _lines.where((l) => !l.condition.backToStock).fold<double>(0, (s, l) => s + l.qty);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Return goods · Invoice #${widget.invoice['invoiceNumber'] ?? ''}',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.text)),
              const SizedBox(height: 2),
              Text(
                '${widget.invoice['customer'] ?? ''}'
                '${factor < 0.999 ? ' · this invoice had ${((1 - factor) * 100).toStringAsFixed(1)}% discount, so the refund is after discount' : ''}',
                style: const TextStyle(fontSize: 12.5, color: AppColors.muted),
              ),
              const SizedBox(height: 14),
              for (var i = 0; i < _items.length; i++) ...[
                _itemRow(i),
                const SizedBox(height: 10),
              ],
              TextField(
                controller: _note,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Note (optional)', hintText: 'e.g. Leaking packs, near expiry'),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(AppRadius.card)),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Refund to the shop', style: TextStyle(fontSize: 12, color: AppColors.muted)),
                      Text(refund == null ? '—' : 'Rs ${_money.format(refund.round())}',
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.text)),
                    ]),
                  ),
                  if (damaged > 0)
                    Text('${_money.format(damaged)} unit${damaged == 1 ? '' : 's'} written off\n(not back in stock)',
                        textAlign: TextAlign.right, style: const TextStyle(fontSize: 12, color: AppColors.amberDark, fontWeight: FontWeight.w600)),
                ]),
              ),
              if ((_error ?? problem) != null) ...[
                const SizedBox(height: 8),
                Text(_error ?? problem!, style: const TextStyle(fontSize: 12.5, color: AppColors.red)),
              ],
              const SizedBox(height: 16),
              Row(children: [
                const Spacer(),
                TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _saving || refund == null ? null : _save,
                  child: _saving
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Save return'),
                ),
              ]),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _itemRow(int i) {
    final it = _items[i];
    final sold = _num(it['QTY']);
    final back = _num(it['returnQty']);
    final left = returnableQty(it);
    final done = left <= 0;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: done ? AppColors.bg : Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text((it['Product Name'] ?? 'Item').toString(),
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.text)),
              Text(
                'Sold ${_money.format(sold)} · returned ${_money.format(back)} · ${done ? 'nothing left to return' : '${_money.format(left)} can come back'} · TP ${it['TP'] ?? '-'}',
                style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
              ),
            ]),
          ),
          SizedBox(
            width: 92,
            child: TextField(
              controller: _qty[i],
              enabled: !done && !_saving,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              textAlign: TextAlign.center,
              decoration: const InputDecoration(labelText: 'Qty back'),
              onChanged: (_) => setState(() => _error = null),
            ),
          ),
        ]),
        if (!done && (double.tryParse(_qty[i].text.trim()) ?? 0) > 0) ...[
          const SizedBox(height: 10),
          SegmentedButton<ReturnCondition>(
            segments: const [
              ButtonSegment(value: ReturnCondition.good, label: Text('Good · back to stock'), icon: Icon(Icons.inventory_2_outlined, size: 16)),
              ButtonSegment(value: ReturnCondition.damaged, label: Text('Damaged'), icon: Icon(Icons.broken_image_outlined, size: 16)),
              ButtonSegment(value: ReturnCondition.expired, label: Text('Expired'), icon: Icon(Icons.event_busy_outlined, size: 16)),
            ],
            selected: {_cond[i]},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() => _cond[i] = s.first),
            style: SegmentedButton.styleFrom(
              selectedBackgroundColor: _cond[i].backToStock ? AppColors.greenBg : AppColors.amberBg,
              selectedForegroundColor: _cond[i].backToStock ? AppColors.green : AppColors.amberDark,
              side: const BorderSide(color: AppColors.border),
              visualDensity: VisualDensity.compact,
              textStyle: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ]),
    );
  }
}
