// One shop's CRM profile: details, sales, balance, tags, notes, activity timeline and follow-ups.
// Bookers can log visits, add follow-ups and record payments; the admin sees it read-only.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../account/account.dart';
import '../inventory/price_tiers.dart';
import '../khata.dart';
import 'crm_data.dart';
import 'crm_sheets.dart';
import 'crm_ui.dart';

class CrmCustomerScreen extends StatefulWidget {
  final CrmBook book;
  final String customerId;
  final bool readOnly;
  const CrmCustomerScreen({super.key, required this.book, required this.customerId, this.readOnly = false});

  @override
  State<CrmCustomerScreen> createState() => _CrmCustomerScreenState();
}

class _CrmCustomerScreenState extends State<CrmCustomerScreen> {
  late CrmBook _book = widget.book;
  bool _changed = false;
  bool _reloading = false;

  CrmCustomer? get _customer => _book.customer(widget.customerId);

  Future<void> _reload() async {
    setState(() => _reloading = true);
    try {
      final book = await loadCrmBook(userId: _book.userId, bookerName: _book.bookerName);
      if (!mounted) return;
      setState(() {
        _book = book;
        _reloading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _reloading = false);
      crmSnack(context, "Couldn't refresh. Pull down to try again.", error: true);
    }
  }

  /// Runs a sheet and reloads when it saved something.
  Future<void> _run(Future<bool?> Function() action, String done) async {
    final saved = await action();
    if (saved != true || !mounted) return;
    _changed = true;
    crmSnack(context, done);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final c = _customer;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _changed);
      },
      child: DefaultTabController(
        length: 3,
        child: Scaffold(
          backgroundColor: CrmTokens.bg,
          appBar: AppBar(
            backgroundColor: CrmTokens.navy,
            elevation: 0,
            iconTheme: const IconThemeData(color: Colors.white),
            title: Text(c?.name ?? 'Shop',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: CrmTokens.display(size: 17, color: Colors.white, w: FontWeight.w600)),
            bottom: TabBar(
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white60,
              indicatorColor: CrmTokens.amber,
              labelStyle: CrmTokens.body(size: 13, w: FontWeight.w600),
              tabs: [
                const Tab(text: 'Overview'),
                const Tab(text: 'Activity'),
                Tab(text: c == null || c.openFollowUps.isEmpty ? 'Follow-ups' : 'Follow-ups (${c.openFollowUps.length})'),
              ],
            ),
            actions: [
              if (_reloading)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                ),
            ],
          ),
          body: c == null
              ? const CrmEmpty(icon: Icons.storefront_outlined, text: 'This shop is no longer in your list.')
              : TabBarView(
                  children: [
                    _refreshable(_overview(c)),
                    _refreshable(_activity(c)),
                    _refreshable(_followUps(c)),
                  ],
                ),
          bottomNavigationBar: c == null || widget.readOnly ? null : _actionBar(c),
        ),
      ),
    );
  }

  Widget _refreshable(List<Widget> children) => RefreshIndicator(
        color: CrmTokens.navy,
        onRefresh: _reload,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(14, 6, 14, 24),
          children: children,
        ),
      );

  Widget _actionBar(CrmCustomer c) {
    Widget button(IconData icon, String label, VoidCallback onTap, {bool primary = false}) => Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: primary
                ? FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: CrmTokens.navy,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: onTap,
                    icon: Icon(icon, size: 18),
                    label: Text(label, style: CrmTokens.body(size: 12, color: Colors.white, w: FontWeight.w600)),
                  )
                : OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: CrmTokens.navy,
                      side: const BorderSide(color: CrmTokens.border),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: onTap,
                    icon: Icon(icon, size: 18),
                    label: Text(label, style: CrmTokens.body(size: 12, color: CrmTokens.navy, w: FontWeight.w600)),
                  ),
          ),
        );
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, -3))],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
          child: Row(
            children: [
              button(Icons.add_location_alt_outlined, 'Log visit', () => _run(() => showLogVisitSheet(context, c), 'Visit saved'),
                  primary: true),
              button(Icons.alarm_add_outlined, 'Follow-up', () => _run(() => showFollowUpSheet(context, c), 'Follow-up added')),
              button(
                  Icons.payments_outlined,
                  'Payment',
                  () => _run(
                      () => showKhataEntrySheet(context, customer: c.name, suggestedAmount: c.isOwing ? c.balance : null),
                      'Payment saved')),
            ],
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // Overview
  // ===========================================================================

  List<Widget> _overview(CrmCustomer c) {
    final lastOrder = c.lastOrder;
    return [
      const SizedBox(height: 8),
      CrmCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: CrmTokens.amberBg,
                  child: Text(c.name.characters.first.toUpperCase(), style: CrmTokens.display(size: 18, color: CrmTokens.navy)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(c.name, style: CrmTokens.display(size: 16)),
                      const SizedBox(height: 2),
                      Text([c.code, c.type, c.area].where((s) => s.isNotEmpty).join('  ·  '),
                          style: CrmTokens.body(size: 12, color: CrmTokens.muted)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, children: _statusPills(c)),
            const Divider(height: 24, color: CrmTokens.border),
            _detail(Icons.phone_outlined, 'Contact', c.contact, copy: true),
            _detail(Icons.location_on_outlined, 'Address', c.address),
            _detail(Icons.badge_outlined, 'CNIC', c.cnic, copy: true),
            _detail(Icons.receipt_outlined, 'NTN', c.ntn, copy: true),
            _detail(Icons.person_outline, 'Booker', c.salesman),
            _priceTierRow(c),
            if (c.createdAt != null) _detail(Icons.calendar_today_outlined, 'Customer since', crmDay.format(c.createdAt!)),
          ],
        ),
      ),
      const CrmSectionTitle('Sales & balance'),
      GridView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        // fixed tile height and width cap, so tiles don't stretch tall on a wide Windows window
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 240,
          mainAxisExtent: 68,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
        ),
        children: [
          CrmStat(
            label: 'Balance due',
            value: crmRs(c.balance),
            color: c.isOwing ? CrmTokens.red : CrmTokens.green,
            onTap: _openKhata,
          ),
          CrmStat(label: 'Total sales', value: crmRs(c.totalSales)),
          CrmStat(label: 'Orders', value: '${c.orderCount}'),
          CrmStat(label: 'Avg order', value: crmRs(c.averageOrder)),
          CrmStat(label: 'Last order', value: crmAgo(lastOrder), color: c.isInactive ? CrmTokens.red : CrmTokens.navy),
          CrmStat(label: 'Last visit', value: crmAgo(c.lastVisit)),
        ],
      ),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: _openKhata,
          icon: const Icon(Icons.menu_book_outlined, size: 18, color: CrmTokens.navy),
          label: Text('Open khata ledger', style: CrmTokens.body(color: CrmTokens.navy, w: FontWeight.w600)),
        ),
      ),
      CrmSectionTitle(
        'Tags',
        trailing: widget.readOnly ? null : _editButton(() => _run(() => showTagsSheet(context, c, _book.allTags), 'Tags saved')),
      ),
      c.tags.isEmpty
          ? Text(widget.readOnly ? 'No tags' : 'No tags yet. Tap Edit to group this shop, e.g. VIP or Slow payer.',
              style: CrmTokens.body(color: CrmTokens.muted, size: 12))
          : Wrap(
              spacing: 6,
              runSpacing: 6,
              children: c.tags.map((t) => CrmPill(t, background: CrmTokens.amberBg, icon: Icons.sell_outlined)).toList(),
            ),
      CrmSectionTitle(
        'Notes',
        trailing: widget.readOnly ? null : _editButton(() => _run(() => showNotesSheet(context, c), 'Notes saved')),
      ),
      CrmCard(
        child: SizedBox(
          width: double.infinity,
          child: Text(
            c.notes.trim().isEmpty ? 'No notes yet.' : c.notes,
            style: CrmTokens.body(color: c.notes.trim().isEmpty ? CrmTokens.muted : CrmTokens.textDark, size: 13),
          ),
        ),
      ),
    ];
  }

  List<Widget> _statusPills(CrmCustomer c) => [
        if (c.isOwing) const CrmPill('Owes money', color: CrmTokens.red, background: CrmTokens.redBg),
        if (c.isInactive)
          const CrmPill('Inactive', color: CrmTokens.red, background: CrmTokens.redBg, icon: Icons.trending_down)
        else
          const CrmPill('Active', color: CrmTokens.green, background: CrmTokens.greenBg),
        if (c.needsVisit) const CrmPill('Needs visit', color: CrmTokens.navy, background: CrmTokens.amberBg),
        if (c.openFollowUps.any((f) => f.isOverdue))
          const CrmPill('Overdue follow-up', color: CrmTokens.red, background: CrmTokens.redBg),
      ];

  Widget _editButton(VoidCallback onTap) => TextButton(
        style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
        onPressed: onTap,
        child: Text('Edit', style: CrmTokens.body(color: CrmTokens.navy, w: FontWeight.w600)),
      );

  /// Which product price the shop pays. The office can change it here.
  Widget _priceTierRow(CrmCustomer c) {
    if (!Account.isAdmin) return _detail(Icons.sell_outlined, 'Pays', '${tierLabel(c.priceTier)} price');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        const Icon(Icons.sell_outlined, size: 18, color: CrmTokens.muted),
        const SizedBox(width: 10),
        SizedBox(width: 104, child: Text('Pays', style: CrmTokens.body(size: 12, color: CrmTokens.muted))),
        Expanded(
          child: DropdownButton<String>(
            value: c.priceTier,
            isExpanded: true,
            underline: const SizedBox.shrink(),
            style: CrmTokens.body(size: 13, w: FontWeight.w500),
            items: [
              for (final t in priceTiers) DropdownMenuItem(value: t, child: Text('${tierLabel(t)} price')),
            ],
            onChanged: (t) {
              if (t == null || t == c.priceTier) return;
              _run(() async {
                try {
                  await updateCustomerTier(c.id, t);
                  return true;
                } catch (_) {
                  if (mounted) crmSnack(context, "Couldn't change the price type. Try again.", error: true);
                  return false;
                }
              }, '${c.name} now pays the ${tierShort(t)} price');
            },
          ),
        ),
      ]),
    );
  }

  Widget _detail(IconData icon, String label, String value, {bool copy = false}) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: CrmTokens.muted),
          const SizedBox(width: 10),
          SizedBox(width: 104, child: Text(label, style: CrmTokens.body(size: 12, color: CrmTokens.muted))),
          Expanded(child: SelectableText(value, style: CrmTokens.body(size: 13, w: FontWeight.w500))),
          if (copy)
            InkWell(
              onTap: () {
                Clipboard.setData(ClipboardData(text: value));
                crmSnack(context, '$label copied');
              },
              child: const Padding(padding: EdgeInsets.only(left: 6), child: Icon(Icons.copy, size: 16, color: CrmTokens.muted)),
            ),
        ],
      ),
    );
  }

  Future<void> _openKhata() async {
    final c = _customer;
    if (c == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => KhataShopScreen(
          userId: _book.userId,
          bookerName: _book.bookerName,
          customer: c.name,
          readOnly: widget.readOnly,
        ),
      ),
    );
    // payments may have been added or deleted in the ledger
    if (!widget.readOnly && mounted) {
      _changed = true;
      _reload();
    }
  }

  // ===========================================================================
  // Activity: visits, invoices and khata entries, newest first
  // ===========================================================================

  List<Widget> _activity(CrmCustomer c) {
    final items = <_Activity>[
      for (final v in c.visits)
        _Activity(
          date: v.date,
          order: v.createdAt,
          icon: outcomeIcon(v.outcome),
          colors: outcomeColors(v.outcome),
          title: v.outcome.label,
          subtitle: v.note,
          tag: 'Visit',
          onDelete: widget.readOnly ? null : () => _deleteVisit(v),
        ),
      for (final l in c.khata?.lines ?? const <KhataLine>[])
        _Activity(
          date: l.date,
          order: l.createdAt,
          icon: switch (l.kind) {
            KhataKind.invoice => Icons.receipt_long_outlined,
            KhataKind.payment => Icons.payments_outlined,
            KhataKind.udhaar => Icons.edit_note,
          },
          colors: switch (l.kind) {
            KhataKind.invoice => (CrmTokens.navy, CrmTokens.amberBg),
            KhataKind.payment => (CrmTokens.green, CrmTokens.greenBg),
            KhataKind.udhaar => (CrmTokens.red, CrmTokens.redBg),
          },
          title: l.title,
          subtitle: l.kind == KhataKind.invoice ? '' : l.note,
          amount: l.kind == KhataKind.payment ? '- ${crmRs(l.amount)}' : crmRs(l.amount),
          tag: l.kind == KhataKind.invoice ? 'Order' : 'Khata',
        ),
    ]..sort((a, b) {
        final byDate = DateTime(b.date.year, b.date.month, b.date.day).compareTo(DateTime(a.date.year, a.date.month, a.date.day));
        return byDate != 0 ? byDate : b.order.compareTo(a.order);
      });

    if (items.isEmpty) {
      return [
        CrmEmpty(
          icon: Icons.timeline,
          text: widget.readOnly ? 'No activity yet.' : 'No activity yet. Log a visit to start this shop\'s timeline.',
        ),
      ];
    }

    final out = <Widget>[];
    String? lastDay;
    for (final a in items) {
      final day = crmDay.format(a.date);
      if (day != lastDay) {
        out.add(Padding(
          padding: const EdgeInsets.fromLTRB(2, 14, 2, 6),
          child: Text(daysSince(a.date) <= 1 ? '${crmAgo(a.date)} · $day' : day,
              style: CrmTokens.body(size: 12, color: CrmTokens.muted, w: FontWeight.w600)),
        ));
        lastDay = day;
      }
      out.add(Padding(padding: const EdgeInsets.only(bottom: 8), child: _activityTile(a)));
    }
    return out;
  }

  Widget _activityTile(_Activity a) {
    final (fg, bg) = a.colors;
    return CrmCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(radius: 17, backgroundColor: bg == CrmTokens.bg ? CrmTokens.border : bg, child: Icon(a.icon, size: 18, color: fg)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(a.title, style: CrmTokens.body(size: 13, w: FontWeight.w600))),
                    if (a.amount != null) Text(a.amount!, style: CrmTokens.body(size: 13, color: fg, w: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: 2),
                Text(a.tag, style: CrmTokens.body(size: 11, color: CrmTokens.muted)),
                if (a.subtitle.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(a.subtitle, style: CrmTokens.body(size: 12)),
                ],
              ],
            ),
          ),
          if (a.onDelete != null)
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Delete visit',
              icon: const Icon(Icons.delete_outline, size: 18, color: CrmTokens.muted),
              onPressed: a.onDelete,
            ),
        ],
      ),
    );
  }

  Future<void> _deleteVisit(CrmVisit v) async {
    final ok = await _confirm('Delete this visit?', '${v.outcome.label} on ${crmDay.format(v.date)} will be removed.');
    if (ok != true) return;
    try {
      await deleteVisit(v.id);
      _changed = true;
      await _reload();
    } catch (_) {
      if (mounted) crmSnack(context, "Couldn't delete the visit. Try again.", error: true);
    }
  }

  // ===========================================================================
  // Follow-ups
  // ===========================================================================

  List<Widget> _followUps(CrmCustomer c) {
    final open = c.followUps.where((f) => !f.done).toList();
    final done = c.followUps.where((f) => f.done).toList();
    if (c.followUps.isEmpty) {
      return [
        CrmEmpty(
          icon: Icons.alarm_outlined,
          text: widget.readOnly ? 'No follow-ups.' : 'No follow-ups. Add one to get reminded about a payment, order or call.',
        ),
      ];
    }
    return [
      if (open.isNotEmpty) const CrmSectionTitle('Open'),
      ...open.map((f) => Padding(padding: const EdgeInsets.only(bottom: 8), child: followUpTile(context, f, readOnly: widget.readOnly, onChanged: _onFollowUpChanged, onDelete: _deleteFollowUp))),
      if (done.isNotEmpty) const CrmSectionTitle('Done'),
      ...done.map((f) => Padding(padding: const EdgeInsets.only(bottom: 8), child: followUpTile(context, f, readOnly: widget.readOnly, onChanged: _onFollowUpChanged, onDelete: _deleteFollowUp))),
    ];
  }

  Future<void> _onFollowUpChanged(CrmFollowUp f, bool done) async {
    try {
      await setFollowUpDone(f.id, done);
      _changed = true;
      await _reload();
    } catch (_) {
      if (mounted) crmSnack(context, "Couldn't update the follow-up. Try again.", error: true);
    }
  }

  Future<void> _deleteFollowUp(CrmFollowUp f) async {
    final ok = await _confirm('Delete this follow-up?', f.title);
    if (ok != true) return;
    try {
      await deleteFollowUp(f.id);
      _changed = true;
      await _reload();
    } catch (_) {
      if (mounted) crmSnack(context, "Couldn't delete the follow-up. Try again.", error: true);
    }
  }

  Future<bool?> _confirm(String title, String body) => showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title, style: CrmTokens.display(size: 16)),
          content: Text(body, style: CrmTokens.body()),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Delete', style: CrmTokens.body(color: CrmTokens.red, w: FontWeight.w600)),
            ),
          ],
        ),
      );
}

