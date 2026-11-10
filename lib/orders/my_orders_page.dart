// A booker's sales orders and where each stands (waiting, invoiced, rejected).
import 'package:flutter/material.dart';
import 'package:an_agency/ui/app_theme.dart';

import '../crm/crm_ui.dart';
import 'orders_data.dart';

(String, Color, Color) soStatusLook(String status) => switch (status) {
      'invoiced' => ('Invoiced', CrmTokens.green, CrmTokens.greenBg),
      'rejected' => ('Rejected', CrmTokens.red, CrmTokens.redBg),
      'cancelled' => ('Cancelled', CrmTokens.muted, CrmTokens.bg),
      _ => ('Waiting for approval', CrmTokens.amber, CrmTokens.amberBg),
    };

class MySalesOrdersPage extends StatefulWidget {
  const MySalesOrdersPage({super.key});

  @override
  State<MySalesOrdersPage> createState() => _MySalesOrdersPageState();
}

class _MySalesOrdersPageState extends State<MySalesOrdersPage> {
  List<SalesOrder>? _orders;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final o = await loadMySalesOrders();
      if (mounted) setState(() => _orders = o);
    } catch (e) {
      debugPrint('My sales orders: $e');
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final orders = _orders;
    return Scaffold(
      backgroundColor: CrmTokens.bg,
      appBar: AppBar(
        title: Text('My sales orders', style: CrmTokens.display(size: 18, color: AppColors.text, w: FontWeight.w600)),
      ),
      body: orders == null
          ? Center(
              child: _error == null
                  ? const CircularProgressIndicator(color: CrmTokens.navy)
                  : OutlinedButton(onPressed: _load, child: Text('Try again', style: CrmTokens.body(color: CrmTokens.navy))),
            )
          : RefreshIndicator(
              color: CrmTokens.navy,
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(14),
                children: [
                  if (orders.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 60),
                      child: CrmEmpty(icon: Icons.assignment_outlined, text: 'No orders yet. Book one from Book Order.'),
                    ),
                  for (final o in orders) _card(o),
                ],
              ),
            ),
    );
  }

  Widget _card(SalesOrder o) {
    final (label, color, bg) = soStatusLook(o.status);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: CrmCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('${o.number}  ·  ${o.customer}', style: CrmTokens.display(size: 15))),
            CrmPill(label, color: color, background: bg),
          ]),
          const SizedBox(height: 3),
          Text(
            [
              o.salesDate,
              '${o.items.length} product${o.items.length == 1 ? '' : 's'}',
              crmRs(o.grandTotal),
              if (o.invoiceNumber.isNotEmpty) 'invoice #${o.invoiceNumber}',
            ].join('  ·  '),
            style: CrmTokens.body(size: 12, color: CrmTokens.muted),
          ),
          if (o.decisionNote.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Office: ${o.decisionNote}', style: CrmTokens.body(size: 12, color: color)),
            ),
          if (o.status == 'pending')
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () async {
                  try {
                    await cancelMySalesOrder(o);
                    _load();
                  } catch (_) {
                    if (mounted) crmSnack(context, "Couldn't cancel. It may already be approved.", error: true);
                  }
                },
                child: Text('Cancel order', style: CrmTokens.body(color: CrmTokens.muted)),
              ),
            ),
        ]),
      ),
    );
  }
}
