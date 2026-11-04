// Admin → Warehouses: the company's warehouses with what each holds, and which warehouse each
// booker sells from.
import 'package:flutter/material.dart';

import '../account/account.dart';
import '../crm/crm_ui.dart';
import 'inventory_data.dart';

class WarehousesScreen extends StatefulWidget {
  const WarehousesScreen({super.key});

  @override
  State<WarehousesScreen> createState() => _WarehousesScreenState();
}

class _WarehousesScreenState extends State<WarehousesScreen> {
  List<Warehouse>? _warehouses;
  ProductIndex? _products;
  List<AppUser> _bookers = [];
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final results = await Future.wait<Object>([
        loadWarehouses(fresh: true),
        loadProductIndex(fresh: true),
        loadCompanyUsers(fresh: true),
      ]);
      if (!mounted) return;
      setState(() {
        _warehouses = results[0] as List<Warehouse>;
        _products = results[1] as ProductIndex;
        _bookers = (results[2] as List<AppUser>).where((u) => u.role == Role.booker).toList();
      });
    } catch (e) {
      debugPrint('Warehouses: loading failed: $e');
      if (mounted) setState(() => _error = e);
    }
  }

  ({num units, num value}) _holding(String warehouseId) {
    num units = 0, value = 0;
    for (final p in _products?.all ?? const <StockProduct>[]) {
      if (p.stock == null) continue;
      final q = p.inWarehouse(warehouseId);
      units += q;
      if (q > 0) value += q * p.costPrice;
    }
    return (units: units, value: value);
  }

  Future<void> _edit([Warehouse? w]) async {
    final saved = await showDialog<bool>(context: context, builder: (_) => _WarehouseDialog(warehouse: w));
    if (saved == true) _load();
  }

  Future<void> _assign(AppUser booker, String warehouseId) async {
    try {
      await assignBookerWarehouse(booker.uid, warehouseId);
      if (mounted) crmSnack(context, '${booker.display} now sells from ${_name(warehouseId)}');
      _load();
    } catch (e) {
      debugPrint('Assigning warehouse failed: $e');
      if (mounted) crmSnack(context, "Couldn't save. Try again.", error: true);
    }
  }

  String _name(String id) => _warehouses?.where((w) => w.id == id).firstOrNull?.name ?? 'Main warehouse';

  @override
  Widget build(BuildContext context) {
    final warehouses = _warehouses;
    Widget body;
    if (warehouses == null) {
      body = Center(
        child: _error != null
            ? OutlinedButton(onPressed: _load, child: Text('Try again', style: CrmTokens.body(color: CrmTokens.navy)))
            : const CircularProgressIndicator(color: CrmTokens.navy),
      );
    } else {
      final active = warehouses.where((w) => w.active).toList();
      body = RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 96),
          children: [
            if (warehouses.length == 1)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  'All stock is in Main warehouse. Add another warehouse to keep stock in more than one place; '
                  'purchases, adjustments and sales will then ask or follow the booker\'s warehouse.',
                  style: CrmTokens.body(color: CrmTokens.muted),
                ),
              ),
            const CrmSectionTitle('Warehouses'),
            for (final w in warehouses) Padding(padding: const EdgeInsets.only(bottom: 8), child: _tile(w)),
            CrmSectionTitle('Bookers', trailing: Text('Sales come from their warehouse', style: CrmTokens.body(size: 12, color: CrmTokens.muted))),
            if (_bookers.isEmpty)
              const CrmEmpty(icon: Icons.people_outline, text: 'No bookers yet. Add them under Settings → Users.')
            else
              for (final b in _bookers)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: CrmCard(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                    child: Row(children: [
                      const Icon(Icons.person_outline, color: CrmTokens.navy),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(b.display, style: CrmTokens.body(w: FontWeight.w600)),
                          Text(b.email, style: CrmTokens.body(size: 12, color: CrmTokens.muted)),
                        ]),
                      ),
                      SizedBox(
                        width: 220,
                        child: DropdownButtonFormField<String>(
                          key: ValueKey('${b.uid}-${b.warehouseId}'),
                          initialValue: active.any((w) => w.id == b.warehouseId) ? b.warehouseId : mainWarehouseId,
                          isExpanded: true,
                          decoration: crmInput('Sells from'),
                          items: [
                            for (final w in active) DropdownMenuItem(value: w.id, child: Text(w.name, style: CrmTokens.body(), overflow: TextOverflow.ellipsis)),
                          ],
                          onChanged: (v) {
                            if (v != null && v != (b.warehouseId ?? mainWarehouseId)) _assign(b, v);
                          },
                        ),
                      ),
                    ]),
                  ),
                ),
          ],
        ),
      );
    }
    return Scaffold(
      backgroundColor: CrmTokens.bg,
      appBar: AppBar(
        backgroundColor: CrmTokens.navy,
        automaticallyImplyLeading: false,
        title: Text('Warehouses', style: CrmTokens.display(size: 18, color: Colors.white, w: FontWeight.w600)),
        actions: [IconButton(tooltip: 'Refresh', onPressed: _load, icon: const Icon(Icons.refresh, color: Colors.white))],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: CrmTokens.amber,
        foregroundColor: CrmTokens.navyDark,
        onPressed: () => _edit(),
        icon: const Icon(Icons.add_business_outlined),
        label: Text('Add warehouse', style: CrmTokens.body(size: 13, color: CrmTokens.navyDark, w: FontWeight.w700)),
      ),
      body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 900), child: body)),
    );
  }

  Widget _tile(Warehouse w) {
    final h = _holding(w.id);
    final bookers = _bookers.where((b) => (b.warehouseId ?? mainWarehouseId) == w.id).length;
    return CrmCard(
      onTap: () => _edit(w),
      padding: const EdgeInsets.all(14),
      child: Row(children: [
        CircleAvatar(
          backgroundColor: w.active ? CrmTokens.amberBg : CrmTokens.bg,
          child: Icon(Icons.warehouse_outlined, color: w.active ? CrmTokens.amber : CrmTokens.muted),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(child: Text(w.name, style: CrmTokens.body(size: 14.5, w: FontWeight.w700), overflow: TextOverflow.ellipsis)),
              if (w.id == mainWarehouseId) ...[const SizedBox(width: 8), const CrmPill('Main')],
              if (!w.active) ...[const SizedBox(width: 8), const CrmPill('Inactive', color: CrmTokens.muted)],
            ]),
            const SizedBox(height: 3),
            Text(
              [
                if (w.address.isNotEmpty) w.address,
                if (w.inCharge.isNotEmpty) 'In charge: ${w.inCharge}',
                '$bookers booker${bookers == 1 ? '' : 's'}',
              ].join('  ·  '),
              style: CrmTokens.body(size: 12, color: CrmTokens.muted),
            ),
          ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('${h.units == h.units.roundToDouble() ? h.units.toInt() : h.units} units', style: CrmTokens.body(w: FontWeight.w700)),
          Text(crmRs(h.value), style: CrmTokens.body(size: 12, color: CrmTokens.muted)),
        ]),
        const SizedBox(width: 4),
        const Icon(Icons.edit_outlined, size: 18, color: CrmTokens.muted),
      ]),
    );
  }
}

