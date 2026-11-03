import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../khata.dart';

/// Admin panel → Khata: pick a booker by name and see their khata, read-only.
class AdminKhataScreen extends StatefulWidget {
  const AdminKhataScreen({super.key});

  @override
  State<AdminKhataScreen> createState() => _AdminKhataScreenState();
}

class _AdminKhataScreenState extends State<AdminKhataScreen> {
  static const _navy = Color(0xFF15294D);
  static const _bg = Color(0xFFF5F6FA);
  static const _border = Color(0xFFE3E7EF);
  static const _amber = Color(0xFFE0A63A);
  static const _muted = Color(0xFF6B7280);

  List<Map<String, String>> _bookers = [];
  bool _loading = true;
  String? _selectedUid;

  @override
  void initState() {
    super.initState();
    _loadBookers();
  }

  Future<void> _loadBookers() async {
    try {
      final snap = await FirebaseFirestore.instance.collection('sessions').get();
      final list = snap.docs
          .map((d) => d.data())
          .where((m) => (m['email'] ?? '').toString().trim().toLowerCase() != 'admin@gmail.com')
          .map((m) => {
                'uid': (m['uid'] ?? '').toString(),
                'name': (m['username'] ?? m['email'] ?? '').toString(),
                'email': (m['email'] ?? '').toString(),
              })
          .where((m) => m['uid']!.isNotEmpty)
          .toList()
        ..sort((a, b) => a['name']!.toLowerCase().compareTo(b['name']!.toLowerCase()));
      if (!mounted) return;
      setState(() {
        _bookers = list;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    Map<String, String>? selected;
    for (final b in _bookers) {
      if (b['uid'] == _selectedUid) selected = b;
    }
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _navy,
        elevation: 0,
        title: Text('Khata', style: GoogleFonts.sora(fontWeight: FontWeight.w600, fontSize: 18, color: Colors.white)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
            child: _loading
                ? const LinearProgressIndicator(color: _navy)
                : DropdownButtonFormField<String>(
                    initialValue: _selectedUid,
                    isExpanded: true,
                    hint: Text('Select a booker to see their khata', style: GoogleFonts.sora(color: _muted, fontSize: 13)),
                    decoration: InputDecoration(
                      labelText: 'Booker',
                      labelStyle: GoogleFonts.sora(color: _muted),
                      filled: true,
                      fillColor: Colors.white,
                      isDense: true,
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _border)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _amber, width: 1.5)),
                    ),
                    items: _bookers
                        .map((b) => DropdownMenuItem(
                              value: b['uid'],
                              child: Text('${b['name']}  ·  ${b['email']}', overflow: TextOverflow.ellipsis, style: GoogleFonts.sora(fontSize: 13)),
                            ))
                        .toList(),
                    onChanged: (v) => setState(() => _selectedUid = v),
                  ),
          ),
          Expanded(
            child: selected == null
                ? Center(
                    child: Text(
                      _bookers.isEmpty && !_loading ? 'No bookers found' : 'Select a booker above',
                      style: GoogleFonts.sora(color: _muted),
                    ),
                  )
                : KhataView(
                    key: ValueKey(selected['uid']),
                    userId: selected['uid']!,
                    bookerName: selected['name']!,
                    readOnly: true,
                  ),
          ),
        ],
      ),
    );
  }
}
