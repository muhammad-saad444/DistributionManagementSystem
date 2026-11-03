// Bottom sheets for the booker's CRM actions. Each returns true when something was saved.
import 'package:flutter/material.dart';

import '../khata.dart';
import 'crm_data.dart';
import 'crm_ui.dart';

Future<bool?> _sheet(BuildContext context, Widget child) => showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
        child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 20), child: child),
      ),
    );

Widget _handle(String title, String subtitle) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(color: CrmTokens.border, borderRadius: BorderRadius.circular(4)),
          ),
        ),
        Text(title, style: CrmTokens.display(size: 17)),
        const SizedBox(height: 2),
        Text(subtitle, style: CrmTokens.body(color: CrmTokens.muted)),
        const SizedBox(height: 16),
      ],
    );

Widget _saveButton({required String label, required bool saving, required VoidCallback onPressed}) => SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: CrmTokens.navy,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        onPressed: saving ? null : onPressed,
        child: saving
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : Text(label, style: CrmTokens.body(size: 14, color: Colors.white, w: FontWeight.w600)),
      ),
    );

Future<DateTime?> _pickDate(BuildContext context, DateTime initial, {bool future = false}) {
  final now = DateTime.now();
  return showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: future ? DateTime(now.year, now.month, now.day) : DateTime(now.year - 2),
    lastDate: future ? DateTime(now.year + 2) : now,
  );
}

Widget _dateField(BuildContext context, String label, DateTime value, VoidCallback onTap) => InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: InputDecorator(
        decoration: crmInput(label, icon: Icons.event_outlined),
        child: Text(crmDay.format(value), style: CrmTokens.body(size: 14)),
      ),
    );

// =============================================================================
// Log visit
// =============================================================================

/// Logs a visit or call. Picking "Payment collected" with an amount also adds the payment to the khata.
Future<bool?> showLogVisitSheet(BuildContext context, CrmCustomer customer) =>
    _sheet(context, _LogVisitSheet(customer: customer));

class _LogVisitSheet extends StatefulWidget {
  final CrmCustomer customer;
  const _LogVisitSheet({required this.customer});

  @override
  State<_LogVisitSheet> createState() => _LogVisitSheetState();
}

class _LogVisitSheetState extends State<_LogVisitSheet> {
  VisitOutcome _outcome = VisitOutcome.order;
  DateTime _date = DateTime.now();
  final _note = TextEditingController();
  final _amount = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _note.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amount.text.replaceAll(',', '').trim()) ?? 0;
    setState(() => _saving = true);
    try {
      final now = DateTime.now();
      // keep the time when logging for today so same-day visits stay in order
      final date = daysSince(_date) == 0 ? now : DateTime(_date.year, _date.month, _date.day, 12);
      await logVisit(customer: widget.customer, outcome: _outcome, date: date, note: _note.text);
      if (_outcome == VisitOutcome.payment && amount > 0) {
        await addKhataEntry(
          customer: widget.customer.name,
          type: 'payment',
          amount: amount,
          date: _date,
          method: 'Cash',
          note: _note.text.trim().isEmpty ? 'Collected on visit' : _note.text,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      crmSnack(context, "Couldn't save the visit. Check your connection and try again.", error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPayment = _outcome == VisitOutcome.payment;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _handle('Log visit', widget.customer.name),
        Text('Outcome', style: CrmTokens.body(size: 12, color: CrmTokens.muted, w: FontWeight.w600)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: VisitOutcome.all.map((o) {
            final selected = o == _outcome;
            final (fg, bg) = outcomeColors(o);
            return ChoiceChip(
              selected: selected,
              showCheckmark: false,
              avatar: Icon(outcomeIcon(o), size: 16, color: selected ? fg : CrmTokens.muted),
              label: Text(o.label),
              labelStyle: CrmTokens.body(size: 12, color: selected ? fg : CrmTokens.textDark, w: FontWeight.w600),
              selectedColor: bg == CrmTokens.bg ? CrmTokens.amberBg : bg,
              backgroundColor: Colors.white,
              side: BorderSide(color: selected ? fg : CrmTokens.border),
              onSelected: (_) => setState(() => _outcome = o),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        _dateField(context, 'Date', _date, () async {
          final d = await _pickDate(context, _date);
          if (d != null) setState(() => _date = d);
        }),
        if (isPayment) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: crmInput('Amount collected (optional)', icon: Icons.payments_outlined),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text(
              widget.customer.isOwing
                  ? 'Balance due ${crmRs(widget.customer.balance)}. An amount here is also added to the khata as a cash payment.'
                  : 'An amount here is also added to the khata as a cash payment.',
              style: CrmTokens.body(size: 11, color: CrmTokens.muted),
            ),
          ),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: _note,
          maxLines: 3,
          minLines: 2,
          textCapitalization: TextCapitalization.sentences,
          decoration: crmInput('Note (optional)', hint: 'What happened, what they asked for…'),
        ),
        const SizedBox(height: 18),
        _saveButton(label: 'Save visit', saving: _saving, onPressed: _save),
      ],
    );
  }
}

// =============================================================================
// Follow-up
// =============================================================================

Future<bool?> showFollowUpSheet(BuildContext context, CrmCustomer customer) =>
    _sheet(context, _FollowUpSheet(customer: customer));

class _FollowUpSheet extends StatefulWidget {
  final CrmCustomer customer;
  const _FollowUpSheet({required this.customer});

  @override
  State<_FollowUpSheet> createState() => _FollowUpSheetState();
}

class _FollowUpSheetState extends State<_FollowUpSheet> {
  final _title = TextEditingController();
  final _note = TextEditingController();
  DateTime _due = DateTime.now().add(const Duration(days: 1));
  bool _saving = false;

  List<String> get _suggestions => [
        if (widget.customer.isOwing) 'Collect payment (${crmRs(widget.customer.balance)})',
        'Take order',
        'Call shop',
        'Show new products',
        'Resolve complaint',
      ];

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      crmSnack(context, 'Write what needs to be done', error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      await addFollowUp(customer: widget.customer, title: _title.text, dueDate: _due, note: _note.text);
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      crmSnack(context, "Couldn't save the follow-up. Try again.", error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final quick = <String, DateTime>{
      'Tomorrow': now.add(const Duration(days: 1)),
      'In 3 days': now.add(const Duration(days: 3)),
      'Next week': now.add(const Duration(days: 7)),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _handle('New follow-up', widget.customer.name),
        TextField(
          controller: _title,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: crmInput('What to do', icon: Icons.task_alt),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: _suggestions
              .map((s) => ActionChip(
                    label: Text(s, style: CrmTokens.body(size: 11)),
                    backgroundColor: CrmTokens.bg,
                    side: BorderSide.none,
                    onPressed: () => setState(() => _title.text = s),
                  ))
              .toList(),
        ),
        const SizedBox(height: 14),
        _dateField(context, 'Due date', _due, () async {
          final d = await _pickDate(context, _due, future: true);
          if (d != null) setState(() => _due = d);
        }),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          children: quick.entries
              .map((e) => ChoiceChip(
                    label: Text(e.key, style: CrmTokens.body(size: 11)),
                    selected: daysSince(e.value) == daysSince(_due),
                    selectedColor: CrmTokens.amberBg,
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _due = e.value),
                  ))
              .toList(),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _note,
          maxLines: 2,
          textCapitalization: TextCapitalization.sentences,
          decoration: crmInput('Note (optional)'),
        ),
        const SizedBox(height: 18),
        _saveButton(label: 'Save follow-up', saving: _saving, onPressed: _save),
      ],
    );
  }
}

