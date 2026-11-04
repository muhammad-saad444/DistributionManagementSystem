// ============================================================================
// CLASSIC + COLOR ACCENT DASHBOARD
// MODERN LEFT SIDEBAR + SLIDING DRAWER ON SMALL SCREENS
// HIGH PERFORMANCE OPTIMIZED - ZERO-WAIT INSTANT APPEARANCE (0 SECONDS)
// ============================================================================

import 'dart:convert';
import '../account/account.dart';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:shimmer/shimmer.dart';

import 'booker_credit_report_screen.dart';
import 'stock_management.dart';
import 'user_dsr_report_screen.dart';
import 'user_invoices.dart';
import 'add_areas.dart';
import 'addproduct.dart';
import '../settings.dart';
import 'allocate_customer.dart';
import 'admin_khata_screen.dart';
import 'admin_crm_screen.dart';
import '../inventory/purchases_screen.dart';
import '../inventory/warehouses_screen.dart';

// Design tokens
class _Tokens {
  static const navy = Color(0xFF15294D);
  static const amber = Color(0xFFE0A63A);
  static const bg = Color(0xFFF5F6FA);
  static const border = Color(0xFFE3E7EF);
  static const textDark = Color(0xFF1E2430);
  static const muted = Color(0xFF6B7280);
}

class AdminDashboardData {
  final int usersCount;
  final int customersCount;
  final int areasCount;
  final int revenue;
  final List<FlSpot> weeklySpots;
  final double maxWeeklySpotY;
  final Map<String, int> areaDistribution;
  final Map<String, int> topProducts;
  final List<Map<String, String>> activities;
  final DateTime lastUpdated;

  const AdminDashboardData({
    this.usersCount = 0,
    this.customersCount = 0,
    this.areasCount = 0,
    this.revenue = 0,
    this.weeklySpots = const [],
    this.maxWeeklySpotY = 100.0,
    this.areaDistribution = const {},
    this.topProducts = const {},
    this.activities = const [],
    required this.lastUpdated,
  });

  Map<String, dynamic> toJson() => {
    'usersCount': usersCount,
    'customersCount': customersCount,
    'areasCount': areasCount,
    'revenue': revenue,
    'weeklySpots': weeklySpots.map((s) => {'x': s.x, 'y': s.y}).toList(),
    'maxWeeklySpotY': maxWeeklySpotY,
    'areaDistribution': areaDistribution,
    'topProducts': topProducts,
    'activities': activities,
    'lastUpdated': lastUpdated.toIso8601String(),
  };

