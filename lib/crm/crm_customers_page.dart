// Customers tab: the booker's shops with search, filters, due follow-ups and a profile per shop.
// The admin panel shows the same view read-only for any booker.
import 'package:firebase_auth/firebase_auth.dart';
import 'package:an_agency/ui/app_theme.dart';
import 'package:flutter/material.dart';

import '../Addshop.dart';
import 'crm_customer_profile.dart';
import 'crm_data.dart';
import 'crm_ui.dart';

class CrmCustomersPage extends StatefulWidget {
  const CrmCustomersPage({super.key});

  @override
  State<CrmCustomersPage> createState() => _CrmCustomersPageState();
}

class _CrmCustomersPageState extends State<CrmCustomersPage> {
  String? _bookerName = cachedBookerName();
  bool _nameFailed = false;

  @override
  void initState() {
    super.initState();
    if (_bookerName == null) _loadName();
  }

  Future<void> _loadName() async {
    setState(() => _nameFailed = false);
    try {
      final name = await currentBookerName();
      if (mounted) setState(() => _bookerName = name);
    } catch (_) {
      if (mounted) setState(() => _nameFailed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return Scaffold(
      backgroundColor: CrmTokens.bg,
      appBar: AppBar(
        elevation: 0,
        title: Text('Customers', style: CrmTokens.display(size: 18, color: AppColors.text, w: FontWeight.w600)),
      ),
      body: uid == null
          ? Center(child: Text('Please log in', style: CrmTokens.body(color: CrmTokens.muted)))
          : _nameFailed
              ? _retry("Couldn't reach the server. Check your connection.", _loadName)
              : _bookerName == null
              ? const Center(child: CircularProgressIndicator(color: CrmTokens.navy))
              : _bookerName!.isEmpty
                  ? Center(child: Text('Your session has no username. Log in again.', style: CrmTokens.body(color: CrmTokens.muted)))
                  : CrmCustomersView(userId: uid, bookerName: _bookerName!),
    );
  }
}

enum _Filter { all, followUps, needsVisit, owing, inactive }

enum _Sort { name, balance, lastOrder, sales }

extension on _Filter {
  String get label => switch (this) {
        _Filter.all => 'All',
        _Filter.followUps => 'Follow-ups due',
        _Filter.needsVisit => 'Needs visit',
        _Filter.owing => 'Owing',
        _Filter.inactive => 'Inactive',
      };
}

extension on _Sort {
  String get label => switch (this) {
        _Sort.name => 'Name',
        _Sort.balance => 'Balance (highest)',
        _Sort.lastOrder => 'Last order (oldest)',
        _Sort.sales => 'Total sales (highest)',
      };
}

/// A booker's shops. [readOnly] hides adding shops and all editing (admin).
class CrmCustomersView extends StatefulWidget {
  final String userId;
  final String bookerName;
  final bool readOnly;
  const CrmCustomersView({super.key, required this.userId, required this.bookerName, this.readOnly = false});

  @override
  State<CrmCustomersView> createState() => _CrmCustomersViewState();
}

class _CrmCustomersViewState extends State<CrmCustomersView> {
  // Starts from the last loaded copy (if any) so the list shows at once; _load refreshes it.
  late CrmBook? _book = cachedCrmBook(widget.userId);
  Object? _error;
  bool _refreshing = false;
  final _search = TextEditingController();
  _Filter _filter = _Filter.all;
  _Sort _sort = _Sort.name;
  String? _tag;
  bool _showAllDue = false;

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
    setState(() {
      _refreshing = true;
      _error = null;
    });
    try {
      final book = await loadCrmBook(userId: widget.userId, bookerName: widget.bookerName);
      if (!mounted) return;
      setState(() {
        _book = book;
        _refreshing = false;
      });
    } catch (e) {
      debugPrint('CRM: loading customers failed: $e');
      if (!mounted) return;
      setState(() {
        _error = e;
        _refreshing = false;
      });
      // with data already on screen, keep it and just say the refresh failed
      if (_book != null) crmSnack(context, "Couldn't refresh customers. Showing the last loaded list.", error: true);
    }
  }

  Future<void> _openCustomer(String id) async {
    final book = _book;
    if (book == null) return;
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => CrmCustomerScreen(book: book, customerId: id, readOnly: widget.readOnly)),
    );
    if (changed == true) _load();
  }

  Future<void> _addShop() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const AddCustomerPage()));
    _load();
  }

  List<CrmCustomer> _visible(CrmBook book) {
    final q = _search.text.trim().toLowerCase();
    final list = book.customers.where((c) {
      if (q.isNotEmpty &&
          !c.name.toLowerCase().contains(q) &&
          !c.code.toLowerCase().contains(q) &&
          !c.contact.contains(q) &&
          !c.area.toLowerCase().contains(q)) {
        return false;
      }
      if (_tag != null && !c.tags.contains(_tag)) return false;
      return switch (_filter) {
        _Filter.all => true,
        _Filter.followUps => c.followUps.any((f) => f.isDue),
        _Filter.needsVisit => c.needsVisit,
        _Filter.owing => c.isOwing,
        _Filter.inactive => c.isInactive,
      };
    }).toList();
    int byName(CrmCustomer a, CrmCustomer b) => a.name.toLowerCase().compareTo(b.name.toLowerCase());
    switch (_sort) {
      case _Sort.name:
        list.sort(byName);
      case _Sort.balance:
        list.sort((a, b) => b.balance.compareTo(a.balance));
      case _Sort.sales:
        list.sort((a, b) => b.totalSales.compareTo(a.totalSales));
      case _Sort.lastOrder:
        // never ordered first, then the longest since the last order
        list.sort((a, b) {
          final x = a.lastOrder, y = b.lastOrder;
          if (x == null && y == null) return byName(a, b);
          if (x == null) return -1;
          if (y == null) return 1;
          return x.compareTo(y);
        });
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final book = _book;
    Widget body;
    if (book == null && _error != null) {
      // pull-to-refresh doesn't work with a mouse on Windows, so give a button
      body = _retry("Couldn't load customers. Check your connection.", _load);
    } else if (book == null) {
      body = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: CrmTokens.navy),
            const SizedBox(height: 14),
            Text('Loading shops, sales and balances…', style: CrmTokens.body(color: CrmTokens.muted)),
          ],
        ),
      );
    } else {
      body = RefreshIndicator(color: CrmTokens.navy, onRefresh: _load, child: _list(book));
    }
    return Scaffold(
      backgroundColor: CrmTokens.bg,
      body: Column(
        children: [
          // refreshing behind data that is already shown
          if (_refreshing && book != null) const LinearProgressIndicator(minHeight: 2, color: CrmTokens.amber),
          Expanded(child: body),
        ],
      ),
      floatingActionButton: widget.readOnly
          ? null
          : FloatingActionButton.extended(
              backgroundColor: CrmTokens.amber,
              foregroundColor: CrmTokens.navyDark,
              onPressed: _addShop,
              icon: const Icon(Icons.add_business),
              label: Text('Add shop', style: CrmTokens.body(size: 13, color: CrmTokens.navyDark, w: FontWeight.w700)),
            ),
    );
  }

  Widget _list(CrmBook book) {
    final visible = _visible(book);
    final due = book.dueFollowUps;
    final tags = book.allTags;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 96),
      children: [
        _stats(book),
        if (due.isNotEmpty) ..._dueSection(book, due),
        const SizedBox(height: 14),
        TextField(
          controller: _search,
          onChanged: (_) => setState(() {}),
          decoration: crmInput('Search by name, code, phone or area', icon: Icons.search).copyWith(
            suffixIcon: _search.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => setState(_search.clear),
                  ),
          ),
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              ..._Filter.values.map((f) => Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(f.label, style: CrmTokens.body(size: 12, w: FontWeight.w600)),
                      selected: _filter == f,
                      showCheckmark: false,
                      selectedColor: CrmTokens.amberBg,
                      backgroundColor: Colors.white,
                      side: BorderSide(color: _filter == f ? CrmTokens.amber : CrmTokens.border),
                      onSelected: (_) => setState(() => _filter = f),
                    ),
                  )),
              ...tags.map((t) => Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: FilterChip(
                      avatar: const Icon(Icons.sell_outlined, size: 14),
                      label: Text(t, style: CrmTokens.body(size: 12, w: FontWeight.w600)),
                      selected: _tag == t,
                      showCheckmark: false,
                      selectedColor: CrmTokens.amberBg,
                      backgroundColor: Colors.white,
                      side: BorderSide(color: _tag == t ? CrmTokens.amber : CrmTokens.border),
                      onSelected: (on) => setState(() => _tag = on ? t : null),
                    ),
                  )),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 8, 0, 6),
          child: Row(
            children: [
              Expanded(
                child: Text('${visible.length} of ${book.customers.length} shops',
                    style: CrmTokens.body(size: 12, color: CrmTokens.muted)),
              ),
              IconButton(
                tooltip: 'Refresh',
                visualDensity: VisualDensity.compact,
                onPressed: _refreshing ? null : _load,
                icon: const Icon(Icons.refresh, size: 18, color: CrmTokens.navy),
              ),
              PopupMenuButton<_Sort>(
                initialValue: _sort,
                onSelected: (s) => setState(() => _sort = s),
                itemBuilder: (_) => _Sort.values.map((s) => PopupMenuItem(value: s, child: Text(s.label))).toList(),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.sort, size: 18, color: CrmTokens.navy),
                    const SizedBox(width: 4),
                    Text('Sort: ${_sort.label}', style: CrmTokens.body(size: 12, color: CrmTokens.navy, w: FontWeight.w600)),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (book.customers.isEmpty)
          CrmEmpty(
            icon: Icons.storefront_outlined,
            text: widget.readOnly ? 'This booker has no shops yet.' : 'No shops yet. Tap Add shop to register your first one.',
          )
        else if (visible.isEmpty)
          const CrmEmpty(icon: Icons.filter_alt_off_outlined, text: 'No shops match this search or filter.')
        else
          ...visible.map((c) => Padding(padding: const EdgeInsets.only(bottom: 8), child: _customerTile(c))),
      ],
    );
  }

  Widget _stats(CrmBook book) {
    Widget stat(String label, String value, _Filter filter, {Color? color}) => Expanded(
          child: CrmStat(
            label: label,
            value: value,
            color: color,
            onTap: () => setState(() => _filter = _filter == filter ? _Filter.all : filter),
          ),
        );
    final needsVisit = book.customers.where((c) => c.needsVisit).length;
    final due = book.dueFollowUps.length;
    return Column(
      children: [
        Row(
          children: [
            stat('Shops', '${book.customers.length}', _Filter.all),
            const SizedBox(width: 8),
            stat('Total due', crmRs(book.totalDue), _Filter.owing, color: book.totalDue > 0 ? CrmTokens.red : CrmTokens.green),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            stat('Needs visit', '$needsVisit', _Filter.needsVisit, color: needsVisit > 0 ? CrmTokens.amber : CrmTokens.navy),
            const SizedBox(width: 8),
            stat('Follow-ups due', '$due', _Filter.followUps, color: due > 0 ? CrmTokens.red : CrmTokens.navy),
          ],
        ),
      ],
    );
  }

  List<Widget> _dueSection(CrmBook book, List<CrmFollowUp> due) {
    final shown = _showAllDue ? due : due.take(3).toList();
    return [
      CrmSectionTitle(
        'Today\'s follow-ups',
        trailing: due.length > 3
            ? TextButton(
                style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                onPressed: () => setState(() => _showAllDue = !_showAllDue),
                child: Text(_showAllDue ? 'Show less' : 'Show all ${due.length}',
                    style: CrmTokens.body(size: 12, color: CrmTokens.navy, w: FontWeight.w600)),
              )
            : null,
      ),
      ...shown.map((f) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: followUpTile(
              context,
              f,
              readOnly: widget.readOnly,
              showShop: true,
              onTap: book.customer(f.customerId) == null ? null : () => _openCustomer(f.customerId),
              onChanged: (f, done) async {
                try {
                  await setFollowUpDone(f.id, done);
                  await _load();
                } catch (_) {
                  if (mounted) crmSnack(context, "Couldn't update the follow-up. Try again.", error: true);
                }
              },
            ),
          )),
    ];
  }

  Widget _customerTile(CrmCustomer c) {
    final overdue = c.openFollowUps.any((f) => f.isOverdue);
    return CrmCard(
      onTap: () => _openCustomer(c.id),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: c.isInactive ? CrmTokens.redBg : CrmTokens.amberBg,
            child: Text(c.name.characters.first.toUpperCase(),
                style: CrmTokens.display(size: 15, color: c.isInactive ? CrmTokens.red : CrmTokens.navy)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: CrmTokens.body(size: 14, w: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                  [c.area, c.type, 'Last order: ${crmAgo(c.lastOrder)}'].where((s) => s.isNotEmpty).join('  ·  '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: CrmTokens.body(size: 11, color: CrmTokens.muted),
                ),
                if (c.tags.isNotEmpty || c.needsVisit || overdue) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      if (overdue) const CrmPill('Overdue follow-up', color: CrmTokens.red, background: CrmTokens.redBg),
                      if (c.needsVisit) const CrmPill('Needs visit', background: CrmTokens.amberBg),
                      ...c.tags.map((t) => CrmPill(t)),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(crmRs(c.balance),
                  style: CrmTokens.body(size: 13, w: FontWeight.w700, color: c.isOwing ? CrmTokens.red : CrmTokens.green)),
              Text('due', style: CrmTokens.body(size: 10, color: CrmTokens.muted)),
            ],
          ),
        ],
      ),
    );
  }
}

Widget _retry(String text, VoidCallback onRetry) => Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CrmEmpty(icon: Icons.cloud_off, text: text),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, color: CrmTokens.navy),
            label: Text('Try again', style: CrmTokens.body(color: CrmTokens.navy, w: FontWeight.w600)),
          ),
        ],
      ),
    );
