import 'package:flutter/material.dart';
import 'account/account.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// ---------------------------------------------------------------------------
// Same design tokens used across auth_screen.dart and dashboard_screen.dart.
// Worth pulling into a shared lib/design_tokens.dart at some point instead
// of duplicating this class per file.
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
  static const error = Color(0xFFD92D20);
  static const green = Color(0xFF12B76A);

  static TextStyle display({double size = 20, Color? color, FontWeight w = FontWeight.w600}) =>
      GoogleFonts.sora(fontSize: size, fontWeight: w, color: color ?? textPrimary, height: 1.2);

  static TextStyle body({double size = 14, Color? color, FontWeight w = FontWeight.w400}) =>
      GoogleFonts.inter(fontSize: size, fontWeight: w, color: color ?? textPrimary);
}

class AddCustomerPage extends StatefulWidget {
  const AddCustomerPage({Key? key}) : super(key: key);

  @override
  State<AddCustomerPage> createState() => _AddCustomerPageState();
}

class _AddCustomerPageState extends State<AddCustomerPage> {
  final _formKey = GlobalKey<FormState>();

  // Controllers
  final TextEditingController _codeController =
  TextEditingController(text: _generateCustomerCode());
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _salesnameController = TextEditingController();
  final TextEditingController _contactController = TextEditingController();
  final TextEditingController _cnicController = TextEditingController();
  final TextEditingController _ntnController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();

  String? _selectedCustomerType;
  String? _selectedArea;
  String? _selectedSalesman;

  List<String> _areaList = [];
  bool _isLoadingAreas = true;

  bool _isLoadingSalesmen = true;

  bool _isSubmitting = false;

