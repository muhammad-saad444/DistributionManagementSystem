import 'package:flutter/material.dart';
import 'package:an_agency/ui/app_theme.dart';
import '../account/account.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';

// Delete this block and import your shared _Tokens file if you already have one.
class _Tokens {
  static const navy = AppColors.navy;
  static const navyDark = AppColors.navyDark;
  static const amber = AppColors.amber;
  static const bg = AppColors.bg;
  static const border = AppColors.border;
  static const textDark = AppColors.text;
  static const muted = AppColors.muted;
  static const error = AppColors.red;
}

class AllocateCustomerPage extends StatefulWidget {
  const AllocateCustomerPage({super.key});

  @override
  State<AllocateCustomerPage> createState() => _AllocateCustomerPageState();
}

class _AllocateCustomerPageState extends State<AllocateCustomerPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String? _selectedUser;
  List<String> _selectedCustomers = [];
  bool _loading = false;

  Future<void> _allocateCustomers() async {
    if (_selectedUser == null || _selectedCustomers.isEmpty) {
      _showSnack('Please select a user and at least one customer');
      return;
    }

    setState(() => _loading = true);

    try {
      final docRef = companyCol('user_customers').doc(_selectedUser);

      final docSnap = await docRef.get();

      List<dynamic> existingCustomers = [];
      if (docSnap.exists) {
        final data = docSnap.data() as Map<String, dynamic>;
        existingCustomers = List<String>.from(data['customers'] ?? []);
      }

      final updatedList = {...existingCustomers, ..._selectedCustomers}.toList();

      await docRef.set({
        'username': _selectedUser,
        'customers': updatedList,
        'updated_at': FieldValue.serverTimestamp(),
      });

      _showSnack('Customers updated for $_selectedUser');

      setState(() {
        _selectedUser = null;
        _selectedCustomers.clear();
      });
    } catch (e) {
      _showSnack('Error: $e', err: true);
    }

    setState(() => _loading = false);
  }

  Future<void> _removeCustomer(String username, String customerName) async {
    try {
      final docRef = companyCol('user_customers').doc(username);
      final docSnap = await docRef.get();

      if (docSnap.exists) {
        final data = docSnap.data() as Map<String, dynamic>;
        final list = List<String>.from(data['customers'] ?? []);
        list.remove(customerName);

        await docRef.update({
          'customers': list,
          'updated_at': FieldValue.serverTimestamp(),
        });

        _showSnack('"$customerName" removed from $username');
      }
    } catch (e) {
      _showSnack('Error removing customer: $e', err: true);
    }
  }

  bool _isCustomerSelected(String name) => _selectedCustomers.contains(name);

  void _toggleCustomerSelection(String name) {
    setState(() {
      if (_selectedCustomers.contains(name)) {
        _selectedCustomers.remove(name);
      } else {
        _selectedCustomers.add(name);
      }
    });
  }

  void _showSnack(String msg, {bool err = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.inter()),
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
          'Allocate customers',
          style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 18, color: AppColors.text),
        ),
        centerTitle: false,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Select User', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: _Tokens.textDark)),
            const SizedBox(height: 8),

            StreamBuilder<QuerySnapshot>(
              stream: companyCol('sessions').snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Text('Error loading users', style: GoogleFonts.inter(color: _Tokens.error));
                }
                if (!snapshot.hasData) {
                  return Center(child: CircularProgressIndicator(color: _Tokens.navy));
                }

                final users = snapshot.data!.docs;

                if (users.isEmpty) {
                  return Text('No users found in sessions table', style: GoogleFonts.inter(color: _Tokens.muted));
                }

                return DropdownButtonFormField<String>(
                  value: _selectedUser,
                  isExpanded: true,
                  hint: Text('Choose a user', style: GoogleFonts.inter(color: _Tokens.muted, fontSize: 14)),
                  style: GoogleFonts.inter(fontSize: 14, color: _Tokens.textDark),
                  items: users.map((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    final username = data['username'] ?? 'Unknown';
                    return DropdownMenuItem<String>(
                      value: username,
                      child: Text(username, overflow: TextOverflow.ellipsis),
                    );
                  }).toList(),
                  onChanged: (val) => setState(() => _selectedUser = val),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: _Tokens.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: _Tokens.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: _Tokens.amber, width: 1.5),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                );
              },
            ),

            const SizedBox(height: 20),
            Text('Select Customers', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: _Tokens.textDark)),
            const SizedBox(height: 8),

            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: companyCol('customers').orderBy('name').snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(child: Text('Error loading customers.', style: GoogleFonts.inter(color: _Tokens.error)));
                  }
                  if (!snapshot.hasData) {
                    return Center(child: CircularProgressIndicator(color: _Tokens.navy));
                  }

                  final customers = snapshot.data!.docs;

                  if (customers.isEmpty) {
                    return Center(child: Text('No customers found.', style: GoogleFonts.inter(color: _Tokens.muted)));
                  }

                  return Container(
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
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: customers.length,
                      separatorBuilder: (_, __) => Divider(height: 1, color: _Tokens.border),
                      itemBuilder: (context, index) {
                        final data = customers[index].data() as Map<String, dynamic>;
                        final name = data['name'] ?? '';
                        final code = data['code'] ?? '';
                        final area = data['area'] ?? '';

                        return CheckboxListTile(
                          title: Text(name, style: GoogleFonts.inter(fontSize: 14, color: _Tokens.textDark)),
                          subtitle: Text(
                            "Code: $code — Area: $area",
                            style: GoogleFonts.inter(fontSize: 12.5, color: _Tokens.muted),
                          ),
                          value: _isCustomerSelected(name),
                          activeColor: _Tokens.amber,
                          checkColor: _Tokens.navyDark,
                          onChanged: (_) => _toggleCustomerSelection(name),
                        );
                      },
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 12),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _loading ? null : _allocateCustomers,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _Tokens.amber,
                  foregroundColor: _Tokens.navyDark,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: _loading
                    ? SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(color: _Tokens.navyDark, strokeWidth: 2),
                )
                    : const Icon(Icons.check_circle_outline),
                label: Text(
                  _loading ? 'Updating...' : 'Update Customer Allocation',
                  style: GoogleFonts.inter(fontSize: 14.5, fontWeight: FontWeight.w600),
                ),
              ),
            ),

            Divider(height: 34, thickness: 1, color: _Tokens.border),

            Text(
              'Current Customer Allocations',
              style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w700, color: _Tokens.navy),
            ),
            const SizedBox(height: 10),

            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: companyCol('user_customers')
                    .orderBy('updated_at', descending: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(child: Text('Error loading data.', style: GoogleFonts.inter(color: _Tokens.error)));
                  }
                  if (!snapshot.hasData) {
                    return Center(child: CircularProgressIndicator(color: _Tokens.navy));
                  }

                  final allocations = snapshot.data!.docs;

                  if (allocations.isEmpty) {
                    return Center(child: Text('No allocations yet.', style: GoogleFonts.inter(color: _Tokens.muted)));
                  }

                  return ListView.separated(
                    itemCount: allocations.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final doc = allocations[index];
                      final data = doc.data() as Map<String, dynamic>;
                      final username = data['username'] ?? '';
                      final List<dynamic> customers = data['customers'] ?? [];

                      return Container(
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
                        child: Theme(
                          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                          child: ExpansionTile(
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: _Tokens.navy.withOpacity(0.06),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(Icons.person_outline, color: _Tokens.navy, size: 20),
                            ),
                            title: Text(
                              username,
                              style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14.5, color: _Tokens.textDark),
                            ),
                            iconColor: _Tokens.navy,
                            collapsedIconColor: _Tokens.muted,
                            children: customers.map((c) {
                              return ListTile(
                                title: Text(c, style: GoogleFonts.inter(fontSize: 13.5, color: _Tokens.textDark)),
                                trailing: IconButton(
                                  icon: Icon(Icons.delete_outline, color: _Tokens.error),
                                  onPressed: () => _removeCustomer(username, c),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            )
          ],
        ),
      ),
    );
  }
}