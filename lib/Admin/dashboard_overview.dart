// The admin home page: a greeting band, the day's key readings as cards, what shops owe, a
// 30-day sales vs recovery chart, and breakdowns by booker, shop, product and area. Live data.
import 'dart:async';
import 'dart:math' as math;
import 'package:an_agency/ui/app_theme.dart';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../account/account.dart';
import '../ui/kpi_card.dart';
import '../inventory/purchases_screen.dart' show InventorySummaryRow;
import 'dashboard_data.dart';

class _T {
  static const navy = AppColors.navy;
  static const navyDark = AppColors.navyDark;
  static const navyMid = AppColors.navyMid;
  static const amber = AppColors.amber;
  static const amberBg = AppColors.amberBg;
  static const bg = AppColors.bg;
  static const border = AppColors.border;
  static const text = AppColors.text;
  static const muted = AppColors.muted;
  static const green = AppColors.green;
  static const greenBg = AppColors.greenBg;
  static const red = AppColors.red;
  static const redBg = AppColors.redBg;
  static const blue = AppColors.blue;
  static const blueBg = AppColors.blueBg;

  static TextStyle display(double size, {Color color = text, FontWeight w = FontWeight.w700}) =>
      GoogleFonts.inter(fontSize: size, fontWeight: w, color: color, height: 1.15);
  static TextStyle body(double size, {Color color = text, FontWeight w = FontWeight.w400}) =>
      GoogleFonts.inter(fontSize: size, fontWeight: w, color: color);
  static TextStyle caps(Color color) =>
      GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w700, color: color, letterSpacing: 0.9);
}

final _comma = NumberFormat('#,##0');

/// Rupees the way the trade reads them: Rs 12,450 · Rs 4.35 Lac · Rs 1.20 Cr.
String dashRs(num v) {
  final a = v.abs();
  final sign = v < 0 ? '-' : '';
  if (a >= 1e7) return '${sign}Rs ${(a / 1e7).toStringAsFixed(2)} Cr';
  if (a >= 1e5) return '${sign}Rs ${(a / 1e5).toStringAsFixed(2)} Lac';
  return '${sign}Rs ${_comma.format(a.round())}';
}

/// "▲ 12% vs yesterday", or null when there is nothing to compare with.
(String, bool)? _trend(double now, double before, String vs) {
  if (before <= 0) return now > 0 ? ('New $vs', true) : null;
  final pct = (now - before) / before * 100;
  return ('${pct >= 0 ? '▲' : '▼'} ${pct.abs().toStringAsFixed(0)}% vs $vs', pct >= 0);
}

class DashboardOverview extends StatefulWidget {
  /// Opens another page of the admin panel by its menu title (e.g. "Sales Orders").
  final void Function(String title) onOpen;
  const DashboardOverview({super.key, required this.onOpen});

  @override
  State<DashboardOverview> createState() => _DashboardOverviewState();
}

class _DashboardOverviewState extends State<DashboardOverview> {
  // Last figures per company, shown at once when coming back to this page.
  static final Map<String?, DashboardStats> _cache = {};

  DashboardStats? _stats;
  bool _loading = true; // still waiting for the server's figures
  Object? _error;
  StreamSubscription<DashboardLive>? _sub;

