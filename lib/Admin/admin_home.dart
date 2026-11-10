import 'package:flutter/material.dart';

import 'admin_dashboard.dart';

/// The admin's home: the admin panel (sidebar of pages). Suppliers are added from Purchases →
/// Suppliers, and areas are allocated from Manage Areas.
class AdminHome extends StatelessWidget {
  const AdminHome({super.key});

  @override
  Widget build(BuildContext context) => const AdminDashboardScreen();
}
