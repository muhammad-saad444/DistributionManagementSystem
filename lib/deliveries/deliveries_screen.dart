// Admin: Deliveries. The day's invoices, grouped into trips (van + delivery man); print a trip's
// load sheet, send it out, and settle it when the van is back.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../Admin/dashboard_overview.dart' show dashRs;
import '../account/account.dart';
import '../print_preview.dart';
import '../returns/return_sheet.dart';
import '../ui/app_theme.dart';
import '../ui/kpi_card.dart';
import 'deliveries_data.dart';

final _money = NumberFormat('#,##0');
String _rs(num v) => 'Rs ${_money.format(v.round())}';

class DeliveriesScreen extends StatefulWidget {
  const DeliveriesScreen({super.key});

  @override
  State<DeliveriesScreen> createState() => _DeliveriesScreenState();
}

class _DeliveriesScreenState extends State<DeliveriesScreen> {
  DateTime _day = DateTime.now();
  List<DeliveryInvoice>? _invoices;
  List<Trip> _trips = const [];
  Object? _error;
  bool _busy = false;
  final Set<String> _picked = {};
  String? _area; // filter for invoices to dispatch

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final (inv, trips) = await loadDeliveryDay(_day);
      if (!mounted) return;
      setState(() {
        _invoices = inv;
        _trips = trips;
        _picked.removeWhere((id) => inv.every((i) => i.id != id || i.dispatched));
      });
    } catch (e) {
      debugPrint('Deliveries: $e');
      if (mounted) setState(() => _error = e);
    }
  }

  void _setDay(DateTime d) {
    setState(() {
      _day = d;
      _invoices = null;
      _picked.clear();
      _area = null;
    });
    _load();
  }

  Future<void> _run(Future<void> Function() job, String done) async {
    setState(() => _busy = true);
    try {
      await job();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Couldn't do that: $e")));
    } finally {
      if (mounted) setState(() => _busy = false);
      await _load();
    }
  }

  Map<String, DeliveryInvoice> get _byId => {for (final i in _invoices ?? const <DeliveryInvoice>[]) i.id: i};

  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final inv = _invoices;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Deliveries'),
        actions: [IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh), onPressed: _load), const SizedBox(width: 6)],
        bottom: _busy ? const PreferredSize(preferredSize: Size.fromHeight(2), child: LinearProgressIndicator(minHeight: 2)) : null,
      ),
      body: LayoutBuilder(builder: (context, box) {
        final wide = box.maxWidth >= 900;
        final pad = wide ? 24.0 : 14.0;
        return RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: EdgeInsets.fromLTRB(pad, 18, pad, 32),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1180),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Align(alignment: Alignment.centerLeft, child: _daySwitcher()),
                    const SizedBox(height: 16),
                    if (inv == null)
                      _error != null
                          ? _panel(child: _empty(Icons.cloud_off, "Couldn't load deliveries", 'Pull down to try again.'))
                          : const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator()))
                    else ...[
                      _kpis(inv, wide),
                      const SizedBox(height: 16),
                      if (wide)
                        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Expanded(flex: 6, child: _toDispatch(inv)),
                          const SizedBox(width: 16),
                          Expanded(flex: 5, child: _tripsPanel()),
                        ])
                      else ...[
                        _toDispatch(inv),
                        const SizedBox(height: 16),
                        _tripsPanel(),
                      ],
                    ],
                  ]),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  Widget _daySwitcher() {
    final today = DateTime.now();
    final isToday = _day.year == today.year && _day.month == today.month && _day.day == today.day;
    return Container(
      decoration: kpiCardDecoration(),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(tooltip: 'Day before', icon: const Icon(Icons.chevron_left), onPressed: () => _setDay(_day.subtract(const Duration(days: 1)))),
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () async {
            final d = await showDatePicker(context: context, initialDate: _day, firstDate: DateTime(2024), lastDate: today.add(const Duration(days: 7)));
            if (d != null) _setDay(d);
          },
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 150),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(DateFormat('EEE, d MMM yyyy').format(_day),
                  style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: AppColors.text)),
              Text(isToday ? 'today · invoices by sales date' : 'invoices by sales date', style: const TextStyle(fontSize: 11, color: AppColors.muted)),
            ]),
          ),
        ),
        IconButton(tooltip: 'Next day', icon: const Icon(Icons.chevron_right), onPressed: () => _setDay(_day.add(const Duration(days: 1)))),
      ]),
    );
  }

  Widget _kpis(List<DeliveryInvoice> inv, bool wide) {
    final waiting = inv.where((i) => !i.dispatched).toList();
    final out = inv.where((i) => i.dispatched && (i.deliveryStatus == 'out' || i.deliveryStatus.isEmpty)).toList();
    final done = inv.where((i) => {'delivered', 'partial'}.contains(i.deliveryStatus)).toList();
    final back = inv.where((i) => i.deliveryStatus == 'returned').length;
    final cash = inv.fold<double>(0, (s, i) => s + i.codCollected);
    double sum(List<DeliveryInvoice> l) => l.fold(0, (s, i) => s + i.amount);
    return kpiGrid([
      KpiCard(
        label: 'TO DISPATCH',
        icon: Icons.inventory_outlined,
        tint: waiting.isEmpty ? AppColors.green : AppColors.amber,
        tintBg: waiting.isEmpty ? AppColors.greenBg : AppColors.amberBg,
        value: '${waiting.length} of ${inv.length}',
        sub: waiting.isEmpty ? 'every invoice is on a trip' : '${dashRs(sum(waiting))} not on a trip yet',
      ),
      KpiCard(
        label: 'ON TRIPS',
        icon: Icons.local_shipping_outlined,
        tint: AppColors.blue,
        tintBg: AppColors.blueBg,
        value: '${out.length}',
        sub: '${_trips.where((t) => t.status != TripStatus.settled).length} trip(s) not settled · ${dashRs(sum(out))}',
      ),
      KpiCard(
        label: 'DELIVERED',
        icon: Icons.task_alt,
        tint: AppColors.green,
        tintBg: AppColors.greenBg,
        value: '${done.length}',
        sub: back > 0 ? '$back not delivered (returned)' : 'invoices delivered',
        valueColor: null,
      ),
      KpiCard(
        label: 'CASH COLLECTED',
        icon: Icons.payments_outlined,
        tint: AppColors.navy,
        tintBg: AppColors.brandSoft,
        value: dashRs(cash),
        sub: 'at the door, into the khata',
      ),
    ], wide ? 4 : 2);
  }

  // ---------------------------------------------------------------------------
  // Invoices not yet on a trip
  // ---------------------------------------------------------------------------

  Widget _toDispatch(List<DeliveryInvoice> inv) {
    final waiting = inv.where((i) => !i.dispatched).toList();
    final areas = {for (final i in waiting) i.area.isEmpty ? '-' : i.area}.toList()..sort();
    final shown = waiting.where((i) => _area == null || (i.area.isEmpty ? '-' : i.area) == _area).toList();
    final picked = waiting.where((i) => _picked.contains(i.id)).toList();
    return _panel(
      padding: const EdgeInsets.fromLTRB(0, 18, 0, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: _title(Icons.inventory_outlined, 'To dispatch', 'tick invoices, then make a trip'),
        ),
        const SizedBox(height: 10),
        if (waiting.isEmpty)
          _empty(Icons.task_alt, inv.isEmpty ? 'No invoices on this day' : 'All invoices are on trips',
              inv.isEmpty ? 'Invoices appear here by their sales date.' : 'Settle the trips when the vans are back.')
        else ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(spacing: 6, runSpacing: 6, children: [
              ChoiceChip(label: const Text('All areas'), selected: _area == null, showCheckmark: false, onSelected: (_) => setState(() => _area = null)),
              for (final a in areas)
                ChoiceChip(label: Text(a), selected: _area == a, showCheckmark: false, onSelected: (_) => setState(() => _area = a)),
            ]),
          ),
          CheckboxListTile(
            dense: true,
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            value: shown.isNotEmpty && shown.every((i) => _picked.contains(i.id)),
            onChanged: (v) => setState(() => v == true ? _picked.addAll(shown.map((i) => i.id)) : _picked.removeAll(shown.map((i) => i.id))),
            title: Text('Select all ${shown.length}', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
          ),
          const Divider(height: 1),
          for (final i in shown)
            CheckboxListTile(
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              value: _picked.contains(i.id),
              onChanged: (v) => setState(() => v == true ? _picked.add(i.id) : _picked.remove(i.id)),
              title: Text('#${i.number} · ${i.shop}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.text)),
              subtitle: Text('${i.area.isEmpty ? '-' : i.area} · ${i.items.length} item${i.items.length == 1 ? '' : 's'}',
                  style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
              secondary: Text(_rs(i.amount), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.text)),
            ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: FilledButton.icon(
              onPressed: picked.isEmpty || _busy ? null : () => _makeTrip(picked),
              icon: const Icon(Icons.local_shipping_outlined),
              label: Text(picked.isEmpty
                  ? 'Make a trip'
                  : 'Make a trip · ${picked.length} invoice${picked.length == 1 ? '' : 's'} · ${_rs(picked.fold<double>(0, (s, i) => s + i.amount))}'),
            ),
          ),
        ],
      ]),
    );
  }

  Future<void> _makeTrip(List<DeliveryInvoice> picked) async {
    final details = await showDialog<(String, String, String, String)>(context: context, builder: (_) => const _TripDialog());
    if (details == null) return;
    final number = _trips.length + 1;
    await _run(
      () => createTrip(
        day: _day,
        invoiceIds: picked.map((i) => i.id).toList(),
        vehicle: details.$1,
        driver: details.$2,
        driverPhone: details.$3,
        notes: details.$4,
        number: number,
      ),
      'Trip $number made with ${picked.length} invoice${picked.length == 1 ? '' : 's'}',
    );
    _picked.clear();
  }

  // ---------------------------------------------------------------------------
  // Trips
  // ---------------------------------------------------------------------------

  Widget _tripsPanel() => _panel(
        padding: const EdgeInsets.fromLTRB(0, 18, 0, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: _title(Icons.local_shipping_outlined, 'Trips', '${_trips.length} today')),
          const SizedBox(height: 10),
          if (_trips.isEmpty) _empty(Icons.local_shipping_outlined, 'No trips yet', 'Tick invoices on the left and make a trip.'),
          for (var k = 0; k < _trips.length; k++) ...[
            if (k > 0) const Divider(height: 1),
            _tripRow(_trips[k]),
          ],
        ]),
      );

  Widget _tripRow(Trip t) {
    final inv = [for (final id in t.invoiceIds) if (_byId[id] != null) _byId[id]!];
    final value = inv.fold<double>(0, (s, i) => s + i.amount);
    final (Color fg, Color bg) = switch (t.status) {
      TripStatus.loading => (AppColors.amberDark, AppColors.amberBg),
      TripStatus.out => (AppColors.blue, AppColors.blueBg),
      TripStatus.settled => (AppColors.green, AppColors.greenBg),
    };
    final settled = t.status == TripStatus.settled;
    final cash = inv.fold<double>(0, (s, i) => s + i.codCollected);
    final delivered = inv.where((i) => {'delivered', 'partial'}.contains(i.deliveryStatus)).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Text('Trip ${t.number}${t.vehicle.isEmpty ? '' : ' · ${t.vehicle}'}',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.text)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
            child: Text(t.statusLabel, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg)),
          ),
        ]),
        const SizedBox(height: 3),
        Text(
          [
            if (t.driver.isNotEmpty) '${t.driver}${t.driverPhone.isEmpty ? '' : ' (${t.driverPhone})'}',
            '${inv.length} invoice${inv.length == 1 ? '' : 's'} · ${_rs(value)}',
            if (settled) '$delivered delivered · ${_rs(cash)} collected',
          ].join(' · '),
          style: const TextStyle(fontSize: 12, color: AppColors.muted),
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton.icon(
            onPressed: inv.isEmpty ? null : () => _printLoadSheet(t, inv),
            icon: const Icon(Icons.print_outlined, size: 18),
            label: const Text('Load sheet'),
          ),
          if (t.status == TripStatus.loading) ...[
            FilledButton.icon(
              onPressed: _busy ? null : () => _run(() => markTripOut(t), 'Trip ${t.number} is out for delivery'),
              icon: const Icon(Icons.local_shipping_outlined, size: 18),
              label: const Text('Out for delivery'),
            ),
            TextButton(
              onPressed: _busy ? null : () => _confirmCancel(t),
              style: TextButton.styleFrom(foregroundColor: AppColors.red),
              child: const Text('Cancel trip'),
            ),
          ],
          if (t.status == TripStatus.out)
            FilledButton.icon(
              onPressed: _busy || inv.isEmpty
                  ? null
                  : () async {
                      final done = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => SettleTripScreen(trip: t, invoices: inv)));
                      if (done == true) _load();
                    },
              icon: const Icon(Icons.fact_check_outlined, size: 18),
              label: const Text('Settle'),
            ),
        ]),
      ]),
    );
  }

  Future<void> _confirmCancel(Trip t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Cancel trip ${t.number}?'),
        content: const Text('Its invoices go back to "To dispatch" so they can go on another trip.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Keep it')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: AppColors.red), onPressed: () => Navigator.pop(c, true), child: const Text('Cancel trip')),
        ],
      ),
    );
    if (ok == true) await _run(() => cancelTrip(t), 'Trip ${t.number} cancelled');
  }

  Future<void> _printLoadSheet(Trip t, List<DeliveryInvoice> inv) => showPrintPreview(
        context,
        title: 'Load sheet · Trip ${t.number}',
        fileName: 'load-sheet-trip-${t.number}-${DateFormat('yyyy-MM-dd').format(t.date)}.pdf',
        buildPdf: () => _loadSheetPdf(t, inv),
      );

  // ---------------------------------------------------------------------------

  Widget _panel({required Widget child, EdgeInsets padding = const EdgeInsets.fromLTRB(20, 18, 20, 12)}) =>
      Container(decoration: kpiCardDecoration(), clipBehavior: Clip.antiAlias, padding: padding, child: child);

  Widget _title(IconData icon, String title, String note) => Row(children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(color: AppColors.brandSoft, borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, size: 15, color: AppColors.navy),
        ),
        const SizedBox(width: 10),
        Text(title, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: AppColors.text)),
        const SizedBox(width: 8),
        Expanded(child: Text(note, style: const TextStyle(fontSize: 11.5, color: AppColors.muted), overflow: TextOverflow.ellipsis)),
      ]);

  Widget _empty(IconData icon, String title, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 34, color: AppColors.muted),
          const SizedBox(height: 8),
          Text(title, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: AppColors.text)),
          const SizedBox(height: 4),
          Text(text, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
        ]),
      );
}

