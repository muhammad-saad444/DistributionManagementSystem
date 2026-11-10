import 'package:an_agency/settings.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'account/account.dart';
import 'crm/crm_data.dart' show currentBookerName;
import 'DSR_menu.dart';
import 'Load_sheet_menu.dart';
import 'invoice_menu.dart';
import 'hr/my_hr_page.dart';

// ---------------------------------------------------------------------------
// Same design tokens as auth_screen.dart, so the login screen and the
// dashboard read as one product. If you use these in more places, consider
// moving this class into its own lib/design_tokens.dart and importing it
// everywhere instead of duplicating it per file.
// ---------------------------------------------------------------------------
class _Tokens {
  static const navyDark = Color(0xFF15294D);
  static const navySlate = Color(0xFF22406F);
  static const amber = Color(0xFFE0A63A);
  static const bg = Color(0xFFF5F6FA);
  static const textPrimary = Color(0xFF1E2430);
  static const textSecondary = Color(0xFF6B7280);
  static const border = Color(0xFFE3E7EF);
  static const green = Color(0xFF2E8B57);
  static const greenBg = Color(0xFFE6F4EC);
  static const amberBg = Color(0xFFFBF0DC);
  static const navySlateBg = Color(0xFFE7EDF8);

  static TextStyle display({double size = 20, Color? color, FontWeight w = FontWeight.w600}) =>
      GoogleFonts.sora(fontSize: size, fontWeight: w, color: color ?? textPrimary, height: 1.2);

  static TextStyle body({double size = 13, Color? color, FontWeight w = FontWeight.w400}) =>
      GoogleFonts.inter(fontSize: size, fontWeight: w, color: color ?? textPrimary);
}

final _rs = NumberFormat('#,##0');
final _day = DateFormat('dd MMM');

/// One of the booker's invoices, as the dashboard needs it.
class _Order {
  final String number;
  final String shop;
  final DateTime date; // the Sales Date
  final num total;
  final Map<String, num> units; // product → QTY + FOC
  const _Order(this.number, this.shop, this.date, this.total, this.units);
}

num _num(dynamic v) => v is num ? v : (num.tryParse('${v ?? ''}'.trim()) ?? 0);

DateTime? _salesDate(Map<String, dynamic> m) {
  final ts = m['salesDateTs'];
  if (ts is Timestamp) return ts.toDate();
  final s = (m['salesDate'] ?? '').toString(); // dd-MM-yyyy
  final p = s.split('-');
  if (p.length == 3) {
    final d = int.tryParse(p[0]), mo = int.tryParse(p[1]), y = int.tryParse(p[2]);
    if (d != null && mo != null && y != null) return DateTime(y, mo, d);
  }
  final c = m['createdAt'];
  return c is Timestamp ? c.toDate() : null;
}

/// The signed-in booker's own invoices (in their company) and shops.
Future<(List<_Order>, int)> _loadMine() async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return (<_Order>[], 0);
  final name = await currentBookerName();
  final results = await Future.wait([
    companyCol('invoices').where('userId', isEqualTo: uid).get(),
    if (name.isNotEmpty) companyCol('customers').where('salesman', isEqualTo: name).get(),
  ]);
  final orders = <_Order>[];
  for (final d in results[0].docs) {
    final m = d.data();
    final date = _salesDate(m);
    if (date == null) continue;
    final units = <String, num>{};
    for (final it in (m['items'] as List? ?? const [])) {
      if (it is! Map) continue;
      final p = (it['Product Name'] ?? '').toString().trim();
      if (p.isEmpty) continue;
      units[p] = (units[p] ?? 0) + _num(it['QTY']) - _num(it['returnQty']) + _num(it['BNS'] ?? it['FOC']);
    }
    orders.add(_Order((m['invoiceNumber'] ?? '').toString(), (m['customer'] ?? '').toString(), date,
        _num(m['grandTotal'] ?? m['total']), units));
  }
  orders.sort((a, b) => b.date.compareTo(a.date));
  final shops = results.length > 1 ? results[1].docs.length : 0;
  return (orders, shops);
}

