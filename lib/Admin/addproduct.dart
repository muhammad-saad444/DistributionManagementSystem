import 'package:an_agency/Admin/product_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import '../inventory/inventory_data.dart';

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

class ProductFormScreen extends StatefulWidget {
  final String? docId;
  final Map<String, dynamic>? productData;

  const ProductFormScreen({Key? key, this.docId, this.productData})
      : super(key: key);

  @override
  State<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends State<ProductFormScreen> {
  final _formKey = GlobalKey<FormState>();

  final _productName = TextEditingController();
  final _price = TextEditingController();
  final _baseSize = TextEditingController();
  final _subSize = TextEditingController();
  final _description = TextEditingController();

  String? category;
  String? supplier;
  String? size;

  final categories = ['Stationery', 'Cosmetics', 'Consumer', 'Electronics', 'Others'];
  final sizes = ['Box', 'Jar', 'G', 'MG', 'KG', 'ML', 'L', 'Nil'];

  List<String> suppliers = [];
  bool loadingSuppliers = true;

  bool get isEdit => widget.docId != null;

  @override
  void initState() {
    super.initState();
    _loadSuppliers();

    if (isEdit && widget.productData != null) {
      final d = widget.productData!;
      _productName.text = d['productName'];
      _price.text = d['dbPrice'];
      _baseSize.text = d['baseSize'];
      _subSize.text = d['subSize'];
      _description.text = d['description'] ?? '';
      category = d['productCategory'];
      supplier = d['productSupplier'];
      size = d['productSize'];
    }
  }

  Future<void> _loadSuppliers() async {
    final snap = await FirebaseFirestore.instance
        .collection('suppliers')
        .orderBy('name')
        .get();

    suppliers = snap.docs.map((e) => e['name'].toString()).toList();
    setState(() => loadingSuppliers = false);
  }

  Future<void> _saveProduct() async {
    final data = {
      'productName': _productName.text.trim(),
      'productCategory': category,
      'productSupplier': supplier,
      'productSize': size,
      'dbPrice': _price.text.trim(),
      'baseSize': _baseSize.text.trim(),
      'subSize': _subSize.text.trim(),
      'description': _description.text.trim(),
    };

    final ref = FirebaseFirestore.instance.collection('products');

    try {
      if (isEdit) {
        await ref.doc(widget.docId).update(data);
      } else {
        final added = await ref.add({
          ...data,
          'createdAt': FieldValue.serverTimestamp(),
        });
        // Once stock is tracked, a new product starts with its Base Size as stock on hand.
        await setNewProductStock(added.id, _productName.text.trim(), num.tryParse(_baseSize.text.trim()) ?? 0);
      }
    } catch (e) {
      if (!mounted) return;
      _snack('Could not save the product. Check your internet connection and try again.', error: true);
      return; // keep what was typed
    }

    if (!mounted) return;
    _snack(isEdit ? 'Product updated' : 'Product added');

    // Opened from the product list (Add / Edit): go back to it.
    // Opened as a page of the admin panel: there is nothing to go back to (popping would close the
    // admin panel and leave a black screen), so clear the form for the next product instead.
    if (Navigator.of(context).canPop()) {
      Navigator.pop(context);
    } else {
      _clearForNextProduct();
    }
  }

  /// Empties the text fields after a product is added; category, supplier and size stay selected
  /// because consecutive products usually share them.
  void _clearForNextProduct() {
    for (final c in [_productName, _price, _baseSize, _subSize, _description]) {
      c.clear();
    }
    // Not _formKey.reset(): that would blank the dropdowns on screen while category/supplier/size keep their values.
    setState(() {});
  }

  void _snack(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.sora()),
        backgroundColor: error ? const Color(0xFFD64545) : _Tokens.navy,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _Tokens.bg,
      appBar: AppBar(
        title: Text(
          isEdit ? 'Edit Product' : 'Add Product',
          style: GoogleFonts.sora(fontWeight: FontWeight.w600, fontSize: 18, color: Colors.white),
        ),
        centerTitle: false,
        backgroundColor: _Tokens.navy,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'View Products',
            icon: const Icon(Icons.list_alt_outlined),
            color: Colors.white,
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProductListScreen()),
              );
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Form(
              key: _formKey,
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _Tokens.border),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isEdit ? 'Product Details' : 'New Product',
                      style: GoogleFonts.sora(fontSize: 19, fontWeight: FontWeight.w700, color: _Tokens.navy),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isEdit
                          ? 'Update the details for this product.'
                          : 'Enter the details for the new product.',
                      style: GoogleFonts.sora(fontSize: 13, color: _Tokens.muted),
                    ),
                    const SizedBox(height: 20),

                    _input(_productName, 'Product Name', icon: Icons.inventory_2_outlined),
                    _dropdown('Category', categories, category, (v) => setState(() => category = v),
                        icon: Icons.category_outlined),
                    _input(_price, 'TP Price', number: true, icon: Icons.attach_money),
                    _dropdown('Size / Unit', sizes, size, (v) => setState(() => size = v),
                        icon: Icons.straighten_outlined),

                    loadingSuppliers
                        ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Center(child: CircularProgressIndicator(color: _Tokens.navy)),
                    )
                        : _dropdown('Supplier', suppliers, supplier,
                            (v) => setState(() => supplier = v),
                        icon: Icons.local_shipping_outlined),

                    _input(_baseSize, 'Base Size', icon: Icons.crop_square_outlined),
                    _input(_subSize, 'Sub Size', icon: Icons.crop_din_outlined),
                    _input(_description, 'Description', lines: 3, icon: Icons.notes_outlined),

                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          if (_formKey.currentState!.validate()) _saveProduct();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _Tokens.amber,
                          foregroundColor: _Tokens.navyDark,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text(
                          isEdit ? 'UPDATE PRODUCT' : 'ADD PRODUCT',
                          style: GoogleFonts.sora(fontWeight: FontWeight.w700, fontSize: 14, letterSpacing: 0.3),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _input(TextEditingController c, String label,
      {bool number = false, int lines = 1, IconData? icon}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: c,
        maxLines: lines,
        keyboardType: number ? TextInputType.number : null,
        style: GoogleFonts.sora(fontSize: 14, color: _Tokens.textDark),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: GoogleFonts.sora(color: _Tokens.muted, fontSize: 14),
          prefixIcon: icon != null ? Icon(icon, color: _Tokens.navy) : null,
          filled: true,
          fillColor: _Tokens.bg,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: _Tokens.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: _Tokens.amber, width: 1.5),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: _Tokens.error),
          ),
        ),
      ),
    );
  }

  Widget _dropdown(
      String label,
      List<String> items,
      String? value,
      Function(String?) onChanged, {
        IconData? icon,
      }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: DropdownButtonFormField<String>(
        value: value,
        isDense: true,
        isExpanded: true,
        style: GoogleFonts.sora(fontSize: 14, color: _Tokens.textDark),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: GoogleFonts.sora(color: _Tokens.muted, fontSize: 14),
          prefixIcon: icon != null ? Icon(icon, color: _Tokens.navy) : null,
          filled: true,
          fillColor: _Tokens.bg,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: _Tokens.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: _Tokens.amber, width: 1.5),
          ),
        ),
        items: items.map((e) {
          return DropdownMenuItem<String>(
            value: e,
            child: Text(
              e,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          );
        }).toList(),

        // Fixes selected value overflow
        selectedItemBuilder: (context) {
          return items.map((e) {
            return Align(
              alignment: Alignment.centerLeft,
              child: Text(
                e,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.sora(fontSize: 14, color: _Tokens.textDark),
              ),
            );
          }).toList();
        },

        onChanged: onChanged,
        validator: (v) => v == null ? 'Required' : null,
      ),
    );
  }
}