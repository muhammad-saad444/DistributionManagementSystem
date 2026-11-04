import 'package:flutter/material.dart';
import '../account/account.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

// Delete this block and import your shared _Tokens file if you already have one.
class _Tokens {
  static const navy = Color(0xFF15294D);
  static const navyDark = Color(0xFF0E1D38);
  static const amber = Color(0xFFE0A63A);
  static const bg = Color(0xFFF5F6FA);
  static const border = Color(0xFFE3E7EF);
  static const textDark = Color(0xFF1E2430);
  static const muted = Color(0xFF6B7280);
  static const error = Color(0xFFD64545);
}

class ViewSuppliersScreen extends StatefulWidget {
  const ViewSuppliersScreen({Key? key}) : super(key: key);

  @override
  State<ViewSuppliersScreen> createState() => _ViewSuppliersScreenState();
}

class _ViewSuppliersScreenState extends State<ViewSuppliersScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _searchController = TextEditingController();

  List<Map<String, dynamic>> _suppliers = [];
  List<Map<String, dynamic>> _filteredSuppliers = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSuppliers();
  }

  Future<void> _loadSuppliers() async {
    setState(() => _isLoading = true);

    final snapshot = await companyCol('suppliers')
        .orderBy('createdAt', descending: true)
        .get();

    final data = snapshot.docs.map((d) => d.data()).toList();

    setState(() {
      _suppliers = data;
      _filteredSuppliers = data;
      _isLoading = false;
    });
  }

  void _filterSuppliers(String query) {
    if (query.isEmpty) {
      setState(() => _filteredSuppliers = _suppliers);
    } else {
      setState(() {
        _filteredSuppliers = _suppliers
            .where((s) =>
        (s['name'] ?? '').toString().toLowerCase().contains(query.toLowerCase()) ||
            (s['company'] ?? '').toString().toLowerCase().contains(query.toLowerCase()))
            .toList();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd MMM yyyy, hh:mm a');
    return Scaffold(
      backgroundColor: _Tokens.bg,
      appBar: AppBar(
        title: Text(
          "All Suppliers",
          style: GoogleFonts.sora(fontWeight: FontWeight.w600, fontSize: 18, color: Colors.white),
        ),
        centerTitle: false,
        backgroundColor: _Tokens.navy,
        elevation: 0,
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: _Tokens.navy))
          : Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              onChanged: _filterSuppliers,
              style: GoogleFonts.sora(fontSize: 14, color: _Tokens.textDark),
              decoration: InputDecoration(
                hintText: "Search suppliers...",
                hintStyle: GoogleFonts.sora(color: _Tokens.muted, fontSize: 14),
                prefixIcon: Icon(Icons.search, color: _Tokens.navy),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: _Tokens.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: _Tokens.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: _Tokens.amber, width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _filteredSuppliers.isEmpty
                  ? _emptyState()
                  : ListView.separated(
                physics: const BouncingScrollPhysics(),
                itemCount: _filteredSuppliers.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final supplier = _filteredSuppliers[index];
                  return _supplierTile(supplier, dateFormat);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _supplierTile(Map<String, dynamic> supplier, DateFormat dateFormat) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _Tokens.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _Tokens.amber.withOpacity(0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.store_outlined, color: _Tokens.amber, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  supplier['name'] ?? 'Unknown',
                  style: GoogleFonts.sora(
                    fontWeight: FontWeight.w700,
                    fontSize: 14.5,
                    color: _Tokens.textDark,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  supplier['company'] ?? '—',
                  style: GoogleFonts.sora(fontSize: 13, color: _Tokens.muted),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.phone_outlined, size: 14, color: _Tokens.navy),
                    const SizedBox(width: 4),
                    Text(
                      supplier['contact'] ?? 'N/A',
                      style: GoogleFonts.sora(fontSize: 12.5, color: _Tokens.textDark),
                    ),
                  ],
                ),
                if (supplier['createdAt'] != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.schedule_outlined, size: 13, color: _Tokens.muted),
                      const SizedBox(width: 4),
                      Text(
                        "Added: ${dateFormat.format((supplier['createdAt'] as Timestamp).toDate())}",
                        style: GoogleFonts.sora(fontSize: 11.5, color: _Tokens.muted),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: _Tokens.muted),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: _Tokens.navy.withOpacity(0.06),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.store_outlined, size: 40, color: _Tokens.navy.withOpacity(0.6)),
          ),
          const SizedBox(height: 16),
          Text(
            "No suppliers found",
            style: GoogleFonts.sora(fontWeight: FontWeight.w600, fontSize: 15, color: _Tokens.textDark),
          ),
          const SizedBox(height: 6),
          Text(
            "Try a different search, or add a new supplier.",
            textAlign: TextAlign.center,
            style: GoogleFonts.sora(fontSize: 13, color: _Tokens.muted),
          ),
        ],
      ),
    );
  }
}