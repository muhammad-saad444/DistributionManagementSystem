import 'package:flutter/material.dart';
import '../account/account.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'addproduct.dart';
import '../crm/crm_ui.dart';

// ---------------------------------------------------------------------------
// Same design tokens used across the rest of the app. Worth pulling into a
// shared lib/design_tokens.dart at some point instead of duplicating this
// class per file.
// ---------------------------------------------------------------------------
class _Tokens {
  static const navyDark = Color(0xFF131C31);
  static const navySlate = Color(0xFF24345C);
  static const amber = Color(0xFFE8973A);
  static const bg = Color(0xFFF5F6F8);
  static const textPrimary = Color(0xFF101828);
  static const textSecondary = Color(0xFF667085);
  static const border = Color(0xFFE4E7EC);
  static const error = Color(0xFFD92D20);
  static const navySlateBg = Color(0xFFE7EAF2);

  static TextStyle display({double size = 18, Color? color, FontWeight w = FontWeight.w600}) =>
      GoogleFonts.sora(fontSize: size, fontWeight: w, color: color ?? textPrimary, height: 1.2);

  static TextStyle body({double size = 13, Color? color, FontWeight w = FontWeight.w400}) =>
      GoogleFonts.inter(fontSize: size, fontWeight: w, color: color ?? textPrimary);
}

String _str(Object? v) => (v ?? '').toString().trim();

/// The lines under a product's name; empty parts are left out.
List<String> _details(Map<String, dynamic> d) {
  String join(List<String> parts) => parts.where((s) => s.isNotEmpty).join('  ·  ');
  final tp = num.tryParse(_str(d['dbPrice'] ?? d['dbPrie']));
  final cost = num.tryParse(_str(d['costPrice'])) ?? 0;
  final mrp = num.tryParse(_str(d['retailPrice'])) ?? 0;
  final perCarton = num.tryParse(_str(d['unitsPerCarton'])) ?? 0;
  final stock = d['stock'];
  return [
    join([_str(d['productCode']), _str(d['productCategory']), _str(d['brand'])]),
    join([
      tp == null ? '' : 'TP Rs. $tp / ${_str(d['productSize']).isEmpty ? 'unit' : _str(d['productSize'])}',
      cost > 0 ? 'Cost Rs. $cost' : '',
      mrp > 0 ? 'MRP Rs. $mrp' : '',
      _str(d['packSize']),
      perCarton > 0 ? '$perCarton per carton' : '',
    ]),
    if (stock is num) 'In stock: $stock',
  ].where((s) => s.isNotEmpty).toList();
}

bool _isLow(Map<String, dynamic> d) {
  final level = num.tryParse(_str(d['reorderLevel'])) ?? 0;
  final stock = d['stock'];
  return level > 0 && stock is num && stock <= level;
}

class ProductListScreen extends StatelessWidget {
  const ProductListScreen({Key? key}) : super(key: key);

  void _deleteProduct(BuildContext context, String docId) async {
    await companyCol('products')
        .doc(docId)
        .delete();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: _Tokens.navyDark,
        content: Text('Product deleted', style: _Tokens.body(color: Colors.white)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _Tokens.bg,
      appBar: AppBar(
        title: Text('Products', style: _Tokens.display(size: 18, color: Colors.white)),
        centerTitle: true,
        backgroundColor: _Tokens.navyDark,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: companyCol('products')
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return Center(child: CircularProgressIndicator(color: _Tokens.amber));
          }

          if (snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.inventory_2_outlined, size: 48, color: _Tokens.textSecondary),
                  const SizedBox(height: 12),
                  Text("No products found", style: _Tokens.body(color: _Tokens.textSecondary)),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: snapshot.data!.docs.length,
            itemBuilder: (context, index) {
              final doc = snapshot.data!.docs[index];
              final data = doc.data() as Map<String, dynamic>;

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _Tokens.border),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2)),
                  ],
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  leading: CircleAvatar(
                    backgroundColor: _Tokens.navySlateBg,
                    child: Icon(Icons.inventory_2_outlined, color: _Tokens.navySlate),
                  ),
                  title: Text(
                    data['productName'] ?? '',
                    style: _Tokens.display(size: 15),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final line in _details(data))
                          Text(line, style: _Tokens.body(color: _Tokens.textSecondary)),
                        if (data['active'] == false || _isLow(data))
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Wrap(spacing: 6, children: [
                              if (data['active'] == false)
                                const CrmPill('Inactive', color: CrmTokens.muted, background: CrmTokens.bg),
                              if (_isLow(data))
                                const CrmPill('Low stock', color: CrmTokens.red, background: CrmTokens.redBg),
                            ]),
                          ),
                      ],
                    ),
                  ),
                  isThreeLine: true,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Edit
                      IconButton(
                        icon: Icon(Icons.edit_outlined, color: _Tokens.navySlate),
                        tooltip: 'Edit',
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ProductFormScreen(
                                docId: doc.id,
                                productData: data,
                              ),
                            ),
                          );
                        },
                      ),
                      // Delete
                      IconButton(
                        icon: Icon(Icons.delete_outline, color: _Tokens.error),
                        tooltip: 'Delete',
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (_) => AlertDialog(
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              title: Text("Delete Product", style: _Tokens.display(size: 18)),
                              content: Text(
                                "Are you sure you want to delete this product?",
                                style: _Tokens.body(color: _Tokens.textSecondary),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: Text("Cancel", style: _Tokens.body(color: _Tokens.textSecondary, w: FontWeight.w600)),
                                ),
                                ElevatedButton(
                                  onPressed: () {
                                    Navigator.pop(context);
                                    _deleteProduct(context, doc.id);
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _Tokens.error,
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  child: Text("Delete", style: _Tokens.body(color: Colors.white, w: FontWeight.w600)),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: _Tokens.amber,
        child: const Icon(Icons.add, color: _Tokens.navyDark),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const ProductFormScreen(),
            ),
          );
        },
      ),
    );
  }
}