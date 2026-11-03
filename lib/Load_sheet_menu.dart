import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'load_sheet_detail.dart';

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

class LoadSheetMenuPage extends StatefulWidget {
  const LoadSheetMenuPage({super.key});

  @override
  State<LoadSheetMenuPage> createState() => _LoadSheetMenuPageState();
}

class _LoadSheetMenuPageState extends State<LoadSheetMenuPage> {
  String? loggedEmail;

  @override
  void initState() {
    super.initState();
    _loadUserEmail();
  }

  Future<void> _loadUserEmail() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final sessionSnap =
    await FirebaseFirestore.instance.collection("sessions").doc(user.uid).get();

    if (sessionSnap.exists) {
      setState(() => loggedEmail = sessionSnap.data()?["email"]);
    } else {
      setState(() => loggedEmail = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loggedEmail == null) {
      return Scaffold(
        backgroundColor: _Tokens.bg,
        appBar: _appBar(),
        body: Center(child: CircularProgressIndicator(color: _Tokens.navy)),
      );
    }

    return Scaffold(
      backgroundColor: _Tokens.bg,
      appBar: _appBar(),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection("load_sheets")
            .where("userEmail", isEqualTo: loggedEmail)
            .orderBy("generatedAt", descending: true)
            .snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return _stateMessage(
              icon: Icons.error_outline,
              title: "Error loading load sheets",
              subtitle: "Please try again in a moment.",
            );
          }
          if (!snap.hasData) {
            return Center(child: CircularProgressIndicator(color: _Tokens.navy));
          }

          final docs = snap.data!.docs;
          if (docs.isEmpty) {
            return _stateMessage(
              icon: Icons.inventory_2_outlined,
              title: "No load sheets found",
              subtitle: "Load sheets you generate will show up here.",
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) {
              final data = docs[i].data() as Map<String, dynamic>;
              final dateStr = data["dateStr"] ?? "---";
              final totals = data["totals"] ?? {};

              return _loadSheetTile(
                dateStr: dateStr,
                products: "${totals['uniqueProducts'] ?? '-'}",
                qty: "${totals['sumQty'] ?? '-'}",
                amount: "${totals['sumAmount'] ?? '-'}",
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => LoadSheetDetailPage(data: data),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  AppBar _appBar() {
    return AppBar(
      backgroundColor: _Tokens.navy,
      elevation: 0,
      centerTitle: false,
      title: Text(
        "Load Sheets",
        style: GoogleFonts.sora(
          fontWeight: FontWeight.w600,
          fontSize: 18,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _loadSheetTile({
    required String dateStr,
    required String products,
    required String qty,
    required String amount,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
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
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _Tokens.amber.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.inventory_2_outlined, color: _Tokens.amber, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Load Sheet — $dateStr",
                      style: GoogleFonts.sora(
                        fontWeight: FontWeight.w600,
                        fontSize: 14.5,
                        color: _Tokens.textDark,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      children: [
                        _statChip("Products", products),
                        _statChip("Qty", qty),
                        _statChip("Amount", amount),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: _Tokens.muted),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statChip(String label, String value) {
    return RichText(
      text: TextSpan(
        style: GoogleFonts.sora(fontSize: 12, color: _Tokens.muted),
        children: [
          TextSpan(text: "$label: "),
          TextSpan(
            text: value,
            style: GoogleFonts.sora(fontWeight: FontWeight.w600, color: _Tokens.navy),
          ),
        ],
      ),
    );
  }

  Widget _stateMessage({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
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
            child: Icon(icon, size: 40, color: _Tokens.navy.withOpacity(0.6)),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: GoogleFonts.sora(
              fontWeight: FontWeight.w600,
              fontSize: 15,
              color: _Tokens.textDark,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: GoogleFonts.sora(fontSize: 13, color: _Tokens.muted),
          ),
        ],
      ),
    );
  }
}