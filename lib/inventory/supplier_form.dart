// Adding or editing a supplier: business, money & terms, bank and notes. Only the name and phone
// are required; everything else can be filled in later.
import 'package:flutter/material.dart';
import 'package:an_agency/ui/app_theme.dart';
import 'package:flutter/services.dart';

import '../crm/crm_ui.dart';
import 'inventory_data.dart';

class SupplierForm extends StatefulWidget {
  /// The supplier to edit, or null to add a new one.
  final Supplier? supplier;

  /// Called after a successful save (the form clears itself when adding).
  final VoidCallback? onSaved;

  const SupplierForm({super.key, this.supplier, this.onSaved});

  @override
  State<SupplierForm> createState() => _SupplierFormState();
}

const _terms = {0: 'Cash on delivery', 7: '7 days credit', 15: '15 days credit', 30: '30 days credit', 45: '45 days credit', 60: '60 days credit'};

class _SupplierFormState extends State<SupplierForm> {
  final _formKey = GlobalKey<FormState>();
  final _c = <String, TextEditingController>{};
  String? _category;
  int _termsDays = 0;
  bool _active = true;
  bool _owedToThem = true; // which way the opening balance goes
  DateTime _openingDate = DateTime.now();
  bool _saving = false;

  bool get _editing => widget.supplier != null;

  TextEditingController _f(String key) => _c.putIfAbsent(key, TextEditingController.new);

  @override
  void initState() {
    super.initState();
    _fill(widget.supplier);
  }

