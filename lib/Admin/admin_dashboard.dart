// The admin panel: a sidebar of pages (a drawer on small screens) and the page that is open.
// The first page is the live dashboard (dashboard_overview.dart).

import '../account/account.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

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
import '../hr/hr_screen.dart';
import '../orders/sales_orders_screen.dart';
import 'dashboard_overview.dart';

// Design tokens
class _Tokens {
  static const navy = Color(0xFF15294D);
  static const navyDark = Color(0xFF0E1D38);
  static const amber = Color(0xFFE0A63A);
  static const bg = Color(0xFFF5F6FA);
}

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  int _selectedIndex = 0;

  final List<String> menuTitles = [
    "Dashboard",
    "Manage Stock",
    "Purchases",
    "Warehouses",
    "Manage Areas",
    "Add Product",
    "Allocate Customers",
    "Invoices",
    "Sales Orders",
    "Reports",
    "Booker Credits",
    "Khata",
    "CRM",
    "HR",
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
    null, // Sales Orders
    'dsr', // Reports (DSR)
    'khata', // Booker Credits
    'khata', // Khata
    'crm', // CRM
    'hr', // HR
    null, // Settings
  ];

  final List<IconData> menuIcons = [
    Icons.space_dashboard_outlined,
    Icons.inventory_2_outlined,
    Icons.shopping_cart_outlined,
    Icons.warehouse_outlined,
    Icons.map_outlined,
    Icons.add_box_outlined,
    Icons.group_add_outlined,
    Icons.receipt_long_outlined,
    Icons.assignment_outlined,
    Icons.bar_chart_rounded,
    Icons.payments_outlined,
    Icons.menu_book_outlined,
    Icons.storefront_outlined,
    Icons.badge_outlined,
    Icons.settings_outlined,
  ];


  /// Opens a page by its menu title (from the dashboard's cards), if this company has it.
  void _openPage(String title) {
    final i = menuTitles.indexOf(title);
    if (i >= 0 && _visibleMenu.contains(i)) setState(() => _selectedIndex = i);
  }

  // The sidebar's sections, by menu index.
  static const _groups = <(String, List<int>)>[
    ('', [0]),
    ('SALES', [7, 8, 9, 10, 11]),
    ('STOCK', [1, 2, 3, 5]),
    ('CUSTOMERS', [12, 4, 6]),
    ('TEAM', [13]),
    ('', [14]),
  ];

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
                  width: 280,
                  backgroundColor: _Tokens.navy,
                  child: _buildSidebarContent(isCollapsed: false, isDrawer: true),
                ),
          // On a wide screen the sidebar carries the brand and each page has its own title bar.
          appBar: isWide
              ? null
              : AppBar(
                  leading: IconButton(
                    icon: const Icon(Icons.menu_rounded),
                    onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                  ),
                  title: Text(menuTitles[_selectedIndex]),
                ),
          body: Row(
            children: [
              if (isWide)
                SizedBox(
                  width: 248,
                  child: _buildSidebarContent(isCollapsed: false, isDrawer: false),
                ),
              Expanded(child: _buildBody()),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSidebarContent({required bool isCollapsed, required bool isDrawer}) {
    final visible = _visibleMenu.toSet();
    final user = Account.user;
    final who = (user?.name.trim().isNotEmpty ?? false) ? user!.name.trim() : (user?.email ?? 'Admin');
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_Tokens.navyDark, _Tokens.navy],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: SafeArea(
        right: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Brand
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 22, 16, 18),
              child: Row(children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(color: _Tokens.amber, borderRadius: BorderRadius.circular(11)),
                  child: const Icon(Icons.local_shipping_rounded, color: _Tokens.navyDark, size: 21),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('depotOS',
                        style: GoogleFonts.sora(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(Account.companyName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.sora(color: Colors.white60, fontSize: 11.5)),
                  ]),
                ),
              ]),
            ),
            Container(height: 1, margin: const EdgeInsets.symmetric(horizontal: 16), color: Colors.white12),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                children: [
                  for (final g in _groups)
                    if (g.$2.any(visible.contains)) ...[
                      if (g.$1.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 16, 12, 6),
                          child: Text(g.$1,
                              style: GoogleFonts.sora(
                                  color: Colors.white38, fontSize: 10.5, fontWeight: FontWeight.w600, letterSpacing: 1.2)),
                        )
                      else
                        const SizedBox(height: 6),
                      for (final i in g.$2)
                        if (visible.contains(i)) _navItem(i, isDrawer),
                    ],
                ],
              ),
            ),
            // Who is signed in
            Container(
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 14),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: _Tokens.amber.withValues(alpha: 0.2),
                  child: Text(who.isEmpty ? 'A' : who[0].toUpperCase(),
                      style: GoogleFonts.sora(color: _Tokens.amber, fontWeight: FontWeight.w700, fontSize: 13)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(who,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.sora(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600)),
                    Text(Account.isSuperAdmin ? 'Super admin' : 'Admin',
                        style: GoogleFonts.sora(color: Colors.white54, fontSize: 11)),
                  ]),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _navItem(int i, bool isDrawer) {
    final active = _selectedIndex == i;
    final color = active ? Colors.white : Colors.white.withValues(alpha: 0.72);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Material(
        color: active ? Colors.white.withValues(alpha: 0.10) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          hoverColor: Colors.white.withValues(alpha: 0.06),
          onTap: () {
            setState(() => _selectedIndex = i);
            if (isDrawer) Navigator.pop(context);
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(0, 10, 12, 10),
            child: Row(children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 3,
                height: 18,
                margin: const EdgeInsets.only(right: 11),
                decoration: BoxDecoration(
                  color: active ? _Tokens.amber : Colors.transparent,
                  borderRadius: const BorderRadius.horizontal(right: Radius.circular(3)),
                ),
              ),
              Icon(menuIcons[i], size: 19, color: active ? _Tokens.amber : color),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  menuTitles[i],
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.sora(
                    fontSize: 13.5,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                    color: color,
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  List<int> get _visibleMenu => [
        for (var i = 0; i < menuTitles.length; i++)
          if (menuModules[i] == null || Account.has(menuModules[i]!)) i,
      ];

  Widget _buildBody() {
    final pages = [
      DashboardOverview(onOpen: _openPage),
      StockAndSalesScreen(),
      const AdminPurchasesScreen(),
      const WarehousesScreen(),
      AddAreaPage(),
      ProductFormScreen(),
      AllocateCustomerPage(),
      ReportsScreen(),
      const AdminSalesOrdersScreen(),
      AdminDSRReportsScreen(),
      const AdminBookerCreditReportScreen(),
      const AdminKhataScreen(),
      const AdminCrmScreen(),
      const AdminHrScreen(),
      AdminSettingsScreen(),
    ];
    return pages[_selectedIndex];
  }
}
