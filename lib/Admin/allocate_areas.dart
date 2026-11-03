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

class AllocateAreaPage extends StatefulWidget {
  const AllocateAreaPage({super.key});

  @override
  State<AllocateAreaPage> createState() => _AllocateAreaPageState();
}

class _AllocateAreaPageState extends State<AllocateAreaPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String? _selectedUser;
  List<String> _selectedAreas = [];
  bool _loading = false;

  Future<void> _allocateAreas() async {
    if (_selectedUser == null || _selectedAreas.isEmpty) {
      _showSnack('Please select a user and at least one area');
      return;
    }

    setState(() => _loading = true);

    try {
      final docRef = _firestore.collection('user_areas').doc(_selectedUser);

      final docSnap = await docRef.get();

      List<dynamic> existingAreas = [];
      if (docSnap.exists) {
        final data = docSnap.data() as Map<String, dynamic>;
        existingAreas = List<String>.from(data['areas'] ?? []);
      }

      final updatedAreas = {...existingAreas, ..._selectedAreas}.toList();

      await docRef.set({
        'username': _selectedUser,
        'areas': updatedAreas,
        'updated_at': FieldValue.serverTimestamp(),
      });

      _showSnack('Areas updated for $_selectedUser');

      setState(() {
        _selectedUser = null;
        _selectedAreas.clear();
      });
    } catch (e) {
      _showSnack('Error: $e', err: true);
    }

    setState(() => _loading = false);
  }

  Future<void> _removeArea(String username, String areaName) async {
    try {
      final docRef = _firestore.collection('user_areas').doc(username);
      final docSnap = await docRef.get();

      if (docSnap.exists) {
        final data = docSnap.data() as Map<String, dynamic>;
        final areas = List<String>.from(data['areas'] ?? []);
        areas.remove(areaName);

        await docRef.update({'areas': areas, 'updated_at': FieldValue.serverTimestamp()});
        _showSnack('"$areaName" removed from $username');
      }
    } catch (e) {
      _showSnack('Error removing area: $e', err: true);
    }
  }

  bool _isAreaSelected(String areaName) => _selectedAreas.contains(areaName);

  void _toggleAreaSelection(String areaName) {
    setState(() {
      if (_isAreaSelected(areaName)) {
        _selectedAreas.remove(areaName);
      } else {
        _selectedAreas.add(areaName);
      }
    });
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
          'Allocate Areas to User',
          style: GoogleFonts.sora(fontWeight: FontWeight.w600, fontSize: 18, color: Colors.white),
        ),
        centerTitle: false,
        backgroundColor: _Tokens.navy,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Select User', style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.w600, color: _Tokens.textDark)),
            const SizedBox(height: 8),
            StreamBuilder<QuerySnapshot>(
              stream: _firestore.collection('sessions').snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Text('Error loading users', style: GoogleFonts.sora(color: _Tokens.error));
                }
                if (!snapshot.hasData) {
                  return Center(child: CircularProgressIndicator(color: _Tokens.navy));
                }
                final users = snapshot.data!.docs;

                if (users.isEmpty) {
                  return Text('No users found in sessions table', style: GoogleFonts.sora(color: _Tokens.muted));
                }

                return DropdownButtonFormField<String>(
                  value: _selectedUser,
                  isExpanded: true,
                  hint: Text('Choose a user', style: GoogleFonts.sora(color: _Tokens.muted, fontSize: 14)),
                  style: GoogleFonts.sora(fontSize: 14, color: _Tokens.textDark),
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
            Text('Select Areas', style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.w600, color: _Tokens.textDark)),
            const SizedBox(height: 8),
            Expanded(
              flex: 1,
              child: StreamBuilder<QuerySnapshot>(
                stream: _firestore.collection('areas').snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(child: Text('Error loading areas.', style: GoogleFonts.sora(color: _Tokens.error)));
                  }
                  if (!snapshot.hasData) {
                    return Center(child: CircularProgressIndicator(color: _Tokens.navy));
                  }

                  final areas = snapshot.data!.docs;

                  if (areas.isEmpty) {
                    return Center(child: Text('No areas found.', style: GoogleFonts.sora(color: _Tokens.muted)));
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
                      itemCount: areas.length,
                      separatorBuilder: (_, __) => Divider(height: 1, color: _Tokens.border),
                      itemBuilder: (context, index) {
                        final data = areas[index].data() as Map<String, dynamic>;
                        final areaName = data['name'] ?? '';

                        return CheckboxListTile(
                          title: Text(areaName, style: GoogleFonts.sora(fontSize: 14, color: _Tokens.textDark)),
                          value: _isAreaSelected(areaName),
                          activeColor: _Tokens.amber,
                          checkColor: _Tokens.navyDark,
                          onChanged: (_) => _toggleAreaSelection(areaName),
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
                onPressed: _loading ? null : _allocateAreas,
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
                  _loading ? 'Updating...' : 'Update Allocations for User',
                  style: GoogleFonts.sora(fontSize: 14.5, fontWeight: FontWeight.w600),
                ),
              ),
            ),

            Divider(height: 34, thickness: 1, color: _Tokens.border),
            Text(
              'Current Allocations',
              style: GoogleFonts.sora(fontSize: 17, fontWeight: FontWeight.w700, color: _Tokens.navy),
            ),
            const SizedBox(height: 10),

            Expanded(
              flex: 1,
              child: StreamBuilder<QuerySnapshot>(
                stream: _firestore
                    .collection('user_areas')
                    .orderBy('updated_at', descending: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(child: Text('Error loading data.', style: GoogleFonts.sora(color: _Tokens.error)));
                  }
                  if (!snapshot.hasData) {
                    return Center(child: CircularProgressIndicator(color: _Tokens.navy));
                  }

                  final allocations = snapshot.data!.docs;

                  if (allocations.isEmpty) {
                    return Center(child: Text('No allocations yet.', style: GoogleFonts.sora(color: _Tokens.muted)));
                  }

                  return ListView.separated(
                    itemCount: allocations.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final doc = allocations[index];
                      final data = doc.data() as Map<String, dynamic>;
                      final username = data['username'] ?? 'Unknown';
                      final List<dynamic> userAreas = data['areas'] ?? [];

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
                              style: GoogleFonts.sora(fontWeight: FontWeight.w600, fontSize: 14.5, color: _Tokens.textDark),
                            ),
                            iconColor: _Tokens.navy,
                            collapsedIconColor: _Tokens.muted,
                            children: userAreas.map((area) {
                              return ListTile(
                                title: Text(area, style: GoogleFonts.sora(fontSize: 13.5, color: _Tokens.textDark)),
                                trailing: IconButton(
                                  icon: Icon(Icons.delete_outline, color: _Tokens.error),
                                  onPressed: () => _removeArea(username, area.toString()),
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
            ),
          ],
        ),
      ),
    );
  }
}