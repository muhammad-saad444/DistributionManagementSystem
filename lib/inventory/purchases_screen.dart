// Admin → Purchases: supplier bills and returns, what is owed to each supplier, and profit.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../crm/crm_ui.dart';
import 'inventory_data.dart';
import 'purchase_form.dart';
import 'quotations_screen.dart';

class AdminPurchasesScreen extends StatefulWidget {
  const AdminPurchasesScreen({super.key});

  @override
  State<AdminPurchasesScreen> createState() => _AdminPurchasesScreenState();
}

class _AdminPurchasesScreenState extends State<AdminPurchasesScreen> {
  PayablesBook? _book;
  Object? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final book = await loadPayables();
      if (mounted) setState(() => _book = book);
    } catch (e) {
      debugPrint('Purchases: loading failed: $e');
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _newPurchase({bool isReturn = false, Supplier? supplier}) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => PurchaseFormScreen(isReturn: isReturn, supplier: supplier)),
    );
    if (saved == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        backgroundColor: CrmTokens.bg,
        appBar: AppBar(
          backgroundColor: CrmTokens.navy,
          elevation: 0,
          automaticallyImplyLeading: false,
          title: Text('Purchases', style: CrmTokens.display(size: 18, color: Colors.white, w: FontWeight.w600)),
          actions: [
            IconButton(
              tooltip: 'Refresh',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh, color: Colors.white),
            ),
          ],
          bottom: TabBar(
            indicatorColor: CrmTokens.amber,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            labelStyle: CrmTokens.body(w: FontWeight.w600, color: Colors.white),
            isScrollable: false,
            tabs: const [Tab(text: 'Bills'), Tab(text: 'Quotations'), Tab(text: 'Suppliers'), Tab(text: 'Profit')],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: CrmTokens.amber,
          foregroundColor: CrmTokens.navyDark,
          onPressed: () => _newPurchase(),
          icon: const Icon(Icons.add_shopping_cart),
          label: Text('New purchase', style: CrmTokens.body(size: 13, color: CrmTokens.navyDark, w: FontWeight.w700)),
        ),
        body: Column(
          children: [
            if (_loading && _book != null) const LinearProgressIndicator(minHeight: 2, color: CrmTokens.amber),
            Expanded(
              child: TabBarView(children: [
                _guard((b) => _BillsTab(book: b, onChanged: _load, onReturn: () => _newPurchase(isReturn: true))),
                QuotationsTab(onPurchased: _load),
                _guard((b) => _SuppliersTab(book: b, onChanged: _load)),
                const ProfitTab(),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _guard(Widget Function(PayablesBook) child) {
    final book = _book;
    if (book != null) return child(book);
    if (_error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const CrmEmpty(icon: Icons.cloud_off, text: "Couldn't load purchases. Check your connection."),
          OutlinedButton(onPressed: _load, child: Text('Try again', style: CrmTokens.body(color: CrmTokens.navy))),
        ]),
      );
    }
    return const Center(child: CircularProgressIndicator(color: CrmTokens.navy));
  }
}

// -----------------------------------------------------------------------------
// Bills
// -----------------------------------------------------------------------------

class _BillsTab extends StatelessWidget {
  final PayablesBook book;
  final VoidCallback onChanged;
  final VoidCallback onReturn;
  const _BillsTab({required this.book, required this.onChanged, required this.onReturn});

  @override
  Widget build(BuildContext context) {
    final month = DateTime(DateTime.now().year, DateTime.now().month);
    final thisMonth = book.purchases.where((p) => !p.date.isBefore(month));
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 96),
      children: [
        Row(children: [
          Expanded(child: CrmStat(label: 'Owed to suppliers', value: crmRs(book.totalPayable), color: CrmTokens.red)),
          const SizedBox(width: 8),
          Expanded(
            child: CrmStat(
              label: 'Bought this month',
              value: crmRs(thisMonth.fold<num>(0, (s, p) => s + p.payableEffect)),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: onReturn,
            icon: const Icon(Icons.assignment_return_outlined, color: CrmTokens.navy, size: 18),
            label: Text('Return goods to supplier', style: CrmTokens.body(color: CrmTokens.navy, w: FontWeight.w600)),
          ),
        ),
        const CrmSectionTitle('Bills and returns'),
        if (book.purchases.isEmpty)
          const CrmEmpty(icon: Icons.receipt_long_outlined, text: 'No purchases yet. Tap New purchase when stock arrives from a supplier.')
        else
          for (final p in book.purchases)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: PurchaseTile(purchase: p, onChanged: onChanged),
            ),
      ],
    );
  }
}

class PurchaseTile extends StatelessWidget {
  final Purchase purchase;
  final VoidCallback onChanged;
  const PurchaseTile({super.key, required this.purchase, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final p = purchase;
    return CrmCard(
      onTap: () => _showPurchase(context, p, onChanged),
      padding: const EdgeInsets.all(12),
      child: Row(children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: p.isReturn ? CrmTokens.redBg : CrmTokens.greenBg,
          child: Icon(p.isReturn ? Icons.assignment_return_outlined : Icons.inventory_2_outlined,
              size: 18, color: p.isReturn ? CrmTokens.red : CrmTokens.green),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p.supplierName, style: CrmTokens.body(size: 14, w: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(
              [
                crmDay.format(p.date),
                if (p.billNo.isNotEmpty) (p.isReturn ? 'Return ${p.billNo}' : 'Bill ${p.billNo}') else if (p.isReturn) 'Return',
                '${p.lines.length} product${p.lines.length == 1 ? '' : 's'}',
                '${_qty(p.units)} units',
              ].join('  ·  '),
              style: CrmTokens.body(size: 12, color: CrmTokens.muted),
            ),
          ]),
        ),
        Text('${p.isReturn ? '−' : ''}${crmRs(p.total)}',
            style: CrmTokens.body(size: 14, w: FontWeight.w700, color: p.isReturn ? CrmTokens.red : CrmTokens.navy)),
      ]),
    );
  }
}

