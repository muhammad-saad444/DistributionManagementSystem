import 'package:flutter/material.dart';
import 'package:an_agency/ui/app_theme.dart';

import '../crm/crm_customer_profile.dart';
import '../crm/crm_customers_page.dart';
import '../crm/crm_data.dart';
import '../crm/crm_ui.dart';

/// Admin panel → CRM: an overview across all bookers (activity, overdue follow-ups, inactive shops),
/// or one booker's shops, read-only.
class AdminCrmScreen extends StatefulWidget {
  const AdminCrmScreen({super.key});

  @override
  State<AdminCrmScreen> createState() => _AdminCrmScreenState();
}

class _AdminCrmScreenState extends State<AdminCrmScreen> {
  List<Booker>? _bookers;
  // Each booker's book appears as soon as it loads, so the overview fills in instead of waiting
  // for the slowest booker. Starts from cached copies when the screen was opened before.
  final Map<String, CrmBook> _books = {};
  final Set<String> _failedUids = {};
  bool _failed = false;
  String? _selectedUid; // null = overview

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _failed = false;
      _failedUids.clear();
    });
    final List<Booker> bookers;
    try {
      bookers = await loadBookers().timeout(crmLoadTimeout);
    } catch (e) {
      debugPrint('CRM: loading bookers failed: $e');
      if (mounted) setState(() => _failed = true);
      return;
    }
    if (!mounted) return;
    setState(() {
      _bookers = bookers;
      for (final b in bookers) {
        final cached = cachedCrmBook(b.uid);
        if (cached != null) _books[b.uid] = cached;
      }
    });
    await Future.wait(bookers.map((b) async {
      try {
        final book = await loadCrmBook(userId: b.uid, bookerName: b.name);
        if (mounted) setState(() => _books[b.uid] = book);
      } catch (e) {
        debugPrint('CRM: loading ${b.name} failed: $e');
        if (mounted) setState(() => _failedUids.add(b.uid));
      }
    }));
  }

  @override
  Widget build(BuildContext context) {
    Booker? selected;
    for (final b in _bookers ?? const <Booker>[]) {
      if (b.uid == _selectedUid) selected = b;
    }
    return Scaffold(
      backgroundColor: CrmTokens.bg,
      appBar: AppBar(
        elevation: 0,
        title: Text('CRM', style: CrmTokens.display(size: 18, color: AppColors.text, w: FontWeight.w600)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
            child: DropdownButtonFormField<String?>(
              key: ValueKey(_selectedUid), // a booker tile can change the selection too
              initialValue: _selectedUid,
              isExpanded: true,
              decoration: crmInput('Booker'),
              items: [
                DropdownMenuItem<String?>(value: null, child: Text('All bookers (overview)', style: CrmTokens.body())),
                ...?_bookers?.map((b) => DropdownMenuItem<String?>(
                      value: b.uid,
                      child: Text('${b.name}  ·  ${b.email}', overflow: TextOverflow.ellipsis, style: CrmTokens.body()),
                    )),
              ],
              onChanged: (v) => setState(() => _selectedUid = v),
            ),
          ),
          Expanded(
            child: selected != null
                ? CrmCustomersView(key: ValueKey(selected.uid), userId: selected.uid, bookerName: selected.name, readOnly: true)
                : RefreshIndicator(color: CrmTokens.navy, onRefresh: _load, child: _overview()),
          ),
        ],
      ),
    );
  }

  Widget _overview() {
    final bookers = _bookers;
    if (bookers == null) {
      return _failed
          ? Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const CrmEmpty(icon: Icons.cloud_off, text: "Couldn't load the CRM. Check your connection."),
                OutlinedButton.icon(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh, color: CrmTokens.navy),
                  label: Text('Try again', style: CrmTokens.body(color: CrmTokens.navy, w: FontWeight.w600)),
                ),
              ]),
            )
          : const Center(child: CircularProgressIndicator(color: CrmTokens.navy));
    }
    if (bookers.isEmpty) {
      return ListView(children: const [CrmEmpty(icon: Icons.people_outline, text: 'No bookers found.')]);
    }

    final books = [for (final b in bookers) ?_books[b.uid]];
    final pending = bookers.where((b) => !_books.containsKey(b.uid) && !_failedUids.contains(b.uid)).length;

    final shops = books.fold(0, (s, b) => s + b.customers.length);
    final due = books.fold(0.0, (s, b) => s + b.totalDue);
    final visits7 = books.fold(0, (s, b) => s + b.visitsInLastDays(7));
    final overdue = [for (final b in books) ...b.overdueFollowUps.map((f) => (b, f))];
    final inactive = [
      for (final b in books) ...b.customers.where((c) => c.isInactive).map((c) => (b, c)),
    ]..sort((x, y) => y.$2.balance.compareTo(x.$2.balance));

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                pending > 0
                    ? 'Loading ${bookers.length - pending} of ${bookers.length} bookers…'
                    : _failedUids.isNotEmpty
                        ? "Couldn't load ${_failedUids.length} booker(s). Totals leave them out."
                        : 'All ${bookers.length} bookers loaded',
                style: CrmTokens.body(size: 12, color: _failedUids.isNotEmpty ? CrmTokens.red : CrmTokens.muted),
              ),
            ),
            if (pending > 0)
              const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: CrmTokens.navy))
            else
              IconButton(
                tooltip: 'Refresh',
                visualDensity: VisualDensity.compact,
                onPressed: _load,
                icon: const Icon(Icons.refresh, size: 18, color: CrmTokens.navy),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: CrmStat(label: 'Shops', value: '$shops')),
          const SizedBox(width: 8),
          Expanded(child: CrmStat(label: 'Total due', value: crmRs(due), color: due > 0 ? CrmTokens.red : CrmTokens.green)),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: CrmStat(label: 'Visits (7 days)', value: '$visits7')),
          const SizedBox(width: 8),
          Expanded(
            child: CrmStat(
                label: 'Overdue follow-ups', value: '${overdue.length}', color: overdue.isEmpty ? CrmTokens.navy : CrmTokens.red),
          ),
        ]),
        const CrmSectionTitle('Bookers'),
        ...bookers.map((b) => Padding(padding: const EdgeInsets.only(bottom: 8), child: _bookerTile(b, _books[b.uid]))),
        CrmSectionTitle('Overdue follow-ups (${overdue.length})'),
        if (overdue.isEmpty)
          Text('Nothing overdue.', style: CrmTokens.body(size: 12, color: CrmTokens.muted))
        else
          ...overdue.take(20).map((e) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: followUpTile(
                  context,
                  e.$2,
                  readOnly: true,
                  showShop: true,
                  onChanged: (_, _) async {},
                  onTap: () => _openCustomer(e.$1, e.$2.customerId),
                ),
              )),
        CrmSectionTitle('Inactive shops (no order in $inactiveDays+ days): ${inactive.length}'),
        if (inactive.isEmpty)
          Text('Every shop ordered in the last $inactiveDays days.', style: CrmTokens.body(size: 12, color: CrmTokens.muted))
        else
          ...inactive.take(30).map((e) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: CrmCard(
                  onTap: () => _openCustomer(e.$1, e.$2.id),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(e.$2.name, style: CrmTokens.body(size: 13, w: FontWeight.w600)),
                            Text('${e.$1.bookerName}  ·  ${e.$2.area}  ·  Last order: ${crmAgo(e.$2.lastOrder)}',
                                maxLines: 1, overflow: TextOverflow.ellipsis, style: CrmTokens.body(size: 11, color: CrmTokens.muted)),
                          ],
                        ),
                      ),
                      Text(crmRs(e.$2.balance),
                          style: CrmTokens.body(size: 13, w: FontWeight.w700, color: e.$2.isOwing ? CrmTokens.red : CrmTokens.green)),
                    ],
                  ),
                ),
              )),
        if (inactive.length > 30)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Showing 30 of ${inactive.length}. Pick a booker above to see all of their shops.',
                style: CrmTokens.body(size: 11, color: CrmTokens.muted)),
          ),
      ],
    );
  }

  Widget _bookerTile(Booker b, CrmBook? book) {
    if (book == null) {
      final failed = _failedUids.contains(b.uid);
      return CrmCard(
        onTap: () => setState(() => _selectedUid = b.uid),
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(child: Text(b.name, style: CrmTokens.body(size: 14, w: FontWeight.w600))),
            failed
                ? Text("Couldn't load", style: CrmTokens.body(size: 12, color: CrmTokens.red))
                : const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: CrmTokens.navy)),
          ],
        ),
      );
    }
    final inactive = book.customers.where((c) => c.isInactive).length;
    final overdue = book.overdueFollowUps.length;
    Widget figure(String label, String value, {Color color = CrmTokens.navy}) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, style: CrmTokens.body(size: 14, w: FontWeight.w700, color: color)),
              Text(label, style: CrmTokens.body(size: 10, color: CrmTokens.muted)),
            ],
          ),
        );
    return CrmCard(
      onTap: () => setState(() => _selectedUid = b.uid),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(b.name, style: CrmTokens.body(size: 14, w: FontWeight.w600))),
              Text(crmRs(book.totalDue), style: CrmTokens.body(size: 13, w: FontWeight.w700, color: book.totalDue > 0 ? CrmTokens.red : CrmTokens.green)),
              const Icon(Icons.chevron_right, color: CrmTokens.muted),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              figure('Shops', '${book.customers.length}'),
              figure('Visits (7d)', '${book.visitsInLastDays(7)}'),
              figure('Overdue', '$overdue', color: overdue > 0 ? CrmTokens.red : CrmTokens.navy),
              figure('Inactive', '$inactive', color: inactive > 0 ? CrmTokens.amber : CrmTokens.navy),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _openCustomer(CrmBook book, String customerId) async {
    if (book.customer(customerId) == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CrmCustomerScreen(book: book, customerId: customerId, readOnly: true)),
    );
  }
}
