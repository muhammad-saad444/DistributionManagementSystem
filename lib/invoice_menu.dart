import 'package:flutter/material.dart';
import 'package:an_agency/ui/app_theme.dart';
import 'account/account.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'invoice_detail.dart';

// ---------------------------------------------------------------------------
// Same design tokens used across the rest of the app. Worth pulling into a
// shared lib/design_tokens.dart at some point instead of duplicating this
// class per file.
// ---------------------------------------------------------------------------
class _Tokens {
  static const navyDark = AppColors.navy;
  static const navySlate = AppColors.navyMid;
  static const amber = AppColors.amber;
  static const bg = AppColors.bg;
  static const textPrimary = AppColors.text;
  static const textSecondary = AppColors.muted;
  static const border = AppColors.border;
  static const error = AppColors.red;
  static const green = AppColors.green;
  static const navySlateBg = AppColors.blueBg;

  static TextStyle display({double size = 18, Color? color, FontWeight w = FontWeight.w600}) =>
      GoogleFonts.inter(fontSize: size, fontWeight: w, color: color ?? textPrimary, height: 1.2);

  static TextStyle body({double size = 13, Color? color, FontWeight w = FontWeight.w400}) =>
      GoogleFonts.inter(fontSize: size, fontWeight: w, color: color ?? textPrimary);
}

class InvoiceMenuPage extends StatefulWidget {
  const InvoiceMenuPage({super.key});

  @override
  State<InvoiceMenuPage> createState() => _InvoiceMenuPageState();
}

class _InvoiceMenuPageState extends State<InvoiceMenuPage> {
  String? loggedEmail;

  @override
  void initState() {
    super.initState();
    _loadUserSession();
  }

  Future<void> _loadUserSession() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final sessionSnap = await companyCol('sessions')
        .doc(user.uid)
        .get();

    if (sessionSnap.exists) {
      setState(() {
        loggedEmail = sessionSnap.data()?['email'];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loggedEmail == null) {
      return Scaffold(
        backgroundColor: _Tokens.bg,
        body: Center(child: CircularProgressIndicator(color: _Tokens.amber)),
      );
    }

    return Scaffold(
      backgroundColor: _Tokens.bg,
      appBar: AppBar(
        title: Text(
          'My Invoices',
          style: _Tokens.display(size: 18, color: AppColors.text),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        elevation: 0,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: companyCol('invoices')
            .where("userEmail", isEqualTo: loggedEmail)
            .orderBy("createdAt", descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Text(
                  "Error: ${snapshot.error}",
                  textAlign: TextAlign.center,
                  style: _Tokens.body(color: _Tokens.error),
                ),
              ),
            );
          }
          if (!snapshot.hasData) {
            return Center(child: CircularProgressIndicator(color: _Tokens.amber));
          }

          final docs = snapshot.data!.docs;
          if (docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.receipt_long_outlined, size: 48, color: _Tokens.textSecondary),
                  const SizedBox(height: 12),
                  Text("No invoices found.", style: _Tokens.body(color: _Tokens.textSecondary)),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index].data() as Map<String, dynamic>;
              final String docId = docs[index].id; // <--- CAPTURE DOC ID

              final grandTotal = data['grandTotal'];
              final amountLabel = grandTotal is num
                  ? 'PKR ${grandTotal.toStringAsFixed(2)}'
                  : null;

              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _Tokens.border),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2)),
                  ],
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  leading: CircleAvatar(
                    backgroundColor: _Tokens.navySlateBg,
                    child: Icon(Icons.receipt_long, color: _Tokens.navySlate),
                  ),
                  title: Text(
                    data['customer'] ?? "Unknown",
                    style: _Tokens.display(size: 15),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      "Invoice #${data['invoiceNumber']} · ${data['salesDate']}",
                      style: _Tokens.body(color: _Tokens.textSecondary),
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (amountLabel != null)
                        Text(amountLabel, style: _Tokens.body(w: FontWeight.w700, color: _Tokens.textPrimary)),
                      const SizedBox(width: 6),
                      Icon(Icons.arrow_forward_ios, size: 14, color: _Tokens.textSecondary),
                    ],
                  ),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => InvoiceDetailPage(
                        invoiceData: data,
                        docId: docId, // <--- PASS DOC ID
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}