// =============================================================================
// Tags and notes
// =============================================================================

const suggestedTags = ['VIP', 'Slow payer', 'Cash only', 'High volume', 'New shop', 'At risk'];

Future<bool?> showTagsSheet(BuildContext context, CrmCustomer customer, List<String> knownTags) =>
    _sheet(context, _TagsSheet(customer: customer, knownTags: knownTags));

class _TagsSheet extends StatefulWidget {
  final CrmCustomer customer;
  final List<String> knownTags;
  const _TagsSheet({required this.customer, required this.knownTags});

  @override
  State<_TagsSheet> createState() => _TagsSheetState();
}

class _TagsSheetState extends State<_TagsSheet> {
  late final Set<String> _tags = {...widget.customer.tags};
  final _newTag = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _newTag.dispose();
    super.dispose();
  }

  void _add() {
    final t = _newTag.text.trim();
    if (t.isEmpty) return;
    setState(() {
      _tags.add(t);
      _newTag.clear();
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await updateCustomerCrm(widget.customer.id, tags: _tags.toList()..sort());
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      crmSnack(context, "Couldn't save tags. Try again.", error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final options = {...suggestedTags, ...widget.knownTags, ..._tags}.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _handle('Tags', 'Group shops so you can filter them later'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: options
              .map((t) => FilterChip(
                    label: Text(t, style: CrmTokens.body(size: 12, w: FontWeight.w600)),
                    selected: _tags.contains(t),
                    selectedColor: CrmTokens.amberBg,
                    checkmarkColor: CrmTokens.navy,
                    backgroundColor: Colors.white,
                    side: BorderSide(color: _tags.contains(t) ? CrmTokens.amber : CrmTokens.border),
                    onSelected: (on) => setState(() => on ? _tags.add(t) : _tags.remove(t)),
                  ))
              .toList(),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _newTag,
                textCapitalization: TextCapitalization.words,
                decoration: crmInput('New tag', icon: Icons.sell_outlined),
                onSubmitted: (_) => _add(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(onPressed: _add, icon: const Icon(Icons.add)),
          ],
        ),
        const SizedBox(height: 18),
        _saveButton(label: 'Save tags', saving: _saving, onPressed: _save),
      ],
    );
  }
}

Future<bool?> showNotesSheet(BuildContext context, CrmCustomer customer) =>
    _sheet(context, _NotesSheet(customer: customer));

class _NotesSheet extends StatefulWidget {
  final CrmCustomer customer;
  const _NotesSheet({required this.customer});

  @override
  State<_NotesSheet> createState() => _NotesSheetState();
}

class _NotesSheetState extends State<_NotesSheet> {
  late final _notes = TextEditingController(text: widget.customer.notes);
  bool _saving = false;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await updateCustomerCrm(widget.customer.id, notes: _notes.text);
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      crmSnack(context, "Couldn't save notes. Try again.", error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _handle('Notes', widget.customer.name),
        TextField(
          controller: _notes,
          autofocus: true,
          minLines: 5,
          maxLines: 10,
          textCapitalization: TextCapitalization.sentences,
          decoration: crmInput('Notes', hint: 'Owner name, best time to visit, preferred products…'),
        ),
        const SizedBox(height: 18),
        _saveButton(label: 'Save notes', saving: _saving, onPressed: _save),
      ],
    );
  }
}