class _WarehouseDialog extends StatefulWidget {
  final Warehouse? warehouse;
  const _WarehouseDialog({this.warehouse});

  @override
  State<_WarehouseDialog> createState() => _WarehouseDialogState();
}

class _WarehouseDialogState extends State<_WarehouseDialog> {
  late final _name = TextEditingController(text: widget.warehouse?.name ?? '');
  late final _address = TextEditingController(text: widget.warehouse?.address ?? '');
  late final _inCharge = TextEditingController(text: widget.warehouse?.inCharge ?? '');
  late final _phone = TextEditingController(text: widget.warehouse?.phone ?? '');
  late bool _active = widget.warehouse?.active ?? true;
  bool _saving = false;
  String? _error;

  bool get _isMain => widget.warehouse?.id == mainWarehouseId;

  @override
  void dispose() {
    for (final c in [_name, _address, _inCharge, _phone]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return setState(() => _error = 'Enter a name');
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await saveWarehouse(Warehouse(
        id: widget.warehouse?.id ?? '',
        name: name,
        address: _address.text.trim(),
        inCharge: _inCharge.text.trim(),
        phone: _phone.text.trim(),
        active: _isMain || _active,
      ));
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      debugPrint('Saving warehouse failed: $e');
      if (mounted) {
        setState(() {
          _saving = false;
          _error = "Couldn't save. Try again.";
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.warehouse == null ? 'Add warehouse' : 'Edit ${widget.warehouse!.name}', style: CrmTokens.display(size: 17)),
      content: SizedBox(
        width: 400,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(controller: _name, autofocus: true, style: CrmTokens.body(), decoration: crmInput('Name *', icon: Icons.warehouse_outlined, hint: 'e.g. Shahfaisal godown')),
          const SizedBox(height: 10),
          TextField(controller: _address, style: CrmTokens.body(), decoration: crmInput('Address', icon: Icons.location_on_outlined)),
          const SizedBox(height: 10),
          TextField(controller: _inCharge, style: CrmTokens.body(), decoration: crmInput('Person in charge', icon: Icons.person_outline)),
          const SizedBox(height: 10),
          TextField(controller: _phone, keyboardType: TextInputType.phone, style: CrmTokens.body(), decoration: crmInput('Phone', icon: Icons.phone_outlined)),
          if (!_isMain)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _active,
              activeThumbColor: CrmTokens.amber,
              title: Text(_active ? 'Active' : 'Inactive', style: CrmTokens.body(w: FontWeight.w600)),
              subtitle: Text('Inactive warehouses are hidden from purchases, transfers and booker choices; their history stays.',
                  style: CrmTokens.body(size: 12, color: CrmTokens.muted)),
              onChanged: (v) => setState(() => _active = v),
            )
          else
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text('Main is always active: it holds stock from before warehouses existed.',
                  style: CrmTokens.body(size: 12, color: CrmTokens.muted)),
            ),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: CrmTokens.body(color: CrmTokens.red))),
        ]),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: Text('Cancel', style: CrmTokens.body())),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: CrmTokens.amber, elevation: 0),
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Saving…' : 'Save', style: CrmTokens.body(w: FontWeight.w700, color: CrmTokens.navyDark)),
        ),
      ],
    );
  }
}
