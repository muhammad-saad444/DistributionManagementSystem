import 'package:flutter/material.dart';

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
  List<Booker> _bookers = [];
  List<CrmBook>? _books; // one per booker, same order as _bookers
  bool _failed = false;
  String? _selectedUid; // null = overview

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final bookers = await loadBookers();
      final books = await Future.wait(bookers.map((b) => loadCrmBook(userId: b.uid, bookerName: b.name)));
      if (!mounted) return;
      setState(() {
        _bookers = bookers;
        _books = books;
        _failed = false;
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    Booker? selected;
    for (final b in _bookers) {
      if (b.uid == _selectedUid) selected = b;
    }
    return Scaffold(
      backgroundColor: CrmTokens.bg,
      appBar: AppBar(
        backgroundColor: CrmTokens.navy,
        elevation: 0,
        title: Text('CRM', style: CrmTokens.display(size: 18, color: Colors.white, w: FontWeight.w600)),
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
                ..._bookers.map((b) => DropdownMenuItem<String?>(
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
    final books = _books;
    if (books == null) {
      return _failed
          ? ListView(children: const [
              SizedBox(height: 60),
              CrmEmpty(icon: Icons.cloud_off, text: "Couldn't load the CRM. Pull down to try again."),
            ])
          : const Center(child: CircularProgressIndicator(color: CrmTokens.navy));
    }
    if (books.isEmpty) {
      return ListView(children: const [CrmEmpty(icon: Icons.people_outline, text: 'No bookers found.')]);
    }

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
        ...List.generate(books.length, (i) => Padding(padding: const EdgeInsets.only(bottom: 8), child: _bookerTile(_bookers[i], books[i]))),
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

  Widget _bookerTile(Booker b, CrmBook book) {
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