// =============================================================================
// New trip
// =============================================================================

class _TripDialog extends StatefulWidget {
  const _TripDialog();

  @override
  State<_TripDialog> createState() => _TripDialogState();
}

class _TripDialogState extends State<_TripDialog> {
  final _vehicle = TextEditingController();
  final _driver = TextEditingController();
  final _phone = TextEditingController();
  final _notes = TextEditingController();

  @override
  void dispose() {
    for (final c in [_vehicle, _driver, _phone, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New trip'),
      content: SizedBox(
        width: 380,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: _vehicle,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(labelText: 'Vehicle', hintText: 'e.g. LES-1234 or Suzuki 2'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _driver,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Delivery man *'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ -]'))],
            decoration: const InputDecoration(labelText: 'Phone (optional)'),
          ),
          const SizedBox(height: 12),
          TextField(controller: _notes, decoration: const InputDecoration(labelText: 'Note (optional)')),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _driver.text.trim().isEmpty
              ? null
              : () => Navigator.pop(context, (_vehicle.text, _driver.text, _phone.text, _notes.text)),
          child: const Text('Make trip'),
        ),
      ],
    );
  }
}

// =============================================================================
// Settle a trip
// =============================================================================

class SettleTripScreen extends StatefulWidget {
  final Trip trip;
  final List<DeliveryInvoice> invoices;
  const SettleTripScreen({super.key, required this.trip, required this.invoices});

