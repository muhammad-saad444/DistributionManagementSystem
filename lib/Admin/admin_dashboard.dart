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
    Icons.dashboard,
    Icons.bar_chart,
    Icons.add_shopping_cart,
    Icons.warehouse_outlined,
    Icons.map,
    Icons.add_box,
    Icons.people,
    Icons.inventory,
    Icons.assignment_outlined,
    Icons.receipt_long,
    Icons.payments,
    Icons.menu_book,
    Icons.groups,
    Icons.badge_outlined,
    Icons.settings,
  ];


  /// Opens a page by its menu title (from the dashboard's cards), if this company has it.
  void _openPage(String title) {
    final i = menuTitles.indexOf(title);
    if (i >= 0 && _visibleMenu.contains(i)) setState(() => _selectedIndex = i);
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
              _selectedIndex == 0 ? "Admin Dashboard" : menuTitles[_selectedIndex],
              style: GoogleFonts.sora(
                fontWeight: FontWeight.w600,
                fontSize: 18,
                color: Colors.white,
              ),
            ),
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