  @override
  void initState() {
    super.initState();
    _stats = _cache[Account.companyId];
    _watch();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  /// Follows the figures: the device's saved copy first, then the server's, then every change.
  void _watch() {
    _sub?.cancel();
    setState(() {
      _loading = true;
      _error = null;
    });
    final company = Account.companyId;
    _sub = watchDashboardStats().listen((r) {
      _cache[company] = r.stats;
      if (mounted) {
        setState(() {
          _stats = r.stats;
          _loading = !r.live;
        });
      }
    }, onError: (Object e) {
      debugPrint('Dashboard: $e');
      if (mounted) setState(() => _error = e);
    });
  }

  Future<void> _load() async => _watch();

  @override
  Widget build(BuildContext context) {
    final s = _stats;
    return Container(
      color: _T.bg,
      child: RefreshIndicator(
        color: _T.navy,
        onRefresh: _load,
        child: LayoutBuilder(builder: (context, box) {
          final w = box.maxWidth;
          final pad = w < 600 ? 14.0 : 22.0;
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            children: [
              Stack(children: [
                _band(),
                Padding(
                  padding: EdgeInsets.fromLTRB(pad, 20, pad, 0),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _greeting(s),
                    const SizedBox(height: 18),
                    if (s == null)
                      _placeholder(w - pad * 2)
                    else
                      _kpis(s, w - pad * 2),
                  ]),
                ),
              ]),
              if (s != null)
                Padding(
                  padding: EdgeInsets.fromLTRB(pad, 14, pad, 30),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _moneyRow(s, w - pad * 2),
                    if (Account.has('purchases')) ...[
                      const SizedBox(height: 14),
                      InventorySummaryRow(
                        onOpenStock: () => widget.onOpen('Manage Stock'),
                        onOpenPurchases: () => widget.onOpen('Purchases'),
                      ),
                    ],
                    const SizedBox(height: 14),
                    _chartCard(s),
                    const SizedBox(height: 14),
                    _pair(w - pad * 2, _bookersCard(s), _duesCard(s)),
                    const SizedBox(height: 14),
                    _pair(
                      w - pad * 2,
                      _shareCard('Top products', 'this month, by value', Icons.inventory_2_outlined, s.topProducts,
                          s.monthSales, 'No sales this month yet.'),
                      _shareCard('Sales by area', 'this month', Icons.map_outlined, s.areaSales, s.monthSales,
                          'No sales this month yet.'),
                    ),
                  ]),
                ),
            ],
          );
        }),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Header
  // ---------------------------------------------------------------------------

  Widget _band() => Container(
        height: 230,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [_T.navyDark, _T.navy, _T.navyMid],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
      );

  Widget _greeting(DashboardStats? s) {
    final now = DateTime.now();
    final hello = now.hour < 12 ? 'Good morning' : (now.hour < 17 ? 'Good afternoon' : 'Good evening');
    final name = (Account.user?.name.trim().isNotEmpty ?? false) ? Account.user!.name.trim().split(' ').first : 'Admin';
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(Account.companyName.toUpperCase(), style: _T.caps(_T.amber)),
          const SizedBox(height: 6),
          Text('$hello, $name', style: _T.display(24, color: Colors.white)),
          const SizedBox(height: 4),
          Text('Here is your overview for ${DateFormat('EEEE, d MMMM y').format(now)}.',
              style: _T.body(12.5, color: Colors.white70)),
        ]),
      ),
      const SizedBox(width: 10),
      InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: _loading ? null : _load,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white24),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            _loading
                ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: _T.amber))
                : Container(width: 8, height: 8, decoration: BoxDecoration(color: _error == null ? const Color(0xFF4ADE80) : _T.red, shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Text(
              _loading
                  ? 'Updating…'
                  : _error != null
                      ? "Couldn't update · retry"
                      : 'Live · ${DateFormat('h:mm a').format(s?.asOf ?? now)}',
              style: _T.body(11.5, color: Colors.white, w: FontWeight.w600),
            ),
          ]),
        ),
      ),
    ]);
  }

  /// The cards' outline while the first figures arrive (no spinner: the page is already here).
  Widget _placeholder(double width) {
    if (_error != null) {
      return Container(
        height: 160,
        alignment: Alignment.center,
        decoration: _card(),
        child: TextButton(onPressed: _load, child: Text("Couldn't load the dashboard. Retry", style: _T.body(13, color: _T.red))),
      );
    }
    Widget bar(double w, double h) => Container(
          width: w,
          height: h,
          decoration: BoxDecoration(color: _T.bg, borderRadius: BorderRadius.circular(6)),
        );
    final card = Container(
      decoration: _card(),
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [bar(24, 24), const SizedBox(width: 8), bar(90, 10)]),
        const SizedBox(height: 16),
        bar(110, 22),
        const SizedBox(height: 8),
        bar(70, 10),
        const Spacer(),
        bar(double.infinity, 8),
      ]),
    );
    return _grid(List.filled(8, card), width >= 940 ? 4 : 2);
  }

  // ---------------------------------------------------------------------------
  // KPI cards
  // ---------------------------------------------------------------------------

  Widget _kpis(DashboardStats s, double width) {
    final cols = width >= 940 ? 4 : 2;
    final totalBookers = s.bookers.length;
    final cards = [
      _kpi(
        label: "TODAY'S SALES",
        icon: Icons.receipt_long_outlined,
        tint: _T.blue,
        tintBg: _T.blueBg,
        value: dashRs(s.todaySales),
        sub: '${s.todayInvoices} invoice${s.todayInvoices == 1 ? '' : 's'}',
        trend: _trend(s.todaySales, s.yesterdaySales, 'yesterday'),
        spark: s.dailySales.sublist(math.max(0, s.dailySales.length - 14)),
        onTap: () => widget.onOpen('Invoices'),
      ),
      _kpi(
        label: 'RECOVERED TODAY',
        icon: Icons.payments_outlined,
        tint: _T.green,
        tintBg: _T.greenBg,
        value: dashRs(s.todayRecovered),
        sub: 'cash from shops',
        trend: _trend(s.todayRecovered, s.yesterdayRecovered, 'yesterday'),
        spark: s.dailyRecovered.sublist(math.max(0, s.dailyRecovered.length - 14)),
        onTap: Account.has('khata') ? () => widget.onOpen('Khata') : null,
      ),
      _kpi(
        label: 'THIS MONTH',
        icon: Icons.calendar_month_outlined,
        tint: _T.navy,
        tintBg: _T.amberBg,
        value: dashRs(s.monthSales),
        sub: '${s.monthInvoices} invoices',
        trend: _trend(s.monthSales, s.lastMonthSales, 'last month'),
        progress: s.monthRecoveryRate,
        progressLabel: '${(s.monthRecoveryRate * 100).toStringAsFixed(0)}% recovered',
      ),
      _kpi(
        label: 'ORDERS WAITING',
        icon: Icons.assignment_late_outlined,
        tint: s.pendingOrders > 0 ? _T.red : _T.muted,
        tintBg: s.pendingOrders > 0 ? _T.redBg : _T.bg,
        value: '${s.pendingOrders}',
        sub: s.pendingOrders > 0 ? '${dashRs(s.pendingOrdersValue)} to approve' : 'Nothing waiting for approval',
        onTap: () => widget.onOpen('Sales Orders'),
      ),
    ];
    final second = [
      _kpi(
        label: 'BOOKERS OUT TODAY',
        icon: Icons.directions_bike_outlined,
        tint: _T.navy,
        tintBg: _T.blueBg,
        value: '${s.activeBookersToday} / $totalBookers',
        sub: 'have booked invoices today',
        progress: totalBookers == 0 ? 0 : s.activeBookersToday / totalBookers,
      ),
      _kpi(
        label: 'SHOPS',
        icon: Icons.storefront_outlined,
        tint: _T.amber,
        tintBg: _T.amberBg,
        value: _comma.format(s.customers),
        sub: s.newCustomersThisMonth > 0 ? '+${s.newCustomersThisMonth} new this month' : 'No new shops this month',
        onTap: Account.has('crm') ? () => widget.onOpen('CRM') : null,
      ),
      _kpi(
        label: 'OPEN INVOICES',
        icon: Icons.pending_actions_outlined,
        tint: _T.red,
        tintBg: _T.redBg,
        value: _comma.format(s.openInvoices),
        sub: s.overdueInvoices > 0 ? '${s.overdueInvoices} older than 30 days' : 'None older than 30 days',
        subColor: s.overdueInvoices > 0 ? _T.red : null,
      ),
      _kpi(
        label: 'MONTH RECOVERED',
        icon: Icons.savings_outlined,
        tint: _T.green,
        tintBg: _T.greenBg,
        value: dashRs(s.monthRecovered),
        sub: 'since the 1st',
        spark: s.dailyRecovered,
      ),
    ];
    return _grid([...cards, ...second], cols);
  }

  // The cards themselves are shared with the accounts pages (lib/ui/kpi_card.dart).
  Widget _grid(List<Widget> items, int cols) => kpiGrid(items, cols);

  BoxDecoration _card({Color color = Colors.white}) => kpiCardDecoration(color: color);

  Widget _kpi({
    required String label,
    required IconData icon,
    required Color tint,
    required Color tintBg,
    required String value,
    required String sub,
    (String, bool)? trend,
    List<double>? spark,
    double? progress,
    String? progressLabel,
    Color? subColor,
    VoidCallback? onTap,
  }) =>
      KpiCard(
        label: label,
        icon: icon,
        tint: tint,
        tintBg: tintBg,
        value: value,
        sub: sub,
        trend: trend,
        spark: spark,
        progress: progress,
        progressLabel: progressLabel,
        subColor: subColor,
        onTap: onTap,
      );


  // ---------------------------------------------------------------------------
  // Money owed (highlighted) and the month's recovery
  // ---------------------------------------------------------------------------

  Widget _moneyRow(DashboardStats s, double width) {
    final owed = Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [_T.navyDark, _T.navy], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: _T.navy.withValues(alpha: 0.25), blurRadius: 18, offset: const Offset(0, 8))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.account_balance_wallet_outlined, size: 16, color: _T.amber),
          const SizedBox(width: 8),
          Expanded(child: Text('MARKET OUTSTANDING', style: _T.caps(Colors.white70))),
          if (Account.has('khata'))
            InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => widget.onOpen('Receivables'),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('Ageing', style: _T.body(12, color: Colors.white, w: FontWeight.w600)),
                  const Icon(Icons.chevron_right, size: 16, color: Colors.white),
                ]),
              ),
            ),
        ]),
        const SizedBox(height: 12),
        Text(dashRs(s.outstanding), style: _T.display(30, color: Colors.white)),
        const SizedBox(height: 6),
        Text('${s.shopsOwing} shop${s.shopsOwing == 1 ? '' : 's'} owe  ·  ${s.openInvoices} open invoice${s.openInvoices == 1 ? '' : 's'}',
            style: _T.body(12, color: Colors.white70)),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
          child: Row(children: [
            Icon(s.overdueInvoices > 0 ? Icons.warning_amber_rounded : Icons.check_circle_outline,
                size: 16, color: s.overdueInvoices > 0 ? _T.amber : const Color(0xFF4ADE80)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                s.overdueInvoices > 0
                    ? '${dashRs(s.overdueAmount)} unpaid for over 30 days (${s.overdueInvoices} invoice${s.overdueInvoices == 1 ? '' : 's'})'
                    : 'Nothing unpaid for over 30 days',
                style: _T.body(12, color: Colors.white, w: FontWeight.w600),
              ),
            ),
          ]),
        ),
      ]),
    );

    final rate = s.monthRecoveryRate;
    final recovery = Container(
      padding: const EdgeInsets.all(18),
      decoration: _card(),
      child: Row(children: [
        SizedBox(
          width: 92,
          height: 92,
          child: Stack(alignment: Alignment.center, children: [
            SizedBox(
              width: 92,
              height: 92,
              child: CircularProgressIndicator(
                value: rate,
                strokeWidth: 9,
                backgroundColor: _T.bg,
                valueColor: AlwaysStoppedAnimation(rate >= 0.8 ? _T.green : (rate >= 0.5 ? _T.amber : _T.red)),
                strokeCap: StrokeCap.round,
              ),
            ),
            Text('${(rate * 100).toStringAsFixed(0)}%', style: _T.display(18)),
          ]),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('RECOVERY THIS MONTH', style: _T.caps(_T.muted)),
            const SizedBox(height: 8),
            _kv('Sold', dashRs(s.monthSales)),
            _kv('Recovered', dashRs(s.monthRecovered), color: _T.green),
            _kv('Gap', dashRs(math.max(0, s.monthSales - s.monthRecovered)), color: _T.red),
          ]),
        ),
      ]),
    );
    return _pair(width, owed, recovery);
  }

  Widget _kv(String k, String v, {Color? color}) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(children: [
          SizedBox(width: 78, child: Text(k, style: _T.body(12, color: _T.muted))),
          Expanded(child: Text(v, style: _T.body(13, color: color ?? _T.text, w: FontWeight.w700))),
        ]),
      );

  Widget _pair(double width, Widget a, Widget b) {
    if (width < 820) return Column(children: [a, const SizedBox(height: 14), b]);
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(child: a),
        const SizedBox(width: 14),
        Expanded(child: b),
      ]),
    );
  }

  // ---------------------------------------------------------------------------
  // 30-day chart
  // ---------------------------------------------------------------------------

  Widget _chartCard(DashboardStats s) {
    final n = s.dailySales.length;
    final maxY = [...s.dailySales, ...s.dailyRecovered].fold<double>(0, math.max);
    final first = DateTime(s.asOf.year, s.asOf.month, s.asOf.day).subtract(Duration(days: n - 1));
    LineChartBarData line(List<double> v, Color c) => LineChartBarData(
          spots: [for (var i = 0; i < v.length; i++) FlSpot(i.toDouble(), v[i])],
          isCurved: true,
          preventCurveOverShooting: true,
          color: c,
          barWidth: 2.5,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(
            show: true,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [c.withValues(alpha: 0.16), c.withValues(alpha: 0)],
            ),
          ),
        );
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
      decoration: _card(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 14, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text('Sales vs recovery', style: _T.display(15)),
          Text('last $n days', style: _T.body(12, color: _T.muted)),
          _legend('Sales', _T.blue),
          _legend('Recovered', _T.green),
        ]),
        const SizedBox(height: 14),
        SizedBox(
          height: 220,
          child: maxY <= 0
              ? Center(child: Text('No sales or recoveries in the last $n days.', style: _T.body(12.5, color: _T.muted)))
              : LineChart(LineChartData(
                  minY: 0,
                  maxY: maxY * 1.15,
                  gridData: FlGridData(
                    drawVerticalLine: false,
                    horizontalInterval: maxY * 1.15 / 4,
                    getDrawingHorizontalLine: (_) => const FlLine(color: _T.border, strokeWidth: 1),
                  ),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 56,
                        interval: maxY * 1.15 / 4,
                        getTitlesWidget: (v, _) =>
                            Text(dashRs(v).replaceFirst('Rs ', ''), style: _T.body(10, color: _T.muted)),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        interval: 5,
                        reservedSize: 24,
                        getTitlesWidget: (v, _) {
                          final i = v.round();
                          if (i < 0 || i >= n) return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(DateFormat('d MMM').format(first.add(Duration(days: i))),
                                style: _T.body(10, color: _T.muted)),
                          );
                        },
                      ),
                    ),
                  ),
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipColor: (_) => _T.navyDark,
                      getTooltipItems: (spots) => [
                        for (final p in spots)
                          LineTooltipItem(
                            '${p.barIndex == 0 ? DateFormat('d MMM').format(first.add(Duration(days: p.x.round()))) + '\n' : ''}'
                            '${p.barIndex == 0 ? 'Sales' : 'Recovered'} ${dashRs(p.y)}',
                            _T.body(11, color: p.barIndex == 0 ? Colors.white : const Color(0xFF86EFAC), w: FontWeight.w600),
                          ),
                      ],
                    ),
                  ),
                  lineBarsData: [line(s.dailySales, _T.blue), line(s.dailyRecovered, _T.green)],
                )),
        ),
      ]),
    );
  }

  Widget _legend(String label, Color c) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 6),
        Text(label, style: _T.body(12, color: _T.muted)),
      ]);

  // ---------------------------------------------------------------------------
  // Breakdowns
  // ---------------------------------------------------------------------------

  Widget _cardTitle(String title, String sub, IconData icon, {VoidCallback? onTap}) => Row(children: [
        Icon(icon, size: 18, color: _T.navy),
        const SizedBox(width: 8),
        Text(title, style: _T.display(15)),
        const SizedBox(width: 8),
        Expanded(child: Text(sub, style: _T.body(12, color: _T.muted), overflow: TextOverflow.ellipsis)),
        if (onTap != null)
          TextButton(onPressed: onTap, child: Text('Open', style: _T.body(12, color: _T.navy, w: FontWeight.w700))),
      ]);

  Widget _bookersCard(DashboardStats s) {
    final rows = s.bookers.take(8).toList();
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      decoration: _card(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _cardTitle('Bookers today', 'sales · recovered · owed', Icons.groups_outlined,
            onTap: Account.has('khata') ? () => widget.onOpen('Booker Credits') : null),
        const SizedBox(height: 10),
        if (rows.isEmpty)
          Padding(padding: const EdgeInsets.all(16), child: Text('No bookers yet.', style: _T.body(12.5, color: _T.muted)))
        else ...[
          Row(children: [
            Expanded(flex: 4, child: Text('BOOKER', style: _T.caps(_T.muted))),
            Expanded(flex: 3, child: Text('SALES', style: _T.caps(_T.muted), textAlign: TextAlign.right)),
            Expanded(flex: 3, child: Text('RECOVERED', style: _T.caps(_T.muted), textAlign: TextAlign.right)),
            Expanded(flex: 3, child: Text('OWED', style: _T.caps(_T.muted), textAlign: TextAlign.right)),
          ]),
          const Divider(height: 14, color: _T.border),
          for (final b in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(children: [
                Expanded(
                  flex: 4,
                  child: Row(children: [
                    CircleAvatar(
                      radius: 13,
                      backgroundColor: b.invoices > 0 ? _T.amberBg : _T.bg,
                      child: Text(b.name.isEmpty ? '?' : b.name[0].toUpperCase(),
                          style: _T.body(11, color: _T.navy, w: FontWeight.w700)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(b.name, style: _T.body(12.5, w: FontWeight.w600), overflow: TextOverflow.ellipsis),
                        Text(b.invoices > 0 ? '${b.invoices} invoice${b.invoices == 1 ? '' : 's'}' : 'No invoices today',
                            style: _T.body(10.5, color: b.invoices > 0 ? _T.muted : _T.red)),
                      ]),
                    ),
                  ]),
                ),
                Expanded(flex: 3, child: Text(dashRs(b.sales), style: _T.body(12, w: FontWeight.w600), textAlign: TextAlign.right)),
                Expanded(
                    flex: 3,
                    child: Text(dashRs(b.recovered), style: _T.body(12, color: _T.green, w: FontWeight.w600), textAlign: TextAlign.right)),
                Expanded(
                    flex: 3,
                    child: Text(dashRs(b.outstanding),
                        style: _T.body(12, color: b.outstanding > 0.5 ? _T.red : _T.muted, w: FontWeight.w600),
                        textAlign: TextAlign.right)),
              ]),
            ),
        ],
      ]),
    );
  }

  Widget _duesCard(DashboardStats s) {
    final top = s.topDues;
    final maxBal = top.isEmpty ? 1.0 : top.first.balance;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      decoration: _card(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _cardTitle('Biggest dues', 'shops that owe the most', Icons.warning_amber_rounded,
            onTap: Account.has('khata') ? () => widget.onOpen('Khata') : null),
        const SizedBox(height: 10),
        if (top.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              const Icon(Icons.check_circle, color: _T.green, size: 18),
              const SizedBox(width: 8),
              Text('No shop owes money.', style: _T.body(12.5, color: _T.muted)),
            ]),
          )
        else
          for (final d in top)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(d.customer, style: _T.body(12.5, w: FontWeight.w600), overflow: TextOverflow.ellipsis)),
                  Text(dashRs(d.balance), style: _T.body(12.5, color: _T.red, w: FontWeight.w700)),
                ]),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: maxBal <= 0 ? 0 : d.balance / maxBal,
                    minHeight: 5,
                    backgroundColor: _T.bg,
                    valueColor: const AlwaysStoppedAnimation(_T.red),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  [
                    if (d.booker.isNotEmpty) d.booker,
                    if (d.oldestOpenDays > 0) 'oldest unpaid ${d.oldestOpenDays} day${d.oldestOpenDays == 1 ? '' : 's'}'
                    else 'unpaid since today',
                  ].join('  ·  '),
                  style: _T.body(10.5, color: d.oldestOpenDays > 30 ? _T.red : _T.muted),
                ),
              ]),
            ),
      ]),
    );
  }

  Widget _shareCard(String title, String sub, IconData icon, List<MapEntry<String, double>> rows, double total, String empty) {
    const colors = [_T.navy, _T.amber, _T.blue, _T.green, Color(0xFF7A8CA3), Color(0xFF94A3B8)];
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      decoration: _card(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _cardTitle(title, sub, icon),
        const SizedBox(height: 10),
        if (rows.isEmpty || total <= 0)
          Padding(padding: const EdgeInsets.all(16), child: Text(empty, style: _T.body(12.5, color: _T.muted)))
        else
          for (var i = 0; i < rows.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(width: 8, height: 8, decoration: BoxDecoration(color: colors[i % colors.length], shape: BoxShape.circle)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(rows[i].key, style: _T.body(12.5, w: FontWeight.w600), overflow: TextOverflow.ellipsis)),
                  Text(dashRs(rows[i].value), style: _T.body(12.5, w: FontWeight.w700)),
                  SizedBox(
                    width: 44,
                    child: Text('${(rows[i].value / total * 100).toStringAsFixed(0)}%',
                        style: _T.body(11.5, color: _T.muted), textAlign: TextAlign.right),
                  ),
                ]),
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: (rows[i].value / total).clamp(0, 1).toDouble(),
                    minHeight: 5,
                    backgroundColor: _T.bg,
                    valueColor: AlwaysStoppedAnimation(colors[i % colors.length]),
                  ),
                ),
              ]),
            ),
      ]),
    );
  }
}