String _qty(num v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

Future<void> _showPurchase(BuildContext context, Purchase p, VoidCallback onChanged) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.85),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
          children: [
            Text(p.isReturn ? 'Return to ${p.supplierName}' : 'Purchase from ${p.supplierName}', style: CrmTokens.display(size: 17)),
            const SizedBox(height: 4),
            Text(
              '${crmDay.format(p.date)}${p.billNo.isEmpty ? '' : '  ·  No. ${p.billNo}'}${p.by.isEmpty ? '' : '  ·  by ${p.by}'}',
              style: CrmTokens.body(size: 12, color: CrmTokens.muted),
            ),
            // Which warehouse the goods went into (only worth saying when there's more than one).
            FutureBuilder<List<Warehouse>>(
              future: loadWarehouses(),
              builder: (_, snap) {
                final all = snap.data ?? const <Warehouse>[];
                if (all.length < 2) return const SizedBox.shrink();
                final name = all.where((w) => w.id == p.warehouseId).firstOrNull?.name ?? 'Main warehouse';
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('${p.isReturn ? 'From' : 'Into'}: $name', style: CrmTokens.body(size: 12, w: FontWeight.w600)),
                );
              },
            ),
            const SizedBox(height: 14),
            for (final l in p.lines)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(children: [
                  Expanded(child: Text(l.productName, style: CrmTokens.body(w: FontWeight.w600))),
                  Text('${_qty(l.qty)} × ${crmRs(l.unitCost)}', style: CrmTokens.body(color: CrmTokens.muted)),
                  const SizedBox(width: 12),
                  SizedBox(width: 110, child: Text(crmRs(l.amount), textAlign: TextAlign.right, style: CrmTokens.body(w: FontWeight.w600))),
                ]),
              ),
            const Divider(height: 22),
            if (p.discount != 0)
              Row(children: [
                Expanded(child: Text('Discount', style: CrmTokens.body(color: CrmTokens.muted))),
                Text('− ${crmRs(p.discount)}', style: CrmTokens.body()),
              ]),
            Row(children: [
              Expanded(child: Text('Total', style: CrmTokens.body(w: FontWeight.w700))),
              Text(crmRs(p.total), style: CrmTokens.display(size: 16, color: CrmTokens.navy)),
            ]),
            if (p.note.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(p.note, style: CrmTokens.body(color: CrmTokens.muted)),
            ],
            const SizedBox(height: 18),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: ctx,
                    builder: (d) => AlertDialog(
                      title: Text('Delete this ${p.isReturn ? 'return' : 'bill'}?', style: CrmTokens.display(size: 17)),
                      content: Text(
                        p.isReturn
                            ? 'The ${_qty(p.units)} units go back into stock and the amount owed to ${p.supplierName} goes back up.'
                            : 'The ${_qty(p.units)} units come out of stock and the amount owed to ${p.supplierName} goes down. '
                                'A payment made with it stays; delete it from the supplier if needed.',
                        style: CrmTokens.body(),
                      ),
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
                    await deletePurchase(p);
                    if (ctx.mounted) Navigator.pop(ctx);
                    onChanged();
                  } catch (e) {
                    if (ctx.mounted) crmSnack(ctx, "Couldn't delete. Try again.", error: true);
                  }
                },
                icon: const Icon(Icons.delete_outline, color: CrmTokens.red),
                label: Text('Delete', style: CrmTokens.body(color: CrmTokens.red, w: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

// -----------------------------------------------------------------------------
// Suppliers
// -----------------------------------------------------------------------------

class _SuppliersTab extends StatelessWidget {
  final PayablesBook book;
  final VoidCallback onChanged;
  const _SuppliersTab({required this.book, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final suppliers = [...book.suppliers]..sort((a, b) => book.balanceOf(b.id).compareTo(book.balanceOf(a.id)));
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 96),
      children: [
        CrmStat(label: 'Total owed to suppliers', value: crmRs(book.totalPayable), color: CrmTokens.red),
        const CrmSectionTitle('Suppliers'),
        if (suppliers.isEmpty)
          const CrmEmpty(icon: Icons.local_shipping_outlined, text: 'No suppliers yet. Add one from Add Supplier.')
        else
          for (final s in suppliers)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: CrmCard(
                padding: const EdgeInsets.all(12),
                onTap: () async {
                  await Navigator.push(
                      context, MaterialPageRoute(builder: (_) => SupplierLedgerScreen(supplier: s)));
                  onChanged();
                },
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(s.display, style: CrmTokens.body(size: 14, w: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(
                        'Bought ${crmRs(book.purchasedFrom(s.id))}  ·  Paid ${crmRs(book.paidTo(s.id))}  ·  ${s.termsLabel}'
                        '${s.active ? '' : '  ·  inactive'}',
                        style: CrmTokens.body(size: 12, color: CrmTokens.muted),
                      ),
                      if (book.overdueOf(s.id) > 0)
                        Text('Overdue ${crmRs(book.overdueOf(s.id))}',
                            style: CrmTokens.body(size: 12, color: CrmTokens.red, w: FontWeight.w600)),
                    ]),
                  ),
                  _balance(book.balanceOf(s.id)),
                  const Icon(Icons.chevron_right, color: CrmTokens.muted),
                ]),
              ),
            ),
      ],
    );
  }
}