  static String _generateCustomerCode() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return 'CUST-${timestamp.toString().substring(6)}';
  }

  @override
  void initState() {
    super.initState();
    _fetchAreasForCurrentUser();
    _fetchSalesmen();
  }

  // ==================== FETCH AREAS ====================
  Future<void> _fetchAreasForCurrentUser() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() => _isLoadingAreas = false);
        return;
      }

      final sessionSnap = await companyCol('sessions')
          .doc(user.uid)
          .get();

      if (!sessionSnap.exists) {
        setState(() => _isLoadingAreas = false);
        return;
      }

      final username = (sessionSnap.data()?['username'] ?? '').toString().trim();

      final areaSnap = await companyCol('user_areas')
          .where('username', isEqualTo: username)
          .limit(1)
          .get();

      if (areaSnap.docs.isNotEmpty) {
        final data = areaSnap.docs.first.data();
        final fetchedAreas = List<String>.from(data['areas'] ?? []);
        setState(() {
          _areaList = fetchedAreas;
          _selectedArea = _areaList.isNotEmpty ? _areaList.first : null;
        });
      }
    } catch (e) {
      debugPrint("Error fetching areas: $e");
    } finally {
      setState(() => _isLoadingAreas = false);
    }
  }

  // ==================== SALESMAN = LOGGED-IN BOOKER ====================
  // A shop is always registered to the booker who adds it, so the name comes from their own session
  // and can't be changed (the old dropdown listed every user in the app).
  Future<void> _fetchSalesmen() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      String name = '';
      if (user != null) {
        final snap = await companyCol('sessions').doc(user.uid).get();
        name = (snap.data()?['username'] ?? user.displayName ?? user.email ?? '').toString().trim();
      }
      if (!mounted) return;
      setState(() {
        _selectedSalesman = name.isEmpty ? null : name;
        _salesnameController.text = name;
        _isLoadingSalesmen = false;
      });
    } catch (e) {
      debugPrint("Error loading salesman name: $e");
      if (mounted) setState(() => _isLoadingSalesmen = false);
    }
  }

  // ==================== SUBMIT CUSTOMER FORM ====================
  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showSnack('Please log in first', error: true);
      return;
    }

    setState(() => _isSubmitting = true);

    final newCustomer = {
      'code': _codeController.text,
      'name': _nameController.text,
      'contact': _contactController.text,
      'cnic': _cnicController.text,
      'ntn': _ntnController.text,
      'address': _addressController.text,
      'type': _selectedCustomerType,
      'area': _selectedArea,
      'salesman': _selectedSalesman,
      'createdAt': FieldValue.serverTimestamp(),
    };

    try {
      await companyCol('customers').add(newCustomer);
      if (!mounted) return;
      _showSnack('Customer added successfully');

      _formKey.currentState?.reset();
      setState(() {
        _codeController.text = _generateCustomerCode();
        _salesnameController.text = _selectedSalesman ?? '';
        _selectedCustomerType = null;
        _selectedArea = null;
      });
    } catch (e) {
      if (!mounted) return;
      _showSnack('Failed to add customer: $e', error: true);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showSnack(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: error ? _Tokens.error : _Tokens.navyDark,
        content: Text(message, style: _Tokens.body(color: Colors.white)),
      ),
    );
  }

  // ==================== UI ====================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _Tokens.bg,
      appBar: AppBar(
        title: Text(
          'Add Customer',
          style: _Tokens.display(size: 18, color: Colors.white),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        backgroundColor: _Tokens.navyDark,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _isLoadingAreas || _isLoadingSalesmen
          ? Center(child: CircularProgressIndicator(color: _Tokens.amber))
          : SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Container(
              padding: const EdgeInsets.all(28.0),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _Tokens.border),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4)),
                ],
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Customer details', style: _Tokens.display(size: 20)),
                    const SizedBox(height: 4),
                    Text(
                      'Fill in the fields below to add a new customer.',
                      style: _Tokens.body(color: _Tokens.textSecondary),
                    ),
                    const SizedBox(height: 24),
                    Wrap(
                      runSpacing: 20,
                      spacing: 20,
                      children: [
                        buildDisabledTextField('Customer Code', _codeController),

                        // Salesman: the logged-in booker, not editable
                        buildDisabledTextField('Salesman Name', _salesnameController),

                        buildTextField('Customer Name', _nameController, Icons.person_outline),
                        buildTextField('Customer Contact', _contactController, Icons.call_outlined),
                        buildCnicField(),
                        buildTextField('Customer NTN', _ntnController, Icons.description_outlined),
                        buildTextField('Customer Address', _addressController, Icons.home_outlined),

                        buildDropdownField(
                          'Customer Type',
                          Icons.storefront_outlined,
                          ['Shop', 'WholeSeller', 'Retailer'],
                              (val) => setState(() => _selectedCustomerType = val),
                          _selectedCustomerType,
                        ),

                        buildDropdownField(
                          'Area',
                          Icons.map_outlined,
                          _areaList.isNotEmpty ? _areaList : ['No areas assigned'],
                              (val) => setState(() => _selectedArea = val),
                          _selectedArea,
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _isSubmitting ? null : _submitForm,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _Tokens.amber,
                          disabledBackgroundColor: _Tokens.amber.withOpacity(0.6),
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: _isSubmitting
                            ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.4, color: _Tokens.navyDark),
                        )
                            : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.person_add_alt_1, color: _Tokens.navyDark, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              'Add Customer',
                              style: _Tokens.body(size: 15, w: FontWeight.w600, color: _Tokens.navyDark),
                            ),
                          ],
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

  // ==================== HELPERS ====================
  InputDecoration _decoration(String label, {IconData? icon, bool disabled = false}) {
    return InputDecoration(
      labelText: label,
      labelStyle: _Tokens.body(color: _Tokens.textSecondary),
      prefixIcon: icon != null ? Icon(icon, color: _Tokens.textSecondary, size: 20) : null,
      filled: true,
      fillColor: disabled ? _Tokens.border.withOpacity(0.5) : _Tokens.bg,
      contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      counterText: '',
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _Tokens.border),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _Tokens.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _Tokens.amber, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _Tokens.error),
      ),
    );
  }

  Widget buildTextField(String label, TextEditingController controller, [IconData? icon]) {
    return SizedBox(
      width: 300,
      child: TextFormField(
        controller: controller,
        style: _Tokens.body(),
        decoration: _decoration(label, icon: icon),
        validator: (value) => value == null || value.trim().isEmpty ? 'Enter $label' : null,
      ),
    );
  }

  Widget buildDisabledTextField(String label, TextEditingController controller) {
    return SizedBox(
      width: 300,
      child: TextFormField(
        controller: controller,
        enabled: false,
        style: _Tokens.body(color: _Tokens.textSecondary),
        decoration: _decoration(label, icon: Icons.lock_outline, disabled: true),
      ),
    );
  }

  Widget buildDropdownField(
      String label,
      IconData icon,
      List<String> items,
      void Function(String?) onChanged,
      String? selectedValue,
      ) {
    final isEmpty = items.first == 'No salesmen found' || items.first == 'No areas assigned';
    return SizedBox(
      width: 300,
      child: DropdownButtonFormField<String>(
        isExpanded: true,
        value: selectedValue,
        style: _Tokens.body(color: _Tokens.textPrimary),
        icon: Icon(Icons.keyboard_arrow_down, color: _Tokens.textSecondary),
        decoration: _decoration(label, icon: icon),
        items: items.map((item) => DropdownMenuItem(value: item, child: Text(item))).toList(),
        onChanged: isEmpty ? null : onChanged,
        validator: (value) => value == null ? 'Please select $label' : null,
      ),
    );
  }

  Widget buildCnicField() {
    return SizedBox(
      width: 300,
      child: TextFormField(
        controller: _cnicController,
        keyboardType: TextInputType.number,
        maxLength: 15,
        style: _Tokens.body(),
        decoration: _decoration('Customer CNIC', icon: Icons.badge_outlined).copyWith(
          hintText: '12345-1234567-1',
          hintStyle: _Tokens.body(color: _Tokens.textSecondary.withOpacity(0.6)),
        ),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[\d-]')),
          _CnicInputFormatter(),
        ],
        validator: (value) {
          final cnicRegex = RegExp(r'^\d{5}-\d{7}-\d{1}$');
          if (value == null || !cnicRegex.hasMatch(value)) {
            return 'Enter valid CNIC (e.g. 12345-1234567-1)';
          }
          return null;
        },
      ),
    );
  }
}

// ==================== CNIC FORMATTER ====================
class _CnicInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    String digitsOnly = newValue.text.replaceAll(RegExp(r'\D'), '');
    String formatted = '';

    if (digitsOnly.length >= 5) {
      formatted += digitsOnly.substring(0, 5) + '-';
      if (digitsOnly.length >= 12) {
        formatted += digitsOnly.substring(5, 12) +
            '-' +
            digitsOnly.substring(12, digitsOnly.length.clamp(12, 13));
      } else if (digitsOnly.length > 5) {
        formatted += digitsOnly.substring(5);
      }
    } else {
      formatted = digitsOnly;
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}