  @override
  State<SettleTripScreen> createState() => _SettleTripScreenState();
}

class _SettleTripScreenState extends State<SettleTripScreen> {
  late final List<DeliveryInvoice> _inv = [...widget.invoices];
  late final List<DeliveryOutcome> _outcome = [for (final _ in widget.invoices) DeliveryOutcome.delivered];
  late final List<TextEditingController> _cash = [
    for (final i in widget.invoices) TextEditingController(text: i.amount > 0 ? i.amount.round().toString() : ''),
  ];
  bool _saving = false;

  @override
  void dispose() {
    for (final c in _cash) {
      c.dispose();
    }
    super.dispose();
  }

  double _cashOf(int k) => _outcome[k] == DeliveryOutcome.returned ? 0 : (double.tryParse(_cash[k].text.trim()) ?? 0);

  List<InvoiceSettlement> get _results => [for (var k = 0; k < _inv.length; k++) InvoiceSettlement(_inv[k], _outcome[k], _cashOf(k))];

  /// Partly delivered: record what came back with the return form, then the bill is smaller.
  Future<void> _recordReturn(int k) async {
    final fresh = (await companyCol('invoices').doc(_inv[k].id).get()).data();
    if (fresh == null || !mounted) return;
    final refund = await showReturnSheet(context, invoiceId: _inv[k].id, invoice: fresh);
    if (refund == null) return;
    final after = (await companyCol('invoices').doc(_inv[k].id).get()).data();
    if (after == null || !mounted) return;
    setState(() {
      _inv[k] = DeliveryInvoice.fromMap(_inv[k].id, after);
      _cash[k].text = _inv[k].amount.round().toString();
    });
  }