Widget _balance(num b) {
  if (b == 0) return Text('Settled', style: CrmTokens.body(color: CrmTokens.green, w: FontWeight.w600));
  return Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
    Text(crmRs(b.abs()), style: CrmTokens.body(size: 14, w: FontWeight.w700, color: b > 0 ? CrmTokens.red : CrmTokens.green)),
    Text(b > 0 ? 'you owe' : 'they owe you', style: CrmTokens.body(size: 11, color: CrmTokens.muted)),
  ]);
}

/// One supplier's bills, returns and payments, with the running balance.
class SupplierLedgerScreen extends StatefulWidget {
  final Supplier supplier;
  const SupplierLedgerScreen({super.key, required this.supplier});

  @override
  State<SupplierLedgerScreen> createState() => _SupplierLedgerScreenState();
}

class _SupplierLedgerScreenState extends State<SupplierLedgerScreen> {
  PayablesBook? _book;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final b = await loadPayables();
      if (mounted) setState(() => _book = b);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _pay() async {
    final balance = _book?.balanceOf(widget.supplier.id) ?? 0;
    final amount = TextEditingController(text: balance > 0 ? balance.round().toString() : '');
    final note = TextEditingController();
    var method = 'Cash';
    var date = DateTime.now();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text('Pay ${widget.supplier.name}', style: CrmTokens.display(size: 17)),
          content: SizedBox(
            width: 380,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: amount,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: CrmTokens.body(),
                decoration: crmInput('Amount (Rs.)', icon: Icons.payments_outlined),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: method,
                decoration: crmInput('Method'),
                items: [for (final m in paymentMethods) DropdownMenuItem(value: m, child: Text(m, style: CrmTokens.body()))],
                onChanged: (v) => method = v ?? 'Cash',
              ),
              const SizedBox(height: 10),
              InkWell(
                onTap: () async {
                  final d = await showDatePicker(context: ctx, initialDate: date, firstDate: DateTime(2023), lastDate: DateTime.now());
                  if (d != null) set(() => date = d);
                },
                child: InputDecorator(
                  decoration: crmInput('Date', icon: Icons.calendar_today_outlined),
                  child: Text(crmDay.format(date), style: CrmTokens.body()),
                ),
              ),
              const SizedBox(height: 10),
              TextField(controller: note, style: CrmTokens.body(), decoration: crmInput('Note / cheque no. (optional)')),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancel', style: CrmTokens.body())),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: CrmTokens.amber, elevation: 0),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Save payment', style: CrmTokens.body(w: FontWeight.w700, color: CrmTokens.navyDark)),
            ),
          ],
        ),
      ),
    );
    final value = num.tryParse(amount.text.trim()) ?? 0;
    final noteText = note.text.trim();
    amount.dispose();
    note.dispose();
    if (ok != true) return;
    if (value <= 0) return mounted ? crmSnack(context, 'Enter an amount above zero', error: true) : null;
    try {
      await addSupplierPayment(widget.supplier, value, date, method, noteText);
      if (mounted) crmSnack(context, 'Payment of ${crmRs(value)} saved');
      _load();
    } catch (e) {
      if (mounted) crmSnack(context, "Couldn't save the payment. Try again.", error: true);
    }
  }

  Future<void> _deletePayment(SupplierPayment p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('Delete payment of ${crmRs(p.amount)}?', style: CrmTokens.display(size: 17)),
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
      await deleteSupplierPayment(p.id);
      _load();
    } catch (_) {
      if (mounted) crmSnack(context, "Couldn't delete. Try again.", error: true);
    }
  }

  Future<void> _newBill({bool isReturn = false}) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => PurchaseFormScreen(isReturn: isReturn, supplier: widget.supplier)),
    );
    if (saved == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.supplier;
    final book = _book;
    Widget body;
    if (book == null) {
      body = _error != null
          ? Center(child: OutlinedButton(onPressed: _load, child: Text('Try again', style: CrmTokens.body(color: CrmTokens.navy))))
          : const Center(child: CircularProgressIndicator(color: CrmTokens.navy));
    } else {
      // Oldest first to build the running balance, shown newest first.
      final entries = <({DateTime date, Widget Function(num running) build, num effect})>[
        for (final p in book.purchasesOf(s.id))
          (date: p.date, effect: p.payableEffect, build: (num r) => _entry(p.isReturn ? 'Return' : 'Bill', p, null, r)),
        for (final p in book.paymentsOf(s.id))
          (date: p.date, effect: -p.amount, build: (num r) => _entry('Payment', null, p, r)),
      ]..sort((a, b) => a.date.compareTo(b.date));
      // The record as saved now (terms, limit, opening balance may have been edited).
      final info = book.supplier(s.id) ?? s;
      final opening = book.openingOf(s.id);
      var running = opening;
      final rows = <Widget>[
        if (opening != 0) _openingEntry(info, opening),
      ];
      for (final e in entries) {
        running += e.effect;
        rows.add(e.build(running));
      }
      final balance = book.balanceOf(s.id);
      final overdue = book.overdueOf(s.id);
      body = RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 40),
          children: [
            Row(children: [
              Expanded(child: CrmStat(label: 'Balance', value: crmRs(balance), color: balance > 0 ? CrmTokens.red : CrmTokens.green)),
              const SizedBox(width: 8),
              Expanded(
                child: CrmStat(
                  label: 'Overdue (${info.termsLabel})',
                  value: crmRs(overdue),
                  color: overdue > 0 ? CrmTokens.red : CrmTokens.green,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: CrmStat(
                  label: 'Credit limit',
                  value: info.creditLimit > 0 ? crmRs(info.creditLimit) : 'None',
                  color: info.creditLimit > 0 && balance > info.creditLimit ? CrmTokens.red : null,
                ),
              ),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: CrmStat(label: 'Total bought', value: crmRs(book.purchasedFrom(s.id)))),
              const SizedBox(width: 8),
              Expanded(child: CrmStat(label: 'Total paid', value: crmRs(book.paidTo(s.id)))),
            ]),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: CrmTokens.amber, elevation: 0),
                onPressed: _pay,
                icon: const Icon(Icons.payments_outlined, color: CrmTokens.navyDark, size: 18),
                label: Text('Pay supplier', style: CrmTokens.body(color: CrmTokens.navyDark, w: FontWeight.w700)),
              ),
              OutlinedButton.icon(
                onPressed: _newBill,
                icon: const Icon(Icons.add_shopping_cart, color: CrmTokens.navy, size: 18),
                label: Text('New purchase', style: CrmTokens.body(color: CrmTokens.navy, w: FontWeight.w600)),
              ),
              OutlinedButton.icon(
                onPressed: () => _newBill(isReturn: true),
                icon: const Icon(Icons.assignment_return_outlined, color: CrmTokens.navy, size: 18),
                label: Text('Return goods', style: CrmTokens.body(color: CrmTokens.navy, w: FontWeight.w600)),
              ),
            ]),
            if (info.contact.isNotEmpty || info.bankName.isNotEmpty || info.iban.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                [
                  if (info.contact.isNotEmpty) 'Phone: ${info.contact}',
                  if (info.contactPerson.isNotEmpty) 'Contact: ${info.contactPerson}',
                  if (info.bankName.isNotEmpty || info.iban.isNotEmpty)
                    'Bank: ${[info.bankName, info.accountTitle, info.iban].where((x) => x.isNotEmpty).join(' · ')}',
                ].join('\n'),
                style: CrmTokens.body(color: CrmTokens.muted),
              ),
            ],
            const CrmSectionTitle('Ledger'),
            if (rows.isEmpty)
              const CrmEmpty(icon: Icons.menu_book_outlined, text: 'No bills or payments with this supplier yet.')
            else
              ...rows.reversed,
          ],
        ),
      );
    }
    return Scaffold(
      backgroundColor: CrmTokens.bg,
      appBar: AppBar(
        backgroundColor: CrmTokens.navy,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(s.display, style: CrmTokens.display(size: 18, color: Colors.white, w: FontWeight.w600)),
      ),
      body: body,
    );
  }

  /// What was owed when the supplier was added (shown as the oldest ledger line).
  Widget _openingEntry(Supplier s, num opening) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: CrmCard(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Opening balance${s.openingDate == null ? '' : '  ·  ${crmDay.format(s.openingDate!)}'}',
                    style: CrmTokens.body(w: FontWeight.w600)),
                Text(opening > 0 ? 'Owed to them when added' : 'They owed us when added',
                    style: CrmTokens.body(size: 12, color: CrmTokens.muted)),
              ]),
            ),
            Text('${opening < 0 ? '−' : '+'} ${crmRs(opening.abs())}',
                style: CrmTokens.body(w: FontWeight.w700, color: opening < 0 ? CrmTokens.green : CrmTokens.red)),
          ]),
        ),
      );

  Widget _entry(String kind, Purchase? p, SupplierPayment? pay, num running) {
    final isPayment = pay != null;
    final amount = isPayment ? -pay.amount : p!.payableEffect;
    final date = isPayment ? pay.date : p!.date;
    final detail = isPayment
        ? [pay.method, if (pay.note.isNotEmpty) pay.note].join('  ·  ')
        : [if (p!.billNo.isNotEmpty) 'No. ${p.billNo}', '${p.lines.length} products', '${_qty(p.units)} units'].join('  ·  ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: CrmCard(
        padding: const EdgeInsets.all(12),
        onTap: isPayment ? null : () => _showPurchase(context, p!, _load),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$kind  ·  ${crmDay.format(date)}', style: CrmTokens.body(w: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(detail, style: CrmTokens.body(size: 12, color: CrmTokens.muted)),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('${amount < 0 ? '−' : '+'} ${crmRs(amount.abs())}',
                style: CrmTokens.body(w: FontWeight.w700, color: amount < 0 ? CrmTokens.green : CrmTokens.red)),
            Text('Balance ${crmRs(running)}', style: CrmTokens.body(size: 11, color: CrmTokens.muted)),
          ]),
          if (isPayment)
            IconButton(
              tooltip: 'Delete payment',
              onPressed: () => _deletePayment(pay),
              icon: const Icon(Icons.delete_outline, size: 18, color: CrmTokens.muted),
            ),
        ]),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Profit