class DashboardScreen extends StatefulWidget {
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedIndex = 0;
  List<_Order>? _orders;
  int _shops = 0;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final (orders, shops) = await _loadMine();
      if (!mounted) return;
      setState(() {
        _orders = orders;
        _shops = shops;
      });
    } catch (e) {
      debugPrint('Booker dashboard failed: $e');
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [_buildDashboardBody(), _buildMyOrders(), AdminSettingsScreen()];
    return Scaffold(
      backgroundColor: _Tokens.bg,
      appBar: AppBar(
        title: Text(
          Account.company?.name ?? 'Dashboard',
          style: _Tokens.display(size: 18, color: Colors.white),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        backgroundColor: _Tokens.navyDark,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh), onPressed: _load),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: CircleAvatar(
              backgroundColor: _Tokens.amber,
              foregroundColor: _Tokens.navyDark,
              child: Text(
                (Account.user?.display ?? 'U').isEmpty ? 'U' : Account.user!.display[0].toUpperCase(),
                style: _Tokens.body(w: FontWeight.w700, color: _Tokens.navyDark),
              ),
            ),
          )
        ],
      ),
      drawer: Drawer(
        backgroundColor: Colors.white,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            Container(
              width: double.infinity,
              color: _Tokens.navyDark,
              padding: const EdgeInsets.fromLTRB(20, 56, 20, 24),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: _Tokens.amber,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.route_outlined, color: _Tokens.navyDark, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Text('Menu', style: _Tokens.display(size: 18, color: Colors.white)),
                ],
              ),
            ),
            const SizedBox(height: 8),
            _buildDrawerItem(Icons.dashboard_outlined, 'Dashboard', 0),
            _buildDrawerItem(Icons.list_alt, 'My orders', 1),
            if (Account.has('hr'))
              ListTile(
                leading: Icon(Icons.badge_outlined, color: _Tokens.textSecondary),
                title: Text('My attendance and pay', style: _Tokens.body(color: _Tokens.textPrimary, w: FontWeight.w500)),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const MyHrPage()));
                },
              ),
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                leading: Icon(Icons.bar_chart, color: _Tokens.textSecondary),
                title: Text('Reports', style: _Tokens.body(color: _Tokens.textPrimary, w: FontWeight.w500)),
                children: [
                  if (Account.has('loadsheet'))
                    ListTile(
                      leading: Icon(Icons.inventory_2_outlined, color: _Tokens.textSecondary),
                      title: Text('Load Sheet', style: _Tokens.body()),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const LoadSheetMenuPage()));
                      },
                    ),
                  if (Account.has('dsr'))
                    ListTile(
                      leading: Icon(Icons.analytics_outlined, color: _Tokens.textSecondary),
                      title: Text('DSR Reports', style: _Tokens.body()),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const DsrMenuPage()));
                      },
                    ),
                  ListTile(
                    leading: Icon(Icons.analytics_outlined, color: _Tokens.textSecondary),
                    title: Text('Invoice Reports', style: _Tokens.body()),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const InvoiceMenuPage()));
                    },
                  ),
                ],
              ),
            ),
            _buildDrawerItem(Icons.settings_outlined, 'Settings', 2),
          ],
        ),
      ),
      body: pages[_selectedIndex],
    );
  }

  Widget _buildDrawerItem(IconData icon, String title, int index) {
    final isSelected = _selectedIndex == index;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isSelected ? _Tokens.amberBg : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        leading: Icon(icon, color: isSelected ? _Tokens.navyDark : _Tokens.textSecondary),
        title: Text(
          title,
          style: _Tokens.body(
            color: isSelected ? _Tokens.navyDark : _Tokens.textPrimary,
            w: isSelected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
        onTap: () {
          setState(() {
            _selectedIndex = index;
            Navigator.pop(context);
          });
        },
      ),
    );
  }

  /// Loading, error or the content built from the booker's orders.
  Widget _withOrders(Widget Function(List<_Order>) build) {
    final orders = _orders;
    if (orders != null) return build(orders);
    if (_error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text("Couldn't load your orders.", style: _Tokens.body(color: _Tokens.textSecondary)),
          TextButton(onPressed: _load, child: Text('Try again', style: _Tokens.body(color: _Tokens.navySlate))),
        ]),
      );
    }
    return const Center(child: CircularProgressIndicator(color: _Tokens.navySlate));
  }

  Widget _buildDashboardBody() {
    return _withOrders((orders) => RefreshIndicator(
          onRefresh: _load,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                if (Account.has('hr')) const HrCheckInCard(),
                _buildSummaryCards(orders),
                const SizedBox(height: 20),
                _buildChartsSection(orders),
                const SizedBox(height: 20),
                _buildRecentOrders(orders.take(5).toList()),
              ],
            ),
          ),
        ));
  }

  bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  Widget _buildSummaryCards(List<_Order> orders) {
    final now = DateTime.now();
    final today = orders.where((o) => _sameDay(o.date, now)).toList();
    final month = orders.where((o) => o.date.year == now.year && o.date.month == now.month).toList();
    final cardData = [
      {
        'title': 'Orders today',
        'value': '${today.length}  ·  Rs. ${_rs.format(today.fold<num>(0, (s, o) => s + o.total))}',
        'icon': Icons.today_outlined,
        'color': _Tokens.amber,
        'bg': _Tokens.amberBg,
      },
      {
        'title': 'Orders this month',
        'value': '${month.length}',
        'icon': Icons.all_inbox,
        'color': _Tokens.navySlate,
        'bg': _Tokens.navySlateBg,
      },
      {
        'title': 'Sales this month',
        'value': 'Rs. ${_rs.format(month.fold<num>(0, (s, o) => s + o.total))}',
        'icon': Icons.payments_outlined,
        'color': _Tokens.green,
        'bg': _Tokens.greenBg,
      },
      {
        'title': 'My shops',
        'value': '$_shops',
        'icon': Icons.storefront_outlined,
        'color': _Tokens.navyDark,
        'bg': _Tokens.navySlateBg,
      },
    ];

    return LayoutBuilder(builder: (context, constraints) {
      double cardWidth = (constraints.maxWidth - 48) / 4;
      if (constraints.maxWidth < 700) cardWidth = (constraints.maxWidth - 32) / 2;
      if (constraints.maxWidth < 450) cardWidth = constraints.maxWidth;

      return Wrap(
        spacing: 16,
        runSpacing: 16,
        children: cardData.map((card) {
          final baseColor = card['color'] as Color;
          final bgColor = card['bg'] as Color;
          return Container(
            width: cardWidth,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _Tokens.border),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 2))
              ],
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: bgColor,
                  child: Icon(card['icon'] as IconData, color: baseColor, size: 22),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        card['title'] as String,
                        style: _Tokens.body(size: 12, color: _Tokens.textSecondary, w: FontWeight.w500),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(card['value'] as String, style: _Tokens.display(size: 18)),
                      ),
                    ],
                  ),
                )
              ],
            ),
          );
        }).toList(),
      );
    });
  }

  Widget _buildChartsSection(List<_Order> orders) {
    return LayoutBuilder(builder: (context, constraints) {
      bool isNarrow = constraints.maxWidth < 800;
      return Flex(
        direction: isNarrow ? Axis.vertical : Axis.horizontal,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildChartCard(
            title: 'My sales (last 7 days)',
            child: _buildSalesChart(orders),
            height: 224,
            width: isNarrow ? double.infinity : (constraints.maxWidth - 16) / 2,
          ),
          SizedBox(height: isNarrow ? 16 : 0, width: isNarrow ? 0 : 16),
          _buildChartCard(
            title: 'Top products this month',
            child: _buildTopProducts(orders),
            height: 224,
            width: isNarrow ? double.infinity : (constraints.maxWidth - 16) / 2,
          ),
        ],
      );
    });
  }

  Widget _buildChartCard({required String title, required Widget child, double? width, double height = 160}) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _Tokens.border),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: _Tokens.display(size: 15)),
          const SizedBox(height: 12),
          SizedBox(height: height, child: child),
        ],
      ),
    );
  }

  Widget _empty(String text) =>
      Center(child: Text(text, textAlign: TextAlign.center, style: _Tokens.body(color: _Tokens.textSecondary)));

  // Small colored-dot legend entry.
  Widget _legendDot(Color color, String label, {String? trailing}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: _Tokens.body(color: _Tokens.textSecondary), overflow: TextOverflow.ellipsis)),
          if (trailing != null) Text(trailing, style: _Tokens.body(w: FontWeight.w600, size: 12)),
        ],
      ),
    );
  }

  /// The booker's sales for each of the last 7 days (by Sales Date).
  Widget _buildSalesChart(List<_Order> orders) {
    final now = DateTime.now();
    final days = [for (var i = 6; i >= 0; i--) DateTime(now.year, now.month, now.day - i)];
    final totals = [for (final d in days) orders.where((o) => _sameDay(o.date, d)).fold<num>(0, (s, o) => s + o.total)];
    if (totals.every((t) => t == 0)) return _empty('No orders in the last 7 days');
    final maxY = totals.reduce((a, b) => a > b ? a : b).toDouble() * 1.15;

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: 6,
        minY: 0,
        maxY: maxY,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: maxY / 4,
          getDrawingHorizontalLine: (_) => const FlLine(color: _Tokens.border, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 44,
              interval: maxY / 4,
              getTitlesWidget: (value, meta) => Text(NumberFormat.compact().format(value),
                  style: _Tokens.body(size: 10, color: _Tokens.textSecondary)),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              interval: 1,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= days.length) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(DateFormat('E').format(days[i]), style: _Tokens.body(size: 10, color: _Tokens.textSecondary)),
                );
              },
            ),
          ),
        ),
        lineTouchData: const LineTouchData(enabled: false),
        lineBarsData: [
          LineChartBarData(
            spots: [for (var i = 0; i < totals.length; i++) FlSpot(i.toDouble(), totals[i].toDouble())],
            isCurved: true,
            preventCurveOverShooting: true,
            color: _Tokens.navySlate,
            barWidth: 2.5,
            dotData: const FlDotData(show: true),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [_Tokens.navySlate.withValues(alpha: 0.16), _Tokens.navySlate.withValues(alpha: 0.0)],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The four products the booker sold most units of this month, plus the rest.
  Widget _buildTopProducts(List<_Order> orders) {
    final now = DateTime.now();
    final units = <String, num>{};
    for (final o in orders.where((o) => o.date.year == now.year && o.date.month == now.month)) {
      o.units.forEach((p, u) => units[p] = (units[p] ?? 0) + u);
    }
    final ranked = units.entries.where((e) => e.value > 0).toList()..sort((a, b) => b.value.compareTo(a.value));
    if (ranked.isEmpty) return _empty('No products sold this month yet');
    const colors = [_Tokens.navySlate, _Tokens.amber, _Tokens.green, Color(0xFF6172F3), Color(0xFF94A3B8)];
    final slices = <(String, num)>[
      for (final e in ranked.take(4)) (e.key, e.value),
      if (ranked.length > 4) ('Other', ranked.skip(4).fold<num>(0, (s, e) => s + e.value)),
    ];
    final total = slices.fold<num>(0, (s, c) => s + c.$2);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 130,
          height: 130,
          child: Stack(
            alignment: Alignment.center,
            children: [
              PieChart(
                PieChartData(
                  sectionsSpace: 2,
                  centerSpaceRadius: 38,
                  sections: [
                    for (var i = 0; i < slices.length; i++)
                      PieChartSectionData(color: colors[i], value: slices[i].$2.toDouble(), radius: 24, title: ''),
                  ],
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(NumberFormat.compact().format(total), style: _Tokens.display(size: 16)),
                  Text('units', style: _Tokens.body(size: 11, color: _Tokens.textSecondary)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < slices.length; i++)
                _legendDot(colors[i], slices[i].$1, trailing: '${(slices[i].$2 / total * 100).round()}%'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRecentOrders(List<_Order> orders) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _Tokens.border),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('My recent orders', style: _Tokens.display(size: 16)),
          const SizedBox(height: 12),
          if (orders.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: _empty('No orders yet. Book one from Book Order.'),
            )
          else
            for (final o in orders) _orderTile(o),
        ],
      ),
    );
  }

  Widget _orderTile(_Order o) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _Tokens.bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _Tokens.border),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: _Tokens.navySlateBg,
            child: const Icon(Icons.receipt_long_outlined, size: 18, color: _Tokens.navySlate),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(o.shop.isEmpty ? '(no shop)' : o.shop, style: _Tokens.body(w: FontWeight.w600), overflow: TextOverflow.ellipsis),
              Text('Invoice #${o.number}  ·  ${_day.format(o.date)}', style: _Tokens.body(size: 12, color: _Tokens.textSecondary)),
            ]),
          ),
          Text('Rs. ${_rs.format(o.total)}', style: _Tokens.body(w: FontWeight.w700)),
        ],
      ),
    );
  }

  /// Every order the booker has booked, newest first.
  Widget _buildMyOrders() {
    return _withOrders((orders) => RefreshIndicator(
          onRefresh: _load,
          child: orders.isEmpty
              ? ListView(children: [const SizedBox(height: 80), _empty('No orders yet. Book one from Book Order.')])
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text('${orders.length} orders  ·  Rs. ${_rs.format(orders.fold<num>(0, (s, o) => s + o.total))}',
                        style: _Tokens.body(color: _Tokens.textSecondary)),
                    const SizedBox(height: 10),
                    for (final o in orders) _orderTile(o),
                  ],
                ),
        ));
  }
}