  factory AdminDashboardData.fromJson(Map<String, dynamic> json) {
    final spotsList = (json['weeklySpots'] as List?) ?? [];
    final List<FlSpot> spots = [];
    for (var it in spotsList) {
      if (it is Map) {
        spots.add(FlSpot(
          (it['x'] as num?)?.toDouble() ?? 0.0,
          (it['y'] as num?)?.toDouble() ?? 0.0,
        ));
      }
    }

    DateTime parsedDate;
    try {
      parsedDate = DateTime.parse(json['lastUpdated']?.toString() ?? '');
    } catch (_) {
      parsedDate = DateTime.now();
    }

    return AdminDashboardData(
      usersCount: (json['usersCount'] as num?)?.toInt() ?? 0,
      customersCount: (json['customersCount'] as num?)?.toInt() ?? 0,
      areasCount: (json['areasCount'] as num?)?.toInt() ?? 0,
      revenue: (json['revenue'] as num?)?.toInt() ?? 0,
      weeklySpots: spots,
      maxWeeklySpotY: (json['maxWeeklySpotY'] as num?)?.toDouble() ?? 100.0,
      areaDistribution: Map<String, int>.from(json['areaDistribution'] ?? {}),
      topProducts: Map<String, int>.from(json['topProducts'] ?? {}),
      activities: (json['activities'] as List?)
          ?.map((e) => Map<String, String>.from(e as Map))
          .toList() ??
          [],
      lastUpdated: parsedDate,
    );
  }
}

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  // Global static memory cache for instant zero-wait display. Kept per company: a different
  // company (or the super admin opening another one) must never see these figures.
  static AdminDashboardData? get memoryCache => _memoryCompany == Account.companyId ? _memoryCache : null;
  static set memoryCache(AdminDashboardData? d) {
    _memoryCache = d;
    _memoryCompany = Account.companyId;
  }

  static AdminDashboardData? _memoryCache;
  static String? _memoryCompany;

  /// Call this on app startup or login to pre-warm cache in background
  static Future<void> prewarm() async {
    try {
      if (memoryCache == null) {
        final diskData = _loadFromDiskCache();
        if (diskData != null) memoryCache = diskData;
      }
    } catch (_) {}
  }

  static File _getCacheFile() {
    return File('${Directory.systemTemp.path}/an_agency_admin_dashboard_cache_${Account.companyId ?? "default"}.json');
  }

  static void _saveToDiskCache(AdminDashboardData data) {
    try {
      final file = _getCacheFile();
      file.writeAsStringSync(jsonEncode(data.toJson()), flush: true);
    } catch (e) {
      debugPrint("Dashboard disk cache write error: $e");
    }
  }

  static AdminDashboardData? _loadFromDiskCache() {
    try {
      final file = _getCacheFile();
      if (file.existsSync()) {
        final content = file.readAsStringSync();
        if (content.isNotEmpty) {
          final json = jsonDecode(content) as Map<String, dynamic>;
          return AdminDashboardData.fromJson(json);
        }
      }
    } catch (e) {
      debugPrint("Dashboard disk cache read error: $e");
    }
    return null;
  }

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  int _selectedIndex = 0;
  AdminDashboardData? _dashboardData;
  bool _isLoading = true;
  bool _isRefreshing = false;

  final List<String> menuTitles = [
    "Dashboard",
    "Manage Stock",
    "Purchases",
    "Warehouses",
    "Manage Areas",
    "Add Product",
    "Allocate Customers",
    "Invoices",
    "Reports",
    "Booker Credits",
    "Khata",
    "CRM",
    "Settings"
  ];

  // The module each menu item needs (null = always shown). The super admin chooses each company's modules.
  final List<String?> menuModules = [
    null, // Dashboard
    'purchases', // Manage Stock
    'purchases', // Purchases
    'purchases', // Warehouses (part of stock)
    null, // Manage Areas
    null, // Add Product
    null, // Allocate Customers
    null, // Invoices
    'dsr', // Reports (DSR)
    'khata', // Booker Credits
    'khata', // Khata
    'crm', // CRM
    null, // Settings
  ];

  final List<IconData> menuIcons = [
    Icons.dashboard,
    Icons.bar_chart,
    Icons.add_shopping_cart,
    Icons.warehouse_outlined,
    Icons.map,
    Icons.add_box,
    Icons.people,
    Icons.inventory,
    Icons.receipt_long,
    Icons.payments,
    Icons.menu_book,
    Icons.groups,
    Icons.settings,
  ];

  @override
  void initState() {
    super.initState();

    // =========================================================================
    // ⚡ ZERO-WAIT INSTANT DATA POPULATION (FRAME 1 - 0 SECONDS)
    // =========================================================================
    // 1. Try static in-memory cache first (0.00 ms)
    if (AdminDashboardScreen.memoryCache != null) {
      _dashboardData = AdminDashboardScreen.memoryCache;
      _isLoading = false;
    } else {
      // 2. Try persistent disk cache (0.5 ms)
      final diskData = AdminDashboardScreen._loadFromDiskCache();
      if (diskData != null) {
        _dashboardData = diskData;
        AdminDashboardScreen.memoryCache = diskData;
        _isLoading = false;
      } else {
        // Fallback default placeholder for fresh install
        _dashboardData = AdminDashboardData(
          usersCount: 0,
          customersCount: 0,
          areasCount: 0,
          revenue: 0,
          weeklySpots: List.generate(7, (i) => FlSpot(i.toDouble(), 0)),
          maxWeeklySpotY: 100,
          areaDistribution: const {},
          topProducts: const {},
          activities: const [],
          lastUpdated: DateTime.now(),
        );
        _isLoading = false;
      }
    }

    // 3. Silently fetch live updates in background (Stale-While-Revalidate)
    // Runs seamlessly without showing any blocking loading spinners or skeletons!
    _fetchDashboardData(silent: true);
  }

  // ===========================================================================
  //               HIGH PERFORMANCE SILENT BACKGROUND SYNC
  // ===========================================================================
  Future<void> _fetchDashboardData({bool isRefresh = false, bool silent = false}) async {
    if (isRefresh) {
      if (mounted) setState(() => _isRefreshing = true);
    } else if (!silent) {
      if (_dashboardData == null && mounted) {
        setState(() => _isLoading = true);
      }
    }

    final data = await _loadDashboardData();

    // Cache in memory and persist to disk for instant load next time
    AdminDashboardScreen.memoryCache = data;
    AdminDashboardScreen._saveToDiskCache(data);

    if (mounted) {
      setState(() {
        _dashboardData = data;
        _isLoading = false;
        _isRefreshing = false;
      });
    }
  }

  Future<AdminDashboardData> _loadDashboardData() async {
    try {
      final now = DateTime.now();
      final DateFormat df = DateFormat("dd-MM-yyyy");
      final String todayStr = df.format(now);

      // Generate the past 7 days strings
      final List<String> weekDateStrs = [];
      for (int i = 0; i < 7; i++) {
        final targetDate = now.subtract(Duration(days: 6 - i));
        weekDateStrs.add(df.format(targetDate));
      }

      // Execute ALL 4 primary queries concurrently in parallel!
      final sessionsFuture = companyCol('sessions').get();
      final customersFuture = companyCol('customers').get();
      final areasFuture = companyCol('areas').get();
      final invoicesFuture = companyCol('invoices')
          .where("salesDate", whereIn: weekDateStrs)
          .get()
          .catchError((_) => companyCol('invoices').limit(100).get());

      final results = await Future.wait([
        sessionsFuture,
        customersFuture,
        areasFuture,
        invoicesFuture,
      ]);

      final QuerySnapshot sessionsSnap = results[0];
      final QuerySnapshot customersSnap = results[1];
      final QuerySnapshot areasSnap = results[2];
      final QuerySnapshot invoicesSnap = results[3];

      // 1. STATS: USERS
      final int usersCount = sessionsSnap.docs.length;

      // 2. STATS: CUSTOMERS & AREA DISTRIBUTION & RECENT CUSTOMERS
      final int customersCount = customersSnap.docs.length;
      final Map<String, int> areaDistribution = {};
      final List<Map<String, dynamic>> customerDocs = [];

      for (var doc in customersSnap.docs) {
        final data = doc.data() as Map<String, dynamic>? ?? {};
        final area = (data["area"] ?? "Unknown").toString().trim();
        if (area.isNotEmpty) {
          areaDistribution[area] = (areaDistribution[area] ?? 0) + 1;
        }
        customerDocs.add(data);
      }

      // 3. STATS: AREAS
      int areaCount = 0;
      for (var doc in areasSnap.docs) {
        final data = doc.data() as Map<String, dynamic>? ?? {};
        final list = data['areas'];
        if (list is List) {
          areaCount += list.length;
        }
      }
      if (areaCount == 0) {
        areaCount = areasSnap.docs.length;
      }

      // 4. STATS: REVENUE, WEEKLY SALES SPOTS & TOP PRODUCTS
      // (All derived in memory from single invoices snapshot!)
      double todayRevenue = 0.0;
      final Map<String, double> salesByDate = {};
      final Map<String, int> productCount = {};

      for (var doc in invoicesSnap.docs) {
        final data = doc.data() as Map<String, dynamic>? ?? {};
        final sDate = data["salesDate"]?.toString() ?? "";
        final grandTotal = (num.tryParse(data['grandTotal']?.toString() ?? "0") ?? 0).toDouble();

        // Today's revenue
        if (sDate == todayStr) {
          todayRevenue += grandTotal;
        }

        // Daily bucket for 7-day chart
        if (sDate.isNotEmpty) {
          salesByDate[sDate] = (salesByDate[sDate] ?? 0.0) + grandTotal;
        }

        // Top selling products
        final items = data['items'] as List?;
        if (items != null) {
          for (var item in items) {
            if (item is Map) {
              final String pName = (item['Product Name'] ?? item['productName'] ?? 'Unknown').toString().trim();
              final int qty = (num.tryParse(item['QTY']?.toString() ?? item['qty']?.toString() ?? "0") ?? 0).toInt();
              if (pName.isNotEmpty && pName != 'Unknown' && qty > 0) {
                productCount[pName] = (productCount[pName] ?? 0) + qty;
              }
            }
          }
        }
      }

      // Build weekly spots (7 spots: index 0 to 6)
      final List<FlSpot> spots = [];
      double maxSpotY = 100.0;
      for (int i = 0; i < 7; i++) {
        final dateStr = weekDateStrs[i];
        final dayRev = salesByDate[dateStr] ?? 0.0;
        spots.add(FlSpot(i.toDouble(), dayRev));
        if (dayRev > maxSpotY) {
          maxSpotY = dayRev;
        }
      }

      // Sort Top Products
      final sortedProductEntries = productCount.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final Map<String, int> topProducts = {};
      for (var entry in sortedProductEntries.take(3)) {
        topProducts[entry.key] = entry.value;
      }

      // 5. RECENT ACTIVITIES (Combined Logins + Customer Registrations)
      final List<Map<String, dynamic>> combinedActivities = [];
      final DateFormat activityFormatter = DateFormat('dd-MM-yyyy hh:mm a');

      // Sessions
      for (var s in sessionsSnap.docs) {
        final data = s.data() as Map<String, dynamic>? ?? {};
        final username = data["username"] ?? data["email"] ?? "User";
        final dynamic startedAt = data["startedAt"];
        DateTime? dt;
        if (startedAt is Timestamp) {
          dt = startedAt.toDate();
        } else if (startedAt is DateTime) {
          dt = startedAt;
        }

        combinedActivities.add({
          "action": "User '$username' logged into system",
          "rawTime": dt,
          "time": dt != null ? activityFormatter.format(dt) : "",
        });
      }

      // Customers
      customerDocs.sort((a, b) {
        final aTime = a["createdAt"];
        final bTime = b["createdAt"];
        if (aTime is Timestamp && bTime is Timestamp) {
          return bTime.compareTo(aTime);
        }
        return 0;
      });

      for (var c in customerDocs.take(3)) {
        final name = (c["name"] ?? "Customer").toString();
        final dynamic createdAt = c["createdAt"];
        DateTime? dt;
        if (createdAt is Timestamp) {
          dt = createdAt.toDate();
        } else if (createdAt is DateTime) {
          dt = createdAt;
        }

        combinedActivities.add({
          "action": "New Customer registered: $name",
          "rawTime": dt,
          "time": dt != null ? activityFormatter.format(dt) : "",
        });
      }

      // Sort combined activity descending
      combinedActivities.sort((a, b) {
        final DateTime? aDt = a["rawTime"] as DateTime?;
        final DateTime? bDt = b["rawTime"] as DateTime?;
        if (aDt == null && bDt == null) {
          return 0;
        }
        if (aDt == null) {
          return 1;
        }
        if (bDt == null) {
          return -1;
        }
        return bDt.compareTo(aDt);
      });

      final finalActivities = combinedActivities.take(6).map((e) => {
        "action": e["action"].toString(),
        "time": e["time"].toString(),
      }).toList();

      return AdminDashboardData(
        usersCount: usersCount,
        customersCount: customersCount,
        areasCount: areaCount,
        revenue: todayRevenue.round(),
        weeklySpots: spots,
        maxWeeklySpotY: maxSpotY,
        areaDistribution: areaDistribution,
        topProducts: topProducts,
        activities: finalActivities,
        lastUpdated: DateTime.now(),
      );
    } catch (e, stack) {
      debugPrint("Error loading admin dashboard: $e\n$stack");
      return AdminDashboardScreen.memoryCache ?? AdminDashboardData(lastUpdated: DateTime.now());
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isWide = constraints.maxWidth >= 900;

        return Scaffold(
          key: _scaffoldKey,
          backgroundColor: _Tokens.bg,
          drawer: isWide
              ? null
              : Drawer(
            backgroundColor: _Tokens.navy,
            child: SafeArea(
              child: _buildSidebarContent(isCollapsed: false, isDrawer: true),
            ),
          ),
          appBar: AppBar(
            elevation: 0,
            backgroundColor: _Tokens.navy,
            leading: isWide
                ? null
                : IconButton(
              icon: const Icon(Icons.menu, color: Colors.white),
              onPressed: () {
                _scaffoldKey.currentState?.openDrawer();
              },
            ),
            title: Text(
              "Admin Dashboard",
              style: GoogleFonts.sora(
                fontWeight: FontWeight.w600,
                fontSize: 18,
                color: Colors.white,
              ),
            ),
            actions: [
              IconButton(
                tooltip: "Instant Sync",
                icon: _isRefreshing
                    ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _Tokens.amber,
                  ),
                )
                    : const Icon(Icons.sync, color: Colors.white),
                onPressed: _isRefreshing
                    ? null
                    : () => _fetchDashboardData(isRefresh: true),
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: Row(
            children: [
              if (isWide)
                SizedBox(
                  width: 220,
                  child: _buildSidebarContent(isCollapsed: false, isDrawer: false),
                ),
              Expanded(child: _buildBody()),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSidebarContent(
      {required bool isCollapsed, required bool isDrawer}) {
    return Container(
      color: _Tokens.navy,
      child: Column(
        children: [
          const SizedBox(height: 30),
          if (!isCollapsed)
            Text(
              "Admin Panel",
              style: GoogleFonts.sora(
                color: Colors.white,
                fontSize: 19,
                fontWeight: FontWeight.w700,
              ),
            ),
          const SizedBox(height: 30),
          Expanded(
            child: ListView.builder(
              itemCount: _visibleMenu.length,
              itemBuilder: (context, k) {
                final i = _visibleMenu[k];
                final bool active = _selectedIndex == i;
                return InkWell(
                  onTap: () {
                    setState(() => _selectedIndex = i);
                    if (isDrawer) {
                      Navigator.pop(context);
                    }
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: active ? _Tokens.amber.withValues(alpha: 0.18) : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: active
                          ? Border.all(color: _Tokens.amber.withValues(alpha: 0.4))
                          : null,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          menuIcons[i],
                          size: 22,
                          color: active ? _Tokens.amber : Colors.white.withValues(alpha: 0.85),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            menuTitles[i],
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.sora(
                              fontSize: 14,
                              fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                              color: active ? _Tokens.amber : Colors.white.withValues(alpha: 0.85),
                            ),
                          ),
                        )
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  List<int> get _visibleMenu => [
        for (var i = 0; i < menuTitles.length; i++)
          if (menuModules[i] == null || Account.has(menuModules[i]!)) i,
      ];

  Widget _buildBody() {
    final pages = [
      _dashboardPage(),
      StockAndSalesScreen(),
      const AdminPurchasesScreen(),
      const WarehousesScreen(),
      AddAreaPage(),
      ProductFormScreen(),
      AllocateCustomerPage(),
      ReportsScreen(),
      AdminDSRReportsScreen(),
      const AdminBookerCreditReportScreen(),
      const AdminKhataScreen(),
      const AdminCrmScreen(),
      AdminSettingsScreen(),
    ];
    return pages[_selectedIndex];
  }

  Widget _dashboardPage() {
    final data = _dashboardData ??
        AdminDashboardScreen.memoryCache ??
        AdminDashboardData(lastUpdated: DateTime.now());

    return RefreshIndicator(
      color: _Tokens.navy,
      onRefresh: () => _fetchDashboardData(isRefresh: true),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(data),
            const SizedBox(height: 20),
            _sectionTitle("Summary"),
            const SizedBox(height: 12),
            _isLoading ? _summaryCardsSkeleton() : _summaryCards(data),
            const SizedBox(height: 12),
            if (Account.has('purchases'))
            InventorySummaryRow(
              onOpenStock: () => setState(() => _selectedIndex = 1),
              onOpenPurchases: () => setState(() => _selectedIndex = 2),
            ),
            const SizedBox(height: 30),
            _sectionTitle("Sales Overview (Past 7 Days)"),
            const SizedBox(height: 12),
            _isLoading ? _chartSkeleton(260) : _salesChart(data),
            const SizedBox(height: 30),
            _sectionTitle("Customer Distribution per Area"),
            const SizedBox(height: 12),
            _isLoading ? _areaDistributionSkeleton() : _areaDistributionChart(data),
            const SizedBox(height: 30),
            _sectionTitle("Top Selling Products"),
            const SizedBox(height: 12),
            _isLoading ? _chartSkeleton(320) : _topProductsChart(data),
            const SizedBox(height: 30),
            _sectionTitle("Recent Activity"),
            const SizedBox(height: 12),
            _isLoading ? _recentActivitySkeleton() : _recentActivity(data),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _header(AdminDashboardData data) {
    final timeStr = DateFormat("hh:mm a").format(data.lastUpdated);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: _Tokens.navy,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: _Tokens.navy.withValues(alpha: 0.18),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Welcome Admin",
                  style: GoogleFonts.sora(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _isRefreshing
                      ? "Synchronizing real-time agency data..."
                      : "Instant cached • Live synced at $timeStr",
                  style: GoogleFonts.sora(
                    fontSize: 12,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: "Instant Sync",
            icon: _isRefreshing
                ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: _Tokens.amber,
              ),
            )
                : const Icon(Icons.sync, color: _Tokens.amber),
            onPressed: _isRefreshing
                ? null
                : () => _fetchDashboardData(isRefresh: true),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 20,
          decoration: BoxDecoration(
            color: _Tokens.amber,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.sora(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: _Tokens.navy,
            ),
          ),
        ),
      ],
    );
  }

  Widget _summaryCards(AdminDashboardData data) {
    final numberFormat = NumberFormat('#,###');
    final items = [
      {
        "label": "Active Sessions",
        "value": numberFormat.format(data.usersCount),
        "icon": Icons.people_outline,
      },
      {
        "label": "Total Customers",
        "value": numberFormat.format(data.customersCount),
        "icon": Icons.storefront_outlined,
      },
      {
        "label": "Assigned Areas",
        "value": numberFormat.format(data.areasCount),
        "icon": Icons.map_outlined,
      },
      {
        "label": "Today's Revenue",
        "value": "Rs. ${numberFormat.format(data.revenue)}",
        "icon": Icons.attach_money,
        "highlight": true,
      },
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        int crossAxisCount = constraints.maxWidth > 600 ? 4 : 2;
        return GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: 14,
          mainAxisSpacing: 14,
          childAspectRatio: 1.5,
          children: items.map((i) => _summaryCard(i)).toList(),
        );
      },
    );
  }

  Widget _summaryCardsSkeleton() {
    return LayoutBuilder(
      builder: (context, constraints) {
        int crossAxisCount = constraints.maxWidth > 600 ? 4 : 2;
        return Shimmer.fromColors(
          baseColor: Colors.grey.shade200,
          highlightColor: Colors.grey.shade100,
          child: GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
            childAspectRatio: 1.5,
            children: List.generate(4, (index) {
              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _Tokens.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(width: 26, height: 26, color: Colors.white),
                    const SizedBox(height: 10),
                    Container(width: 70, height: 12, color: Colors.white),
                    const SizedBox(height: 8),
                    Container(width: 90, height: 20, color: Colors.white),
                  ],
                ),
              );
            }),
          ),
        );
      },
    );
  }

  Widget _summaryCard(Map item) {
    final bool highlight = item['highlight'] == true;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: highlight ? _Tokens.amber.withValues(alpha: 0.14) : Colors.white,
        border: Border.all(
          color: highlight ? _Tokens.amber.withValues(alpha: 0.4) : _Tokens.border,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: highlight
            ? []
            : [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: FittedBox(
        alignment: Alignment.topLeft,
        fit: BoxFit.scaleDown,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(item['icon'], size: 28, color: highlight ? _Tokens.amber : _Tokens.navy),
            const SizedBox(height: 8),
            Text(
              item['label'],
              style: GoogleFonts.sora(fontSize: 13, fontWeight: FontWeight.w600, color: _Tokens.muted),
            ),
            const SizedBox(height: 4),
            Text(
              "${item['value']}",
              style: GoogleFonts.sora(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: _Tokens.textDark,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  //               SALES OVERVIEW (PAST 7 DAYS) - PRECOMPUTED INSTANT
  // ===========================================================================
  Widget _salesChart(AdminDashboardData data) {
    final spots = data.weeklySpots.isEmpty
        ? List.generate(7, (i) => FlSpot(i.toDouble(), 0))
        : data.weeklySpots;

    final maxSpotY = data.maxWeeklySpotY;

    return Container(
      height: 260,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _Tokens.border),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: LineChart(
        LineChartData(
          gridData: FlGridData(
            drawVerticalLine: false,
            horizontalInterval: maxSpotY / 5 == 0 ? 20 : maxSpotY / 5,
            getDrawingHorizontalLine: (_) => FlLine(
              color: _Tokens.navy.withValues(alpha: 0.08),
              strokeWidth: 1,
            ),
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 45,
                getTitlesWidget: (value, meta) => Text(
                  value.toInt().toString(),
                  style: GoogleFonts.sora(fontSize: 10, color: _Tokens.muted),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 1,
                getTitlesWidget: (value, meta) {
                  int idx = value.toInt();
                  if (idx >= 0 && idx < 7) {
                    DateTime targetDate = DateTime.now().subtract(Duration(days: 6 - idx));
                    String label = DateFormat("E").format(targetDate);
                    return Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        label,
                        style: GoogleFonts.sora(fontSize: 11, color: _Tokens.muted),
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
          minX: 0,
          maxX: 6,
          minY: 0,
          maxY: maxSpotY * 1.15,
          lineBarsData: [
            LineChartBarData(
              isCurved: true,
              color: _Tokens.amber,
              barWidth: 3,
              dotData: const FlDotData(show: true),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  colors: [
                    _Tokens.amber.withValues(alpha: 0.28),
                    _Tokens.amber.withValues(alpha: 0.02),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              spots: spots,
            ),
          ],
          lineTouchData: const LineTouchData(enabled: true),
        ),
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeOut,
      ),
    );
  }

  // ===========================================================================
  //                          AREA DISTRIBUTION CHART
  // ===========================================================================
  Widget _areaDistributionChart(AdminDashboardData data) {
    final entries = data.areaDistribution.entries.toList();

    if (entries.isEmpty) {
      return Container(
        height: 140,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: _Tokens.border),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          "No customer distribution data available",
          style: GoogleFonts.sora(color: _Tokens.muted, fontSize: 13),
        ),
      );
    }

    final total = entries.fold(0, (a, b) => a + b.value);
    if (total == 0) {
      return Container(
        height: 140,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: _Tokens.border),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          "No customers assigned to areas yet",
          style: GoogleFonts.sora(color: _Tokens.muted, fontSize: 13),
        ),
      );
    }

    final colors = [
      _Tokens.navy,
      _Tokens.amber,
      const Color(0xFF5B8DB8),
      const Color(0xFF48A9A6),
      const Color(0xFFD4B483),
      const Color(0xFFC1666B),
      const Color(0xFF4357AD),
      const Color(0xFF48BF84),
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _Tokens.border),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 250,
            child: PieChart(
              PieChartData(
                centerSpaceRadius: 40,
                sectionsSpace: 2,
                sections: List.generate(entries.length, (i) {
                  final percent = (entries[i].value / total) * 100;
                  return PieChartSectionData(
                    color: colors[i % colors.length],
                    value: entries[i].value.toDouble(),
                    radius: 70,
                    title: "${percent.toStringAsFixed(1)}%",
                    titleStyle: GoogleFonts.sora(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  );
                }),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: List.generate(entries.length, (i) {
              return ConstrainedBox(
                constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.42),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: colors[i % colors.length],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        "${entries[i].key} (${entries[i].value})",
                        overflow: TextOverflow.ellipsis,
                        maxLines: 2,
                        style: GoogleFonts.sora(fontSize: 12, color: _Tokens.textDark),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _areaDistributionSkeleton() {
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade200,
      highlightColor: Colors.grey.shade100,
      child: Container(
        height: 260,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _Tokens.border),
        ),
      ),
    );
  }

  // ===========================================================================
  //                          TOP SELLING PRODUCTS CHART
  // ===========================================================================
  Widget _topProductsChart(AdminDashboardData data) {
    if (data.topProducts.isEmpty) {
      return Container(
        height: 120,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: _Tokens.border),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          "No item sales data logged yet",
          style: GoogleFonts.sora(color: _Tokens.muted, fontSize: 13),
        ),
      );
    }

    final productNames = data.topProducts.keys.toList();
    final values = data.topProducts.values.toList();
    final colors = [_Tokens.navy, _Tokens.amber, const Color(0xFF5B8DB8)];

    final maxVal = values.reduce(max);

    return Container(
      height: 320,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _Tokens.border),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: BarChart(
        BarChartData(
          maxY: (maxVal + 20).toDouble(),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 32,
                getTitlesWidget: (value, meta) => Text(
                  value.toInt().toString(),
                  style: GoogleFonts.sora(fontSize: 10, color: _Tokens.muted),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 1,
                getTitlesWidget: (value, meta) {
                  int i = value.toInt();
                  if (i < 0 || i >= productNames.length) return Container();

                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: SizedBox(
                      width: 80,
                      child: Text(
                        productNames[i],
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.sora(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _Tokens.textDark,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          gridData: FlGridData(
            drawVerticalLine: false,
            horizontalInterval: (maxVal / 4) == 0 ? 10 : (maxVal / 4),
            getDrawingHorizontalLine: (_) =>
                FlLine(color: _Tokens.border, strokeWidth: 1),
          ),
          barGroups: List.generate(productNames.length, (index) {
            return BarChartGroupData(
              x: index,
              barsSpace: 25,
              barRods: [
                BarChartRodData(
                  toY: values[index].toDouble(),
                  color: colors[index % colors.length],
                  width: 26,
                  borderRadius: BorderRadius.circular(6),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }

  // ===========================================================================
  //                               RECENT ACTIVITY
  // ===========================================================================
  Widget _recentActivity(AdminDashboardData data) {
    if (data.activities.isEmpty) {
      return Container(
        height: 100,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: _Tokens.border),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          "No recent activity logged yet",
          style: GoogleFonts.sora(color: _Tokens.muted, fontSize: 13),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _Tokens.border),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: data.activities.map((e) {
          return Container(
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: _Tokens.border)),
            ),
            child: ListTile(
              dense: true,
              leading: const Icon(Icons.circle, size: 8, color: _Tokens.amber),
              title: Text(
                e['action'] ?? '',
                style: GoogleFonts.sora(fontSize: 13, color: _Tokens.textDark, fontWeight: FontWeight.w500),
              ),
              subtitle: Text(
                e['time'] ?? '',
                style: GoogleFonts.sora(fontSize: 11, color: _Tokens.muted),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _recentActivitySkeleton() {
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade200,
      highlightColor: Colors.grey.shade100,
      child: Container(
        height: 180,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _Tokens.border),
        ),
      ),
    );
  }

  Widget _chartSkeleton(double height) {
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade200,
      highlightColor: Colors.grey.shade100,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _Tokens.border),
        ),
      ),
    );
  }
}