import 'package:an_agency/settings.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import 'Admin/add_areas.dart';
import 'Admin/admin_dashboard.dart';
import 'DSR.dart';
import 'Admin/addproduct.dart';
import 'DSR_menu.dart';
import 'Load_sheet_menu.dart';
import 'invoice_menu.dart';

// ---------------------------------------------------------------------------
// Same design tokens as auth_screen.dart, so the login screen and the
// dashboard read as one product. If you use these in more places, consider
// moving this class into its own lib/design_tokens.dart and importing it
// everywhere instead of duplicating it per file.
// ---------------------------------------------------------------------------
class _Tokens {
  static const navyDark = Color(0xFF131C31);
  static const navySlate = Color(0xFF24345C);
  static const amber = Color(0xFFE8973A);
  static const bg = Color(0xFFF5F6F8);
  static const surface = Color(0xFFFFFFFF);
  static const textPrimary = Color(0xFF101828);
  static const textSecondary = Color(0xFF667085);
  static const border = Color(0xFFE4E7EC);
  static const green = Color(0xFF12B76A);
  static const greenBg = Color(0xFFE6F7EE);
  static const amberBg = Color(0xFFFCEEDA);
  static const navySlateBg = Color(0xFFE7EAF2);

  static TextStyle display({double size = 20, Color? color, FontWeight w = FontWeight.w600}) =>
      GoogleFonts.sora(fontSize: size, fontWeight: w, color: color ?? textPrimary, height: 1.2);

  static TextStyle body({double size = 13, Color? color, FontWeight w = FontWeight.w400}) =>
      GoogleFonts.inter(fontSize: size, fontWeight: w, color: color ?? textPrimary);
}

class DashboardScreen extends StatefulWidget {
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedIndex = 0;