  void _fill(Supplier? s) {
    _f('name').text = s?.name ?? '';
    _f('company').text = s?.company ?? '';
    _f('contact').text = s?.contact ?? '';
    _f('whatsapp').text = s?.whatsapp ?? '';
    _f('email').text = s?.email ?? '';
    _f('contactPerson').text = s?.contactPerson ?? '';
    _f('contactCnic').text = s?.contactCnic ?? '';
    _f('address').text = s?.address ?? '';
    _f('city').text = s?.city ?? '';
    _f('ntn').text = s?.ntn ?? '';
    _f('strn').text = s?.strn ?? '';
    _f('brands').text = s?.brands ?? '';
    _f('creditLimit').text = (s?.creditLimit ?? 0) > 0 ? '${s!.creditLimit}' : '';
    _f('opening').text = (s?.openingBalance ?? 0) != 0 ? '${s!.openingBalance.abs()}' : '';
    _f('bankName').text = s?.bankName ?? '';
    _f('accountTitle').text = s?.accountTitle ?? '';
    _f('iban').text = s?.iban ?? '';
    _f('notes').text = s?.notes ?? '';
    _category = s != null && supplierCategories.contains(s.category) ? s.category : null;
    _termsDays = s?.paymentTermsDays ?? 0;
    if (!_terms.containsKey(_termsDays)) _termsDays = 0;
    _active = s?.active ?? true;
    _owedToThem = (s?.openingBalance ?? 0) >= 0;
    _openingDate = s?.openingDate ?? DateTime.now();
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  String _t(String key) => _f(key).text.trim();

  Supplier _build() {
    final opening = num.tryParse(_t('opening')) ?? 0;
    return Supplier(
      id: widget.supplier?.id ?? '',
      name: _t('name'),
      company: _t('company'),
      contact: _t('contact'),
      whatsapp: _t('whatsapp'),
      email: _t('email'),
      contactPerson: _t('contactPerson'),
      contactCnic: _t('contactCnic'),
      address: _t('address'),
      city: _t('city'),
      ntn: _t('ntn'),
      strn: _t('strn'),
      category: _category ?? '',
      brands: _t('brands'),
      paymentTermsDays: _termsDays,
      creditLimit: num.tryParse(_t('creditLimit')) ?? 0,
      openingBalance: _owedToThem ? opening : -opening,
      openingDate: opening == 0 ? null : _openingDate,
      bankName: _t('bankName'),
      accountTitle: _t('accountTitle'),
      iban: _t('iban').toUpperCase().replaceAll(' ', ''),
      active: _active,
      notes: _t('notes'),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      crmSnack(context, 'Check the highlighted fields', error: true);
      return;
    }
    final s = _build();
    setState(() => _saving = true);
    try {
      final dup = await findDuplicateSupplier(name: s.name, ntn: s.ntn, exceptId: widget.supplier?.id);
      if (dup != null && mounted) {
        final same = dup.name.toLowerCase() == s.name.toLowerCase() ? 'name' : 'NTN';
        final go = await showDialog<bool>(
          context: context,
          builder: (d) => AlertDialog(
            title: Text('Possible duplicate', style: CrmTokens.display(size: 17)),
            content: Text(
              '"${dup.display}" already has this $same${dup.city.isEmpty ? '' : ' (${dup.city})'}. '
              'Saving creates a second supplier.\n\nSave anyway?',
              style: CrmTokens.body(),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(d, false), child: Text('Go back', style: CrmTokens.body())),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: CrmTokens.amber, elevation: 0),
                onPressed: () => Navigator.pop(d, true),
                child: Text('Save anyway', style: CrmTokens.body(w: FontWeight.w700, color: CrmTokens.navyDark)),
              ),
            ],
          ),
        );
        if (go != true) {
          if (mounted) setState(() => _saving = false);
          return;
        }
      }
      await saveSupplier(s, oldName: widget.supplier?.name);
      if (!mounted) return;
      crmSnack(context, _editing ? '${s.name} updated' : '${s.name} added');
      if (!_editing) {
        _formKey.currentState!.reset();
        _fill(null);
      }
      setState(() => _saving = false);
      widget.onSaved?.call();
    } catch (e) {
      debugPrint('Saving supplier failed: $e');
      if (!mounted) return;
      setState(() => _saving = false);
      crmSnack(context, "Couldn't save. Check your connection and try again.", error: true);
    }
  }

  // ------------------------------------------------------------------ fields

  Widget _field(
    String key,
    String label, {
    IconData? icon,
    String? hint,
    bool required = false,
    TextInputType? keyboard,
    int maxLines = 1,
    String? Function(String)? check,
    List<TextInputFormatter>? formatters,
  }) {
    return TextFormField(
      controller: _f(key),
      keyboardType: keyboard,
      maxLines: maxLines,
      inputFormatters: formatters,
      style: CrmTokens.body(size: 14),
      decoration: crmInput(required ? '$label *' : label, icon: icon, hint: hint),
      validator: (v) {
        final t = (v ?? '').trim();
        if (required && t.isEmpty) return 'Required';
        if (t.isEmpty) return null;
        return check?.call(t);
      },
    );
  }

  static String? _phone(String v) =>
      RegExp(r'^\+?[0-9 \-]{10,15}$').hasMatch(v) ? null : 'Enter a valid phone number';
  static String? _email(String v) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v) ? null : 'Enter a valid email';
  static String? _cnic(String v) =>
      RegExp(r'^[0-9]{5}-?[0-9]{7}-?[0-9]$').hasMatch(v) ? null : 'CNIC is 13 digits (12345-1234567-1)';
  static String? _iban(String v) =>
      RegExp(r'^[A-Za-z]{2}[0-9]{2}[A-Za-z0-9 ]{10,30}$').hasMatch(v) ? null : 'IBAN starts like PK36…';
  static String? _amount(String v) => (num.tryParse(v) ?? -1) >= 0 ? null : 'Enter an amount';
  static final _digits = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))];

  /// Two fields side by side on wide screens, stacked on phones.
  Widget _pair(Widget a, Widget b) => LayoutBuilder(
        builder: (_, c) => c.maxWidth < 560
            ? Column(children: [a, const SizedBox(height: 12), b])
            : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: a),
                const SizedBox(width: 12),
                Expanded(child: b),
              ]),
      );

  Widget _section(String title, String subtitle, List<Widget> children) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: CrmCard(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: CrmTokens.display(size: 15, color: CrmTokens.navy)),
            const SizedBox(height: 2),
            Text(subtitle, style: CrmTokens.body(size: 12, color: CrmTokens.muted)),
            const SizedBox(height: 14),
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              children[i],
            ],
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final opening = num.tryParse(_t('opening')) ?? 0;
    return Form(
      key: _formKey,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _section('Supplier', 'Who they are and how to reach them', [
          _pair(
            _field('name', 'Supplier name', icon: Icons.store_outlined, required: true),
            _field('company', 'Company (if different)', icon: Icons.business_outlined),
          ),
          _pair(
            _field('contact', 'Phone', icon: Icons.phone_outlined, required: true, keyboard: TextInputType.phone, check: _phone),
            _field('whatsapp', 'WhatsApp / second phone', icon: Icons.chat_outlined, keyboard: TextInputType.phone, check: _phone),
          ),
          _pair(
            _field('contactPerson', 'Contact person', icon: Icons.person_outline),
            _field('contactCnic', 'Contact person CNIC', icon: Icons.badge_outlined, hint: '12345-1234567-1', check: _cnic),
          ),
          _field('email', 'Email', icon: Icons.email_outlined, keyboard: TextInputType.emailAddress, check: _email),
        ]),
        _section('Business', 'Address, tax registration and what they supply', [
          _field('address', 'Address', icon: Icons.location_on_outlined, maxLines: 2),
          _pair(
            _field('city', 'City', icon: Icons.location_city_outlined),
            DropdownButtonFormField<String>(
              initialValue: _category,
              isExpanded: true,
              decoration: crmInput('Category', icon: Icons.category_outlined),
              items: [for (final c in supplierCategories) DropdownMenuItem(value: c, child: Text(c, style: CrmTokens.body()))],
              onChanged: (v) => setState(() => _category = v),
            ),
          ),
          _pair(
            _field('ntn', 'NTN', icon: Icons.receipt_long_outlined, hint: '1234567-8'),
            _field('strn', 'Sales tax reg. no. (STRN)', icon: Icons.receipt_outlined),
          ),
          _field('brands', 'Brands / products supplied', icon: Icons.sell_outlined, hint: 'e.g. Dollar, Piano, Picasso'),
        ]),
        _section('Money & terms', 'Used by Purchases: what you owe them and when it is due', [
          _pair(
            DropdownButtonFormField<int>(
              initialValue: _termsDays,
              isExpanded: true,
              decoration: crmInput('Payment terms', icon: Icons.schedule_outlined),
              items: [for (final e in _terms.entries) DropdownMenuItem(value: e.key, child: Text(e.value, style: CrmTokens.body()))],
              onChanged: (v) => setState(() => _termsDays = v ?? 0),
            ),
            _field('creditLimit', 'Credit limit (Rs.)', icon: Icons.speed_outlined, hint: 'Leave empty for no limit',
                keyboard: TextInputType.number, check: _amount, formatters: _digits),
          ),
          _pair(
            TextFormField(
              controller: _f('opening'),
              keyboardType: TextInputType.number,
              inputFormatters: _digits,
              onChanged: (_) => setState(() {}),
              style: CrmTokens.body(size: 14),
              decoration: crmInput('Opening balance (Rs.)', icon: Icons.account_balance_wallet_outlined, hint: 'Already owed today'),
              validator: (v) => (v ?? '').trim().isEmpty ? null : _amount(v!.trim()),
            ),
            InkWell(
              onTap: opening == 0
                  ? null
                  : () async {
                      final d = await showDatePicker(context: context, initialDate: _openingDate, firstDate: DateTime(2015), lastDate: DateTime.now());
                      if (d != null) setState(() => _openingDate = d);
                    },
              child: InputDecorator(
                decoration: crmInput('As of', icon: Icons.calendar_today_outlined),
                child: Text(opening == 0 ? '—' : crmDay.format(_openingDate),
                    style: CrmTokens.body(color: opening == 0 ? CrmTokens.muted : null)),
              ),
            ),
          ),
          if (opening != 0)
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('We owe them'), icon: Icon(Icons.call_made, size: 16)),
                ButtonSegment(value: false, label: Text('They owe us'), icon: Icon(Icons.call_received, size: 16)),
              ],
              selected: {_owedToThem},
              onSelectionChanged: (v) => setState(() => _owedToThem = v.first),
            ),
          if (_editing && (widget.supplier!.openingBalance != 0))
            Text('Changing the opening balance changes their balance in Purchases.',
                style: CrmTokens.body(size: 12, color: CrmTokens.muted)),
        ]),
        _section('Bank', 'Where to send payments', [
          _pair(
            _field('bankName', 'Bank', icon: Icons.account_balance_outlined),
            _field('accountTitle', 'Account title', icon: Icons.person_pin_outlined),
          ),
          _field('iban', 'IBAN', icon: Icons.numbers, hint: 'PK36SCBL0000001123456702', check: _iban),
        ]),
        _section('Other', 'Status and notes', [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _active,
            title: Text(_active ? 'Active' : 'Inactive', style: CrmTokens.body(size: 14, w: FontWeight.w600)),
            subtitle: Text(
              _active ? 'Offered when adding products and purchases' : 'Hidden from new products and purchases; history is kept',
              style: CrmTokens.body(size: 12, color: CrmTokens.muted),
            ),
            onChanged: (v) => setState(() => _active = v),
          ),
          _field('notes', 'Notes', icon: Icons.notes_outlined, maxLines: 3),
        ]),
        SizedBox(
          height: 50,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: CrmTokens.amber,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: CrmTokens.navyDark))
                : const Icon(Icons.save_outlined, color: CrmTokens.navyDark),
            label: Text(_saving ? 'Saving…' : (_editing ? 'Save changes' : 'Save supplier'),
                style: CrmTokens.body(size: 15, w: FontWeight.w700, color: CrmTokens.navyDark)),
          ),
        ),
      ]),
    );
  }
}

