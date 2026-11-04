import 'package:an_agency/Admin/view_supplier.dart';
import 'package:flutter/material.dart';

import '../crm/crm_ui.dart';
import '../inventory/supplier_form.dart';

/// Admin → Add Supplier: the full supplier form, with a way to the list of all suppliers.
class AddSupplierScreen extends StatelessWidget {
  const AddSupplierScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CrmTokens.bg,
      appBar: AppBar(
        title: Text('Add Supplier', style: CrmTokens.display(size: 18, color: Colors.white, w: FontWeight.w600)),
        centerTitle: false,
        backgroundColor: CrmTokens.navy,
        elevation: 0,
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ViewSuppliersScreen())),
            icon: const Icon(Icons.list_alt_outlined, color: Colors.white, size: 18),
            label: Text('All suppliers', style: CrmTokens.body(color: Colors.white, w: FontWeight.w600)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: const SupplierForm(),
          ),
        ),
      ),
    );
  }
}