  final List<Map<String, String>> recentOrders = [
    {'id': '001235', 'customer': 'Acme Corp', 'status': 'Delivered', 'date': '2025-06-01', 'amount': '\$1,200'},
    {'id': '001236', 'customer': 'Beta LLC', 'status': 'Pending', 'date': '2025-06-03', 'amount': '\$450'},
    {'id': '001237', 'customer': 'Gamma Inc', 'status': 'In Transit', 'date': '2025-06-02', 'amount': '\$900'},
    {'id': '001238', 'customer': 'Delta Co', 'status': 'Delivered', 'date': '2025-05-30', 'amount': '\$2,100'},
  ];

  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _pages = [
      _buildDashboardBody(),    // Index 0
      OrdersScreen(),           // Index 1
      DeliveriesScreen(),       // Index 2
      DsrReportsPage(),         // Index 3 (Handled via bottom nav or drawer)
      AdminSettingsScreen(),    // Index 4
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _Tokens.bg,
      appBar: AppBar(
        title: Text(
          'Distribution Dashboard',
          style: _Tokens.display(size: 18, color: Colors.white),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        backgroundColor: _Tokens.navyDark,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(icon: const Icon(Icons.search), onPressed: () {}),
          IconButton(icon: const Icon(Icons.notifications_none), onPressed: () {}),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: CircleAvatar(
              backgroundColor: _Tokens.amber,
              foregroundColor: _Tokens.navyDark,
              child: Text('U', style: _Tokens.body(w: FontWeight.w700, color: _Tokens.navyDark)),
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
            _buildDrawerItem(Icons.list_alt, 'Orders', 1),
            _buildDrawerItem(Icons.local_shipping_outlined, 'Deliveries', 2),
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                leading: Icon(Icons.bar_chart, color: _Tokens.textSecondary),
                title: Text('Reports', style: _Tokens.body(color: _Tokens.textPrimary, w: FontWeight.w500)),
                children: [
                  ListTile(
                    leading: Icon(Icons.inventory_2_outlined, color: _Tokens.textSecondary),
                    title: Text('Load Sheet', style: _Tokens.body()),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const LoadSheetMenuPage()));
                    },
                  ),
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
            _buildDrawerItem(Icons.settings_outlined, 'Settings', 4),
          ],
        ),
      ),
      body: _pages[_selectedIndex],
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

  Widget _buildDashboardBody() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: SingleChildScrollView(
        child: Column(
          children: [
            _buildSummaryCards(),
            const SizedBox(height: 20),
            _buildChartsSection(),
            const SizedBox(height: 20),
            _buildRecentOrdersTable(),
            const SizedBox(height: 20),
            _buildDeliveryMapPlaceholder(),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCards() {
    final cardData = [
      {'title': 'Total Orders', 'value': '1,254', 'icon': Icons.all_inbox, 'color': _Tokens.navySlate, 'bg': _Tokens.navySlateBg},
      {'title': 'Pending Deliveries', 'value': '87', 'icon': Icons.local_shipping, 'color': _Tokens.amber, 'bg': _Tokens.amberBg},
      {'title': 'Inventory Stock', 'value': '13,400 units', 'icon': Icons.inventory, 'color': _Tokens.green, 'bg': _Tokens.greenBg},
      {'title': 'Revenue Month', 'value': '\$123,000', 'icon': Icons.attach_money, 'color': _Tokens.navyDark, 'bg': _Tokens.navySlateBg},
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
                BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))
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
                      Text(
                        card['value'] as String,
                        style: _Tokens.display(size: 18),
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

  Widget _buildChartsSection() {
    return LayoutBuilder(builder: (context, constraints) {
      bool isNarrow = constraints.maxWidth < 800;
      return Flex(
        direction: isNarrow ? Axis.vertical : Axis.horizontal,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildChartCard(
            title: 'Orders & Deliveries (30 days)',
            child: _buildOrdersLineChart(),
            height: 224,
            width: isNarrow ? double.infinity : (constraints.maxWidth - 16) / 2,
          ),
          SizedBox(height: isNarrow ? 16 : 0, width: isNarrow ? 0 : 16),
          _buildChartCard(
            title: 'Inventory Distribution',
            child: _buildInventoryDonutChart(),
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
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))
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

  // Small colored-dot legend entry reused by both charts.
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

  // Line chart comparing orders placed vs. delivered across five weekly
  // buckets. Replace the two spot lists with real aggregated data when wired
  // up to a backend.
  Widget _buildOrdersLineChart() {
    final orderSpots = <FlSpot>[
      const FlSpot(0, 180), const FlSpot(1, 230), const FlSpot(2, 210),
      const FlSpot(3, 270), const FlSpot(4, 250), const FlSpot(5, 320),
    ];
    final deliverySpots = <FlSpot>[
      const FlSpot(0, 150), const FlSpot(1, 190), const FlSpot(2, 185),
      const FlSpot(3, 225), const FlSpot(4, 215), const FlSpot(5, 280),
    ];
    const weekLabels = ['W1', 'W2', 'W3', 'W4', 'W5', 'W6'];

    return Column(
      children: [
        Expanded(
          child: LineChart(
            LineChartData(
              minX: 0,
              maxX: 5,
              minY: 0,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: 100,
                getDrawingHorizontalLine: (_) => FlLine(color: _Tokens.border, strokeWidth: 1),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 34,
                    interval: 100,
                    getTitlesWidget: (value, meta) =>
                        Text(value.toInt().toString(), style: _Tokens.body(size: 10, color: _Tokens.textSecondary)),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 22,
                    getTitlesWidget: (value, meta) {
                      final i = value.toInt();
                      if (i < 0 || i >= weekLabels.length) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(weekLabels[i], style: _Tokens.body(size: 10, color: _Tokens.textSecondary)),
                      );
                    },
                  ),
                ),
              ),
              lineTouchData: const LineTouchData(enabled: false),
              lineBarsData: [
                LineChartBarData(
                  spots: orderSpots,
                  isCurved: true,
                  color: _Tokens.navySlate,
                  barWidth: 2.5,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(
                    show: true,
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [_Tokens.navySlate.withOpacity(0.16), _Tokens.navySlate.withOpacity(0.0)],
                    ),
                  ),
                ),
                LineChartBarData(
                  spots: deliverySpots,
                  isCurved: true,
                  color: _Tokens.amber,
                  barWidth: 2.5,
                  dotData: const FlDotData(show: false),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Container(width: 8, height: 8, decoration: const BoxDecoration(color: _Tokens.navySlate, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text('Orders', style: _Tokens.body(size: 12, color: _Tokens.textSecondary)),
            const SizedBox(width: 16),
            Container(width: 8, height: 8, decoration: const BoxDecoration(color: _Tokens.amber, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text('Deliveries', style: _Tokens.body(size: 12, color: _Tokens.textSecondary)),
          ],
        ),
      ],
    );
  }

  // Donut chart breaking down inventory by category, with a unit count in
  // the center and a legend with per-category totals.
  Widget _buildInventoryDonutChart() {
    final categories = [
      {'label': 'Packaged Goods', 'units': 5628, 'color': _Tokens.navySlate},
      {'label': 'Beverages', 'units': 3618, 'color': _Tokens.amber},
      {'label': 'Perishables', 'units': 2412, 'color': _Tokens.green},
      {'label': 'Other', 'units': 1742, 'color': const Color(0xFF94A3B8)},
    ];
    final total = categories.fold<int>(0, (sum, c) => sum + (c['units'] as int));

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
                  sections: categories
                      .map((c) => PieChartSectionData(
                    color: c['color'] as Color,
                    value: (c['units'] as int).toDouble(),
                    radius: 24,
                    title: '',
                  ))
                      .toList(),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${(total / 1000).toStringAsFixed(1)}k', style: _Tokens.display(size: 16)),
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
            children: categories
                .map((c) => _legendDot(
              c['color'] as Color,
              c['label'] as String,
              trailing: '${(((c['units'] as int) / total) * 100).round()}%',
            ))
                .toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildRecentOrdersTable() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _Tokens.border),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Recent Orders', style: _Tokens.display(size: 16)),
          const SizedBox(height: 12),
          LayoutBuilder(builder: (context, constraints) {
            final isMobile = constraints.maxWidth < 640;
            return isMobile ? _buildOrdersCardList() : _buildOrdersGrid();
          }),
        ],
      ),
    );
  }

  // Status color pairing used by both the grid and the mobile card list.
  (Color, Color) _statusColors(String status) {
    switch (status) {
      case 'Delivered':
        return (_Tokens.green, _Tokens.greenBg);
      case 'In Transit':
        return (_Tokens.navySlate, _Tokens.navySlateBg);
      default: // Pending
        return (_Tokens.amber, _Tokens.amberBg);
    }
  }

  // Wide-screen layout: a hand-built grid (no DataTable), so column widths
  // are always exact fractions of the available width and never overflow.
  Widget _buildOrdersGrid() {
    const flexes = [2, 3, 2, 2, 2]; // id, customer, status, date, amount
    final headers = ['Order ID', 'Customer', 'Status', 'Delivery Date', 'Amount'];

    Widget row(List<Widget> cells, {bool isHeader = false}) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        decoration: BoxDecoration(
          color: isHeader ? _Tokens.bg : Colors.transparent,
          borderRadius: isHeader ? BorderRadius.circular(8) : null,
          border: isHeader
              ? null
              : const Border(bottom: BorderSide(color: _Tokens.border, width: 1)),
        ),
        child: Row(
          children: List.generate(cells.length, (i) => Expanded(flex: flexes[i], child: cells[i])),
        ),
      );
    }

    return Column(
      children: [
        row(headers.map((h) => Text(h, style: _Tokens.body(color: _Tokens.textPrimary, w: FontWeight.w700))).toList(), isHeader: true),
        ...recentOrders.map((order) {
          final status = order['status']!;
          final (statusColor, statusBg) = _statusColors(status);
          return row([
            Text(order['id']!, style: _Tokens.body(color: _Tokens.textSecondary)),
            Text(order['customer']!, style: _Tokens.body(color: _Tokens.textPrimary), overflow: TextOverflow.ellipsis),
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: statusBg, borderRadius: BorderRadius.circular(6)),
                child: Text(status, style: _Tokens.body(color: statusColor, size: 12, w: FontWeight.w600)),
              ),
            ),
            Text(order['date']!, style: _Tokens.body(color: _Tokens.textSecondary)),
            Text(order['amount']!, style: _Tokens.body(color: _Tokens.textPrimary, w: FontWeight.w600)),
          ]);
        }),
      ],
    );
  }

  // Mobile layout: each order becomes a compact ticket-style card instead of
  // a horizontally-scrolling table, which is far easier to read on a phone.
  Widget _buildOrdersCardList() {
    return Column(
      children: recentOrders.map((order) {
        final status = order['status']!;
        final (statusColor, statusBg) = _statusColors(status);
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _Tokens.bg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _Tokens.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('#${order['id']}', style: _Tokens.body(color: _Tokens.textSecondary, w: FontWeight.w600)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: statusBg, borderRadius: BorderRadius.circular(6)),
                    child: Text(status, style: _Tokens.body(color: statusColor, size: 12, w: FontWeight.w600)),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(order['customer']!, style: _Tokens.display(size: 15)),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(order['date']!, style: _Tokens.body(color: _Tokens.textSecondary)),
                  Text(order['amount']!, style: _Tokens.body(color: _Tokens.textPrimary, w: FontWeight.w700)),
                ],
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildDeliveryMapPlaceholder() {
    return Container(
      height: 180,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _Tokens.border),
      ),
      child: Center(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.map_outlined, color: _Tokens.textSecondary),
            const SizedBox(width: 8),
            Text('Delivery Map Visualizer', style: _Tokens.body(color: _Tokens.textSecondary, w: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}

// ---------------- Orders List Sub-Screen ----------------
class OrdersScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: _Tokens.bg,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView.builder(
          itemCount: 8,
          itemBuilder: (context, index) => Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _Tokens.border),
            ),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: _Tokens.navySlateBg,
                child: Icon(Icons.article_outlined, color: _Tokens.navySlate),
              ),
              title: Text('Order #${10234 + index}', style: _Tokens.display(size: 15)),
              subtitle: Text('Customer Distribution Inc • Pending Settlement', style: _Tokens.body(color: _Tokens.textSecondary)),
              trailing: Text('\$420.00', style: _Tokens.body(w: FontWeight.w700, color: _Tokens.green, size: 14)),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------- Deliveries List Sub-Screen ----------------
class DeliveriesScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: _Tokens.bg,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView.builder(
          itemCount: 5,
          itemBuilder: (context, index) => Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _Tokens.border),
            ),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: _Tokens.amberBg,
                child: Icon(Icons.local_shipping, color: _Tokens.amber),
              ),
              title: Text('Dispatch Route Zone ${String.fromCharCode(65 + index)}', style: _Tokens.display(size: 15)),
              subtitle: Text(
                'Status: ${index % 2 == 0 ? "In Transit" : "Loading Sheet Prepared"}',
                style: _Tokens.body(color: _Tokens.textSecondary),
              ),
              trailing: Icon(Icons.arrow_forward_ios, size: 16, color: _Tokens.textSecondary),
            ),
          ),
        ),
      ),
    );
  }
}