import 'package:flutter/material.dart';
import 'package:an_agency/ui/app_theme.dart';
import '../account/account.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';

import 'allocate_areas.dart';

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

class AddAreaPage extends StatefulWidget {
  const AddAreaPage({super.key});

  @override
  State<AddAreaPage> createState() => _AddAreaPageState();
}

class _AddAreaPageState extends State<AddAreaPage> {
  final TextEditingController _areaController = TextEditingController();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _loading = false;
  String? _editingId;

  Future<void> _saveArea() async {
    String areaName = _areaController.text.trim();
    if (areaName.isEmpty) {
      _showSnack('Please enter an area name');
      return;
    }

    setState(() => _loading = true);

    try {
      if (_editingId == null) {
        await companyCol('areas').add({
          'name': areaName,
          'created_at': FieldValue.serverTimestamp(),
        });
        _showSnack('Area added successfully!');
      } else {
        await companyCol('areas').doc(_editingId).update({
          'name': areaName,
        });
        _showSnack('Area updated successfully!');
        _editingId = null;
      }

      _areaController.clear();
    } catch (e) {
      _showSnack('Error: $e', err: true);
    }

    setState(() => _loading = false);
  }

  Future<void> _deleteArea(String id) async {
    try {
      await companyCol('areas').doc(id).delete();
      _showSnack('Area deleted successfully!');
    } catch (e) {
      _showSnack('Error deleting area: $e', err: true);
    }
  }

  void _startEditing(String id, String currentName) {
    setState(() {
      _editingId = id;
      _areaController.text = currentName;
    });
  }

  void _cancelEditing() {
    setState(() {
      _editingId = null;
      _areaController.clear();
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
          'Manage Areas',
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
            Container(
              padding: const EdgeInsets.all(16),
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _editingId == null ? 'Enter Area Name' : 'Edit Area Name',
                    style: GoogleFonts.inter(fontSize: 14.5, fontWeight: FontWeight.w600, color: _Tokens.textDark),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _areaController,
                    style: GoogleFonts.inter(fontSize: 14, color: _Tokens.textDark),
                    decoration: InputDecoration(
                      hintText: 'e.g., Clifton, Gulshan, PECHS',
                      hintStyle: GoogleFonts.inter(color: _Tokens.muted, fontSize: 13.5),
                      prefixIcon: Icon(Icons.location_on_outlined, color: _Tokens.navy),
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
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _loading ? null : _saveArea,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _Tokens.amber,
                            foregroundColor: _Tokens.navyDark,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          icon: _loading
                              ? SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(color: _Tokens.navyDark, strokeWidth: 2),
                          )
                              : Icon(_editingId == null ? Icons.add : Icons.check),
                          label: Text(
                            _loading
                                ? 'Saving...'
                                : _editingId == null
                                ? 'Add Area'
                                : 'Update Area',
                            style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14),
                          ),
                        ),
                      ),
                      if (_editingId != null) const SizedBox(width: 10),
                      if (_editingId != null)
                        OutlinedButton(
                          onPressed: _cancelEditing,
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 18),
                            side: BorderSide(color: _Tokens.border),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          child: Text('Cancel', style: GoogleFonts.inter(color: _Tokens.muted, fontWeight: FontWeight.w600)),
                        ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: Icon(Icons.map_outlined, color: _Tokens.navy),
                label: Text(
                  'Go to Allocate Areas Screen',
                  style: GoogleFonts.inter(color: _Tokens.navy, fontWeight: FontWeight.w600, fontSize: 14),
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  side: BorderSide(color: _Tokens.navy),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const AllocateAreaPage()),
                  );
                },
              ),
            ),

            Divider(height: 34, thickness: 1, color: _Tokens.border),
            Text(
              'Existing Areas',
              style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w700, color: _Tokens.navy),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: companyCol('areas')
                    .orderBy('created_at', descending: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(child: Text('Error loading areas.', style: GoogleFonts.inter(color: _Tokens.error)));
                  }
                  if (!snapshot.hasData) {
                    return Center(child: CircularProgressIndicator(color: _Tokens.navy));
                  }

                  final areas = snapshot.data!.docs;

                  if (areas.isEmpty) {
                    return Center(child: Text('No areas added yet.', style: GoogleFonts.inter(color: _Tokens.muted)));
                  }

                  return ListView.separated(
                    itemCount: areas.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final doc = areas[index];
                      final data = doc.data() as Map<String, dynamic>;
                      final areaName = data['name'] ?? 'Unnamed';

                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                        child: ListTile(
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: _Tokens.amber.withOpacity(0.14),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(Icons.location_on_outlined, color: _Tokens.amber, size: 20),
                          ),
                          title: Text(
                            areaName,
                            style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14.5, color: _Tokens.textDark),
                          ),
                          trailing: Wrap(
                            spacing: 4,
                            children: [
                              IconButton(
                                icon: Icon(Icons.edit_outlined, color: _Tokens.navy),
                                onPressed: () => _startEditing(doc.id, areaName),
                              ),
                              IconButton(
                                icon: Icon(Icons.delete_outline, color: _Tokens.error),
                                onPressed: () {
                                  showDialog(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      backgroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                      title: Text(
                                        'Confirm Delete',
                                        style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: _Tokens.textDark),
                                      ),
                                      content: Text(
                                        'Are you sure you want to delete "$areaName"?',
                                        style: GoogleFonts.inter(color: _Tokens.textDark),
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(ctx),
                                          child: Text('Cancel', style: GoogleFonts.inter(color: _Tokens.muted)),
                                        ),
                                        TextButton(
                                          onPressed: () {
                                            Navigator.pop(ctx);
                                            _deleteArea(doc.id);
                                          },
                                          child: Text(
                                            'Delete',
                                            style: GoogleFonts.inter(color: _Tokens.error, fontWeight: FontWeight.w600),
                                          ),
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
            ),
          ],
        ),
      ),
    );
  }
}