  Future<void> _settle() async {
    setState(() => _saving = true);
    try {
      await settleTrip(widget.trip, _results);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Trip ${widget.trip.number} settled')));
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Couldn't settle: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = TripSummary.of(_results);
    return Scaffold(
      appBar: AppBar(title: Text('Settle trip ${widget.trip.number}${widget.trip.driver.isEmpty ? '' : ' · ${widget.trip.driver}'}')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Text(
                  'For each invoice: was it delivered? Enter the cash collected at the door; it goes into the shop\'s khata. '
                  'For a partly delivered invoice, record the goods that came back first.',
                  style: TextStyle(fontSize: 12.5, color: AppColors.muted),
                ),
                const SizedBox(height: 14),
                for (var k = 0; k < _inv.length; k++) ...[_row(k), const SizedBox(height: 10)],
              ]),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: AppColors.border))),
          child: Center(
            heightFactor: 1, // a plain Center fills the whole screen in a bottom bar
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: Row(children: [
                Expanded(
                  child: Text(
                    '${s.delivered} delivered · ${s.partial} partly · ${s.returned} not delivered\nCash collected ${_rs(s.cash)} of ${_rs(s.value)}',
                    style: const TextStyle(fontSize: 12.5, color: AppColors.text, fontWeight: FontWeight.w600),
                  ),
                ),
                FilledButton.icon(
                  onPressed: _saving ? null : _settle,
                  icon: _saving
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check),
                  label: const Text('Settle trip'),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(int k) {
    final i = _inv[k];
    final o = _outcome[k];
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: kpiCardDecoration(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('#${i.number} · ${i.shop}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.text)),
              Text('${i.area.isEmpty ? '-' : i.area} · bill ${_rs(i.amount)}', style: const TextStyle(fontSize: 12, color: AppColors.muted)),
            ]),
          ),
        ]),
        const SizedBox(height: 10),
        SegmentedButton<DeliveryOutcome>(
          segments: const [
            ButtonSegment(value: DeliveryOutcome.delivered, label: Text('Delivered'), icon: Icon(Icons.task_alt, size: 16)),
            ButtonSegment(value: DeliveryOutcome.partial, label: Text('Partly'), icon: Icon(Icons.rule, size: 16)),
            ButtonSegment(value: DeliveryOutcome.returned, label: Text('Not delivered'), icon: Icon(Icons.undo, size: 16)),
          ],
          selected: {o},
          showSelectedIcon: false,
          onSelectionChanged: (v) => setState(() => _outcome[k] = v.first),
          style: SegmentedButton.styleFrom(
            selectedBackgroundColor: switch (o) {
              DeliveryOutcome.delivered => AppColors.greenBg,
              DeliveryOutcome.partial => AppColors.amberBg,
              DeliveryOutcome.returned => AppColors.redBg,
            },
            side: const BorderSide(color: AppColors.border),
            visualDensity: VisualDensity.compact,
          ),
        ),
        const SizedBox(height: 10),
        if (o == DeliveryOutcome.returned)
          const Text('All goods come back into stock and the bill is cancelled (recorded as a return).',
              style: TextStyle(fontSize: 12, color: AppColors.red))
        else
          Row(children: [
            Expanded(
              child: TextField(
                controller: _cash[k],
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: 'Cash collected', prefixText: 'Rs  ', helperText: '0 if the shop took it on credit'),
                onChanged: (_) => setState(() {}),
              ),
            ),
            if (o == DeliveryOutcome.partial) ...[
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: () => _recordReturn(k),
                icon: const Icon(Icons.assignment_return_outlined, size: 18),
                label: const Text('Goods back'),
              ),
            ],
          ]),
      ]),
    );
  }
}