// -----------------------------------------------------------------------------

class ProfitTab extends StatefulWidget {
  const ProfitTab({super.key});

  @override
  State<ProfitTab> createState() => _ProfitTabState();
}

class _ProfitTabState extends State<ProfitTab> {
  late DateTimeRange _range = DateTimeRange(start: DateTime(DateTime.now().year, DateTime.now().month), end: DateTime.now());
  ProfitReport? _report;
  Object? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await loadProfitReport(_range.start, _range.end);
      if (mounted) setState(() => _report = r);
    } catch (e) {
      debugPrint('Profit report failed: $e');
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickRange() async {
    final r = await showDateRangePicker(context: context, firstDate: DateTime(2023), lastDate: DateTime.now(), initialDateRange: _range);
    if (r == null) return;
    setState(() => _range = r);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final r = _report;
    final fmt = DateFormat('dd MMM');
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 96),
      children: [
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _pickRange,
              icon: const Icon(Icons.date_range, color: CrmTokens.navy, size: 18),
              label: Text('${fmt.format(_range.start)} – ${crmDay.format(_range.end)}',
                  style: CrmTokens.body(color: CrmTokens.navy, w: FontWeight.w600)),
            ),
          ),
          const SizedBox(width: 8),
          if (_loading)
            const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: CrmTokens.navy))
          else
            IconButton(tooltip: 'Refresh', onPressed: _load, icon: const Icon(Icons.refresh, color: CrmTokens.navy)),
        ]),
        const SizedBox(height: 12),
        if (r == null && _error != null)
          const CrmEmpty(icon: Icons.cloud_off, text: "Couldn't load the report. Check your connection.")
        else if (r == null)
          const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(color: CrmTokens.navy)))
        else ...[
          Row(children: [
            Expanded(child: CrmStat(label: 'Sales (${r.invoices} invoices)', value: crmRs(r.sales))),
            const SizedBox(width: 8),
            Expanded(child: CrmStat(label: 'Cost of goods sold', value: crmRs(r.cost))),
            const SizedBox(width: 8),
            Expanded(
              child: CrmStat(
                label: 'Gross profit${r.sales > 0 ? ' (${(r.profit / r.sales * 100).toStringAsFixed(1)}%)' : ''}',
                value: crmRs(r.profit),
                color: r.profit >= 0 ? CrmTokens.green : CrmTokens.red,
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: CrmStat(label: 'Purchases (net of returns)', value: crmRs(r.purchases))),
            const SizedBox(width: 8),
            Expanded(child: CrmStat(label: 'Paid to suppliers', value: crmRs(r.paidToSuppliers))),
          ]),
          if (r.productsWithoutCost > 0)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                '${r.productsWithoutCost} product(s) sold have no purchase cost yet, so their cost counts as 0 and profit '
                'looks higher than it is. Enter a purchase for them to fix this.',
                style: CrmTokens.body(size: 12, color: CrmTokens.red),
              ),
            ),
          const CrmSectionTitle('By product'),
          if (r.products.isEmpty)
            const CrmEmpty(icon: Icons.bar_chart, text: 'No sales in these dates.')
          else
            CrmCard(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Column(children: [
                _row('Product', 'Units', 'Sales', 'Cost', 'Profit', header: true),
                for (final p in r.products) _row(p.name, _qty(p.units), crmRs(p.sales), crmRs(p.cost), crmRs(p.profit), profit: p.profit),
              ]),
            ),
          const SizedBox(height: 8),
          Text(
            'Sales are invoice amounts after shop returns and discounts, by Sales Date. Cost uses each product\'s latest '
            'purchase cost; free (FOC) units count as cost with no sale.',
            style: CrmTokens.body(size: 11.5, color: CrmTokens.muted),
          ),
        ],
      ],
    );
  }

  Widget _row(String a, String b, String c, String d, String e, {bool header = false, num profit = 0}) {
    TextStyle st(bool right, {Color? color}) =>
        CrmTokens.body(size: 12, w: header ? FontWeight.w700 : FontWeight.w400, color: header ? CrmTokens.muted : color);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Expanded(flex: 4, child: Text(a, style: st(false), overflow: TextOverflow.ellipsis)),
        Expanded(flex: 2, child: Text(b, textAlign: TextAlign.right, style: st(true))),
        Expanded(flex: 3, child: Text(c, textAlign: TextAlign.right, style: st(true))),
        Expanded(flex: 3, child: Text(d, textAlign: TextAlign.right, style: st(true))),
        Expanded(
          flex: 3,
          child: Text(e, textAlign: TextAlign.right, style: st(true, color: profit < 0 ? CrmTokens.red : CrmTokens.green)),
        ),
      ]),
    );
  }
}

