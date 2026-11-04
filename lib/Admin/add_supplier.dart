import 'package:an_agency/Admin/view_supplier.dart';
import '../account/account.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';

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

class AddSupplierScreen extends StatefulWidget {
  const AddSupplierScreen({Key? key}) : super(key: key);

  @override
  State<AddSupplierScreen> createState() => _AddSupplierScreenState();
}

class _AddSupplierScreenState extends State<AddSupplierScreen> {
  final _formKey = GlobalKey<FormState>();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _companyController = TextEditingController();
  final TextEditingController _contactController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _categoryController = TextEditingController();

  bool _isSubmitting = false;

  Future<void> _saveSupplier() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    try {
      await companyCol('suppliers').add({
        'name': _nameController.text.trim(),
        'company': _companyController.text.trim(),
        'contact': _contactController.text.trim(),
        'email': _emailController.text.trim(),
        'category': _categoryController.text.trim(),
        'createdAt': FieldValue.serverTimestamp(),
      });

      _showSnack("Supplier added successfully!");
      _formKey.currentState!.reset();
    } catch (e) {
      debugPrint("Error saving supplier: $e");
      _showSnack("Failed to add supplier.", err: true);
    }

    setState(() => _isSubmitting = false);
  }

  void _showSnack(String msg, {bool err = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.sora()),
        backgroundColor: err ? _Tokens.error : _Tokens.navy,
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
          "Add Supplier",
          style: GoogleFonts.sora(fontWeight: FontWeight.w600, fontSize: 18, color: Colors.white),
        ),
        centerTitle: false,
        backgroundColor: _Tokens.navy,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Supplier Information",
                      style: GoogleFonts.sora(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                        color: _Tokens.navy,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "Enter the supplier's contact and business details.",
                      style: GoogleFonts.sora(fontSize: 13, color: _Tokens.muted),
                    ),
                    const SizedBox(height: 20),

                    _buildInputField(_nameController, "Supplier Name", Icons.person_outline,
                        "Please enter supplier name"),
                    _buildInputField(_companyController, "Company Name",
                        Icons.business_outlined, "Please enter company name"),
                    _buildInputField(_contactController, "Contact Number",
                        Icons.phone_outlined, "Please enter contact number",
                        keyboard: TextInputType.phone),
                    _buildInputField(_emailController, "Email Address", Icons.email_outlined,
                        "Please enter email",
                        keyboard: TextInputType.emailAddress),
                    _buildInputField(_categoryController, "Category / Type",
                        Icons.category_outlined, null,
                        hint: "e.g., Cosmetics, Stationery"),

                    const SizedBox(height: 12),

                    // Save button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isSubmitting ? null : _saveSupplier,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _Tokens.amber,
                          foregroundColor: _Tokens.navyDark,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: _isSubmitting
                            ? SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            color: _Tokens.navyDark,
                            strokeWidth: 2,
                          ),
                        )
                            : const Icon(Icons.save_outlined),
                        label: Text(
                          _isSubmitting ? "Saving..." : "Save Supplier",
                          style: GoogleFonts.sora(fontSize: 15, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // View all suppliers
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const ViewSuppliersScreen()),
                          );
                        },
                        icon: Icon(Icons.list_alt_outlined, color: _Tokens.navy),
                        label: Text(
                          "View All Suppliers",
                          style: GoogleFonts.sora(fontSize: 15, color: _Tokens.navy, fontWeight: FontWeight.w600),
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          side: BorderSide(color: _Tokens.navy),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
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

  Widget _buildInputField(TextEditingController c, String label, IconData icon,
      String? validatorMsg,
      {int maxLines = 1, String? hint, TextInputType? keyboard}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: TextFormField(
        controller: c,
        maxLines: maxLines,
        keyboardType: keyboard,
        style: GoogleFonts.sora(fontSize: 14, color: _Tokens.textDark),
        decoration: InputDecoration(
          prefixIcon: Icon(icon, color: _Tokens.navy),
          labelText: label,
          labelStyle: GoogleFonts.sora(color: _Tokens.muted, fontSize: 14),
          hintText: hint,
          hintStyle: GoogleFonts.sora(color: _Tokens.muted, fontSize: 13),
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
            borderSide: BorderSide(color: _Tokens.amber, width: 1.5),
            borderRadius: BorderRadius.circular(10),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: _Tokens.error),
          ),
        ),
        validator: validatorMsg != null
            ? (v) => (v == null || v.trim().isEmpty) ? validatorMsg : null
            : null,
      ),
    );
  }
}