// =============================================================================
// Printed load sheet
// =============================================================================

Future<Uint8List> _loadSheetPdf(Trip t, List<DeliveryInvoice> inv) async {
  final doc = pw.Document();
  final lines = loadSheet(inv);
  String q(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
  pw.Widget cell(String s, {bool right = false, bool bold = false}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: pw.Text(s, textAlign: right ? pw.TextAlign.right : pw.TextAlign.left, style: pw.TextStyle(fontSize: 9.5, fontWeight: bold ? pw.FontWeight.bold : null)),
      );
  final total = inv.fold<double>(0, (s, i) => s + i.amount);
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4.copyWith(marginLeft: 32, marginRight: 32, marginTop: 32, marginBottom: 32),
    build: (_) => [
      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
        pw.Text(Account.companyName, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
        pw.Text('Load sheet · Trip ${t.number}', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
      ]),
      pw.SizedBox(height: 4),
      pw.Text(
        [
          DateFormat('EEE, d MMM yyyy').format(t.date),
          if (t.vehicle.isNotEmpty) 'Vehicle ${t.vehicle}',
          if (t.driver.isNotEmpty) 'Delivery man ${t.driver}${t.driverPhone.isEmpty ? '' : ' (${t.driverPhone})'}',
        ].join('   ·   '),
        style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
      ),
      pw.SizedBox(height: 12),
      pw.Text('Goods to load', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 4),
      pw.Table(
        border: pw.TableBorder.all(color: PdfColors.grey500, width: 0.5),
        columnWidths: const {0: pw.FlexColumnWidth(4), 1: pw.FlexColumnWidth(1.4), 2: pw.FlexColumnWidth(1), 3: pw.FlexColumnWidth(1), 4: pw.FlexColumnWidth(1.2), 5: pw.FixedColumnWidth(50)},
        children: [
          pw.TableRow(decoration: const pw.BoxDecoration(color: PdfColors.grey300), children: [
            cell('Product', bold: true),
            cell('Unit', bold: true),
            cell('Qty', bold: true, right: true),
            cell('Free', bold: true, right: true),
            cell('Total', bold: true, right: true),
            cell('Loaded', bold: true),
          ]),
          for (final l in lines)
            pw.TableRow(children: [cell(l.product), cell(l.size), cell(q(l.qty), right: true), cell(q(l.free), right: true), cell(q(l.units), right: true, bold: true), cell('')]),
        ],
      ),
      pw.SizedBox(height: 14),
      pw.Text('Invoices', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 4),
      pw.Table(
        border: pw.TableBorder.all(color: PdfColors.grey500, width: 0.5),
        columnWidths: const {0: pw.FixedColumnWidth(40), 1: pw.FlexColumnWidth(3), 2: pw.FlexColumnWidth(1.6), 3: pw.FlexColumnWidth(1.4), 4: pw.FlexColumnWidth(1.4), 5: pw.FlexColumnWidth(1.6)},
        children: [
          pw.TableRow(decoration: const pw.BoxDecoration(color: PdfColors.grey300), children: [
            cell('#', bold: true),
            cell('Shop', bold: true),
            cell('Area', bold: true),
            cell('Bill (Rs)', bold: true, right: true),
            cell('Collected', bold: true),
            cell('Shop signature', bold: true),
          ]),
          for (final i in inv)
            pw.TableRow(children: [cell(i.number), cell(i.shop), cell(i.area), cell(_money.format(i.amount.round()), right: true), cell(''), cell('')]),
          pw.TableRow(decoration: const pw.BoxDecoration(color: PdfColors.grey200), children: [
            cell(''),
            cell('Total (${inv.length} invoices)', bold: true),
            cell(''),
            cell(_money.format(total.round()), right: true, bold: true),
            cell(''),
            cell(''),
          ]),
        ],
      ),
      pw.SizedBox(height: 28),
      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Text('Loaded by: ____________________', style: const pw.TextStyle(fontSize: 10)),
        pw.Text('Delivery man: ____________________', style: const pw.TextStyle(fontSize: 10)),
      ]),
    ],
  ));
  return doc.save();
}