/// Editing one supplier, with Delete (only when it has no history).
class EditSupplierScreen extends StatelessWidget {
  final Supplier supplier;
  const EditSupplierScreen({super.key, required this.supplier});

  Future<void> _delete(BuildContext context) async {
    final String? blocker;
    try {
      blocker = await supplierDeleteBlocker(supplier);
    } catch (_) {
      if (context.mounted) crmSnack(context, "Couldn't check. Try again.", error: true);
      return;
    }
    if (!context.mounted) return;
    if (blocker != null) {
      await showDialog<void>(
        context: context,
        builder: (d) => AlertDialog(
          title: Text("Can't delete ${supplier.name}", style: CrmTokens.display(size: 17)),
          content: Text('$blocker Deleting it would lose that history.\n\nSwitch it to Inactive instead: it disappears '
              'from new products and purchases, and its history stays.', style: CrmTokens.body()),
          actions: [TextButton(onPressed: () => Navigator.pop(d), child: Text('OK', style: CrmTokens.body()))],
        ),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('Delete ${supplier.name}?', style: CrmTokens.display(size: 17)),
        content: Text('It has no bills, payments or products, so nothing else changes.', style: CrmTokens.body()),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: Text('Cancel', style: CrmTokens.body())),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: CrmTokens.red, elevation: 0),
            onPressed: () => Navigator.pop(d, true),
            child: Text('Delete', style: CrmTokens.body(color: Colors.white, w: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await deleteSupplier(supplier);
      if (context.mounted) Navigator.pop(context, true);
    } catch (_) {
      if (context.mounted) crmSnack(context, "Couldn't delete. Try again.", error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CrmTokens.bg,
      appBar: AppBar(
        title: Text('Edit ${supplier.name}', style: CrmTokens.display(size: 18, color: AppColors.text, w: FontWeight.w600)),
        actions: [
          IconButton(
            tooltip: 'Delete supplier',
            onPressed: () => _delete(context),
            icon: const Icon(Icons.delete_outline, color: AppColors.text),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: SupplierForm(supplier: supplier, onSaved: () => Navigator.pop(context, true)),
          ),
        ),
      ),
    );
  }
}