/// Dashboard row: what is owed to suppliers and what the stock on hand is worth.
class InventorySummaryRow extends StatefulWidget {
  final VoidCallback? onOpenPurchases;
  final VoidCallback? onOpenStock;
  const InventorySummaryRow({super.key, this.onOpenPurchases, this.onOpenStock});

  @override
  State<InventorySummaryRow> createState() => _InventorySummaryRowState();
}

class _InventorySummaryRowState extends State<InventorySummaryRow> {
  num? _payable;
  num? _stockValue;
  int? _outOfStock;
  bool _tracking = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait<Object?>([loadPayables(), loadProductIndex(fresh: true), stockStartedAt()]);
      if (!mounted) return;
      final products = results[1] as ProductIndex;
      setState(() {
        _payable = (results[0] as PayablesBook).totalPayable;
        _tracking = results[2] != null;
        _stockValue = products.all.fold<num>(0, (s, p) => s + p.stockValue);
        _outOfStock = products.all.where((p) => p.stock != null && p.onHand <= 0).length;
      });
    } catch (e) {
      debugPrint('Dashboard inventory figures failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    String v(Object? x, String Function() f) => x == null ? '…' : f();
    return Row(children: [
      Expanded(
        child: CrmStat(
          label: 'Owed to suppliers',
          value: v(_payable, () => crmRs(_payable!)),
          color: CrmTokens.red,
          onTap: widget.onOpenPurchases,
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: CrmStat(
          label: 'Stock value (at cost)',
          value: _tracking || _stockValue == null ? v(_stockValue, () => crmRs(_stockValue!)) : 'Not set up',
          onTap: widget.onOpenStock,
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: CrmStat(
          label: 'Out of stock',
          value: _tracking || _outOfStock == null ? v(_outOfStock, () => '$_outOfStock products') : '—',
          color: (_outOfStock ?? 0) > 0 ? CrmTokens.red : CrmTokens.navy,
          onTap: widget.onOpenStock,
        ),
      ),
    ]);
  }
}
