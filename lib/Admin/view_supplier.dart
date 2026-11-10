import 'package:flutter/material.dart';
import 'package:an_agency/ui/app_theme.dart';

import '../crm/crm_ui.dart';
import '../inventory/inventory_data.dart';
import '../inventory/supplier_form.dart';

/// All suppliers: search, show inactive ones, and tap to edit.
class ViewSuppliersScreen extends StatefulWidget {
  const ViewSuppliersScreen({super.key});

  @override
  State<ViewSuppliersScreen> createState() => _ViewSuppliersScreenState();
}

class _ViewSuppliersScreenState extends State<ViewSuppliersScreen> {
  final _search = TextEditingController();
  List<Supplier>? _suppliers;
  Object? _error;
  bool _showInactive = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final s = await loadSuppliers();
      if (mounted) setState(() => _suppliers = s);
    } catch (e) {
      debugPrint('Loading suppliers failed: $e');
      if (mounted) setState(() => _error = e);
    }
  }

  List<Supplier> get _visible {
    final q = _search.text.trim().toLowerCase();
    return (_suppliers ?? const <Supplier>[]).where((s) {
      if (!_showInactive && !s.active) return false;
      if (q.isEmpty) return true;
      return [s.name, s.company, s.city, s.contact, s.ntn, s.brands, s.contactPerson]
          .any((f) => f.toLowerCase().contains(q));
    }).toList();
  }

  Future<void> _edit(Supplier s) async {
    final changed = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => EditSupplierScreen(supplier: s)));
    if (changed == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final all = _suppliers;
    final inactive = all?.where((s) => !s.active).length ?? 0;
    Widget body;
    if (all == null) {
      body = Center(
        child: _error != null
            ? OutlinedButton(onPressed: _load, child: Text('Try again', style: CrmTokens.body(color: CrmTokens.navy)))
            : const CircularProgressIndicator(color: CrmTokens.navy),
      );
    } else {
      final list = _visible;
      body = RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
          children: [
            TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              style: CrmTokens.body(size: 14),
              decoration: crmInput('Search name, city, phone, NTN or brand', icon: Icons.search),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: Text('${list.length} supplier${list.length == 1 ? '' : 's'}',
                    style: CrmTokens.body(size: 12, color: CrmTokens.muted)),
              ),
              if (inactive > 0)
                FilterChip(
                  label: Text('Show inactive ($inactive)', style: CrmTokens.body(size: 12)),
                  selected: _showInactive,
                  onSelected: (v) => setState(() => _showInactive = v),
                ),
            ]),
            const SizedBox(height: 8),
            if (list.isEmpty)
              const CrmEmpty(icon: Icons.store_outlined, text: 'No suppliers found. Try a different search, or add one.')
            else
              for (final s in list) Padding(padding: const EdgeInsets.only(bottom: 8), child: _tile(s)),
          ],
        ),
      );
    }
    return Scaffold(
      backgroundColor: CrmTokens.bg,
      appBar: AppBar(
        title: Text('All Suppliers', style: CrmTokens.display(size: 18, color: AppColors.text, w: FontWeight.w600)),
      ),
      body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 900), child: body)),
    );
  }

  Widget _tile(Supplier s) {
    final details = [
      if (s.city.isNotEmpty) s.city,
      if (s.category.isNotEmpty) s.category,
      s.termsLabel,
      if (s.ntn.isNotEmpty) 'NTN ${s.ntn}',
    ].join('  ·  ');
    return CrmCard(
      onTap: () => _edit(s),
      padding: const EdgeInsets.all(14),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: s.active ? CrmTokens.amberBg : CrmTokens.bg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(Icons.store_outlined, color: s.active ? CrmTokens.amber : CrmTokens.muted, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(child: Text(s.display, style: CrmTokens.body(size: 14.5, w: FontWeight.w700), overflow: TextOverflow.ellipsis)),
              if (!s.active) ...[
                const SizedBox(width: 8),
                const CrmPill('Inactive', color: CrmTokens.muted),
              ],
            ]),
            const SizedBox(height: 3),
            Text(details, style: CrmTokens.body(size: 12, color: CrmTokens.muted)),
            const SizedBox(height: 6),
            Wrap(spacing: 14, runSpacing: 4, children: [
              if (s.contact.isNotEmpty) _meta(Icons.phone_outlined, s.contact),
              if (s.contactPerson.isNotEmpty) _meta(Icons.person_outline, s.contactPerson),
              if (s.openingBalance != 0) _meta(Icons.account_balance_wallet_outlined, 'Opening ${crmRs(s.openingBalance)}'),
            ]),
          ]),
        ),
        const Icon(Icons.edit_outlined, color: CrmTokens.muted, size: 20),
      ]),
    );
  }

  Widget _meta(IconData icon, String text) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: CrmTokens.navy),
        const SizedBox(width: 4),
        Text(text, style: CrmTokens.body(size: 12.5)),
      ]);
}
