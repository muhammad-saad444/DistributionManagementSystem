// Settings → Company details & sales tax (admins): what every invoice prints at the top and bottom,
// and whether invoices carry sales tax, at what rate, and whether prices already include it.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/widgets.dart' as pw;

import '../print_preview.dart';
import '../ui/app_theme.dart';
import '../ui/kpi_card.dart';
import 'company_profile.dart';
import 'invoice_pdf.dart';

class CompanyProfileScreen extends StatefulWidget {
  const CompanyProfileScreen({super.key});

  @override
  State<CompanyProfileScreen> createState() => _CompanyProfileScreenState();
}

class _CompanyProfileScreenState extends State<CompanyProfileScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _address = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _ntn = TextEditingController();
  final _strn = TextEditingController();
  final _note = TextEditingController();
  final _rate = TextEditingController();
  bool _taxOn = false;
  bool _inclusive = true;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    loadCompanyProfile(fresh: true).then((p) {
      if (!mounted) return;
      setState(() {
        _name.text = p.legalName;
        _address.text = p.address;
        _phone.text = p.phone;
        _email.text = p.email;
        _ntn.text = p.ntn;
        _strn.text = p.strn;
        _note.text = p.invoiceNote;
        _rate.text = p.taxRate == p.taxRate.roundToDouble() ? p.taxRate.toInt().toString() : '${p.taxRate}';
        _taxOn = p.taxEnabled;
        _inclusive = p.taxInclusive;
        _loading = false;
      });
    });
  }

  @override
  void dispose() {
    for (final c in [_name, _address, _phone, _email, _ntn, _strn, _note, _rate]) {
      c.dispose();
    }
    super.dispose();
  }

  CompanyProfile get _profile => CompanyProfile(
        legalName: _name.text,
        address: _address.text,
        phone: _phone.text,
        email: _email.text,
        ntn: _ntn.text,
        strn: _strn.text,
        invoiceNote: _note.text,
        taxEnabled: _taxOn,
        taxRate: double.tryParse(_rate.text.trim()) ?? 18,
        taxInclusive: _inclusive,
      );

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await saveCompanyProfile(_profile);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved. New invoices use these details.')));
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Couldn't save: $e")));
    }
  }

  /// A made-up invoice with these settings, to see how it prints.
  Future<void> _preview() {
    final p = _profile;
    final items = [
      {'Product Name': 'Sample soap 100g', 'Size': 'Carton', 'QTY': '10', 'BNS': '1', 'TP': '1200'},
      {'Product Name': 'Sample tea 500g', 'Size': 'Pack', 'QTY': '24', 'TP': '450'},
    ];
    const net = 12000.0 + 24 * 450 - 500;
    final invoice = <String, dynamic>{
      'invoiceNumber': '123',
      'salesDate': '13-11-2026',
      'customer': 'Sample General Store',
      'area': 'Main Bazaar',
      'items': items,
      'discountType': 'pkr',
      'discountValue': 500,
      'grandTotal': net,
      ...p.taxFieldsFor(items, net),
    };
    return showPrintPreview(
      context,
      title: 'Sample invoice',
      fileName: 'sample-invoice.pdf',
      buildPdf: () {
        final doc = pw.Document();
        doc.addPage(invoicePdfPage(invoice,
            profile: p,
            buyer: const Buyer(address: 'Shop 4, Main Bazaar', contact: '0300 1234567', ntn: '1234567-8'),
            booker: 'booker@company.com'));
        return doc.save();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Company details & sales tax'),
        actions: [
          TextButton.icon(onPressed: _loading ? null : _preview, icon: const Icon(Icons.visibility_outlined, size: 18), label: const Text('Preview')),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _form,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 100),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 760),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        _panel(
                          icon: Icons.business_outlined,
                          title: 'On every invoice',
                          note: 'Printed at the top of invoices, for the office and bookers alike.',
                          children: [
                            _field(_name, 'Company name on invoices', hint: 'As registered, e.g. A.N Agency (Pvt) Ltd'),
                            _field(_address, 'Address', lines: 2),
                            _pair(_field(_phone, 'Phone', keyboard: TextInputType.phone), _field(_email, 'Email', keyboard: TextInputType.emailAddress)),
                            _pair(_field(_ntn, 'NTN'), _field(_strn, 'Sales tax registration (STRN)')),
                            _field(_note, 'Note at the bottom', lines: 3, hint: 'Terms, bank account for payments, "Goods once sold..."'),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _panel(
                          icon: Icons.percent,
                          title: 'Sales tax',
                          note: 'New invoices keep the rate they were made with; changing it later doesn\'t change old invoices.',
                          children: [
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              value: _taxOn,
                              onChanged: (v) => setState(() => _taxOn = v),
                              title: const Text('Show sales tax on invoices'),
                              subtitle: const Text('The invoice becomes a "Sales tax invoice" with the tax worked out.'),
                            ),
                            if (_taxOn) ...[
                              const SizedBox(height: 6),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: SizedBox(
                                width: 180,
                                child: TextFormField(
                                  controller: _rate,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                                  decoration: const InputDecoration(labelText: 'Rate', suffixText: '%'),
                                  validator: (v) {
                                    final r = double.tryParse((v ?? '').trim());
                                    return r == null || r < 0 || r > 100 ? 'Enter a rate from 0 to 100' : null;
                                  },
                                ),
                              ),
                              ),
                              const SizedBox(height: 12),
                              RadioGroup<bool>(
                                groupValue: _inclusive,
                                onChanged: (v) => setState(() => _inclusive = v ?? true),
                                child: const Column(children: [
                                  RadioListTile<bool>(
                                    contentPadding: EdgeInsets.zero,
                                    value: true,
                                    title: Text('My prices already include sales tax'),
                                    subtitle: Text('Bills stay the same; the invoice shows how much of it is tax.'),
                                  ),
                                  RadioListTile<bool>(
                                    contentPadding: EdgeInsets.zero,
                                    value: false,
                                    title: Text('Add sales tax on top of my prices'),
                                    subtitle: Text('Bills go up by the tax; shops owe the total with tax.'),
                                  ),
                                ]),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'A product can have its own rate (e.g. exempt): set it on the product, under Sales tax.',
                                style: TextStyle(fontSize: 12, color: AppColors.muted),
                              ),
                            ],
                          ],
                        ),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
      bottomNavigationBar: _loading
          ? null
          : SafeArea(
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: AppColors.border))),
                child: Center(
                  heightFactor: 1,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: Row(children: [
                      const Expanded(child: SizedBox()),
                      OutlinedButton(onPressed: _preview, child: const Text('Preview invoice')),
                      const SizedBox(width: 10),
                      FilledButton(
                        onPressed: _saving ? null : _save,
                        child: _saving
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Text('Save'),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _panel({required IconData icon, required String title, required String note, required List<Widget> children}) => Container(
        decoration: kpiCardDecoration(),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: AppColors.brandSoft, borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, size: 16, color: AppColors.navy),
            ),
            const SizedBox(width: 10),
            Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.text)),
          ]),
          const SizedBox(height: 4),
          Text(note, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
          const SizedBox(height: 14),
          ...children,
        ]),
      );

  Widget _field(TextEditingController c, String label, {String? hint, int lines = 1, TextInputType? keyboard}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
          controller: c,
          maxLines: lines,
          minLines: 1,
          keyboardType: keyboard,
          decoration: InputDecoration(labelText: label, hintText: hint),
        ),
      );

  Widget _pair(Widget a, Widget b) => LayoutBuilder(
        builder: (context, box) => box.maxWidth < 520
            ? Column(children: [a, b])
            : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: a), const SizedBox(width: 12), Expanded(child: b)]),
      );
}