class _Activity {
  final DateTime date;
  final DateTime order;
  final IconData icon;
  final (Color, Color) colors;
  final String title;
  final String subtitle;
  final String? amount;
  final String tag;
  final VoidCallback? onDelete;

  _Activity({
    required this.date,
    required this.order,
    required this.icon,
    required this.colors,
    required this.title,
    required this.subtitle,
    required this.tag,
    this.amount,
    this.onDelete,
  });
}

/// A follow-up row with a done checkbox. [showShop] adds the shop name (for lists across shops).
Widget followUpTile(
  BuildContext context,
  CrmFollowUp f, {
  required bool readOnly,
  required Future<void> Function(CrmFollowUp, bool) onChanged,
  Future<void> Function(CrmFollowUp)? onDelete,
  bool showShop = false,
  VoidCallback? onTap,
}) {
  final dueColor = f.done ? CrmTokens.muted : (f.isOverdue ? CrmTokens.red : (f.isDueToday ? CrmTokens.amber : CrmTokens.muted));
  return CrmCard(
    onTap: onTap,
    padding: const EdgeInsets.fromLTRB(4, 6, 6, 6),
    child: Row(
      children: [
        Checkbox(
          value: f.done,
          activeColor: CrmTokens.green,
          onChanged: readOnly ? null : (v) => onChanged(f, v ?? false),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showShop) Text(f.customer, style: CrmTokens.body(size: 11, color: CrmTokens.muted, w: FontWeight.w600)),
              Text(
                f.title,
                style: CrmTokens.body(size: 13, w: FontWeight.w600, color: f.done ? CrmTokens.muted : CrmTokens.textDark).copyWith(
                  decoration: f.done ? TextDecoration.lineThrough : null,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                f.done ? 'Done ${crmAgo(f.doneAt, never: '')}'.trim() : crmDue(f),
                style: CrmTokens.body(size: 11, color: dueColor, w: FontWeight.w600),
              ),
              if (f.note.trim().isNotEmpty) Text(f.note, style: CrmTokens.body(size: 12, color: CrmTokens.muted)),
            ],
          ),
        ),
        if (!readOnly && onDelete != null)
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Delete follow-up',
            icon: const Icon(Icons.delete_outline, size: 18, color: CrmTokens.muted),
            onPressed: () => onDelete(f),
          ),
      ],
    ),
  );
}
