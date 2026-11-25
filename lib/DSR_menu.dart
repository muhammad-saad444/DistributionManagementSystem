import 'package:flutter/material.dart';
import 'package:an_agency/ui/app_theme.dart';
import 'account/account.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'DSR_detail.dart'; // Ensure this matches your filename

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

class DsrMenuPage extends StatefulWidget {
  const DsrMenuPage({super.key});

  @override
  State<DsrMenuPage> createState() => _DsrMenuPageState();
}

class _DsrMenuPageState extends State<DsrMenuPage> {
  String? loggedEmail;

  @override
  void initState() {
    super.initState();
    _loadLoggedUserEmail();
  }

  Future<void> _loadLoggedUserEmail() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final sessionSnap = await companyCol('sessions')
        .doc(user.uid)
        .get();

    if (sessionSnap.exists && sessionSnap.data() != null) {
      loggedEmail = sessionSnap.data()!['email'];
    } else {
      loggedEmail = user.email; // Fallback
    }
    if (mounted) setState(() {});
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
        stream: companyCol('dsr_reports')
            .where("userEmail", isEqualTo: loggedEmail)
            .orderBy("generatedAt", descending: true)
            .snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return _stateMessage(
              icon: Icons.error_outline,
              title: "Error loading reports",
              subtitle: "${snap.error}",
            );
          }
          if (!snap.hasData) {
            return Center(child: CircularProgressIndicator(color: _Tokens.navy));
          }

          final docs = snap.data!.docs;
          if (docs.isEmpty) {
            return _stateMessage(
              icon: Icons.description_outlined,
              title: "No reports found",
              subtitle: "DSRs you generate will show up here.",
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
            itemCount: docs.length,
            separatorBuilder: (context, index) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final data = docs[index].data() as Map<String, dynamic>;

              // Logic aligned with your reference model
              final List<dynamic> rows = data['rows'] ?? [];
              int invoiceCount = rows.length;
              double totalQty = 0;

              for (var row in rows) {
                final productQtyMap = row['productQty'] as Map? ?? {};
                productQtyMap.forEach((_, qty) {
                  if (qty is num) {
                    totalQty += qty.toDouble();
                  }
                });
              }

              return _dsrTile(
                dateStr: "${data['dateStr'] ?? 'N/A'}",
                invoiceCount: "$invoiceCount",
                qty: totalQty.toStringAsFixed(0),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => DsrDetailPage(data: data)),
                ),
              );
            },
          );
        },
      ),
    );
  }

  AppBar _appBar() {
    return AppBar(
      elevation: 0,
      centerTitle: false,
      title: Text(
        "DSR Reports",
        style: GoogleFonts.inter(
          fontWeight: FontWeight.w600,
          fontSize: 18,
          color: AppColors.text,
        ),
      ),
    );
  }

  Widget _dsrTile({
    required String dateStr,
    required String invoiceCount,
    required String qty,
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
                child: Icon(Icons.description_outlined, color: _Tokens.amber, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "DSR — $dateStr",
                      style: GoogleFonts.inter(
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
                        _statChip("Invoices", invoiceCount),
                        _statChip("Qty", qty),
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
        style: GoogleFonts.inter(fontSize: 12, color: _Tokens.muted),
        children: [
          TextSpan(text: "$label: "),
          TextSpan(
            text: value,
            style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: _Tokens.navy),
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
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w600,
              fontSize: 15,
              color: _Tokens.textDark,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: 13, color: _Tokens.muted),
          ),
        ],
      ),
    );
  }
}