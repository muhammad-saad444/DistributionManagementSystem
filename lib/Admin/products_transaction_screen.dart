import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

// ---------------------------------------------------------------------------
// Same design tokens used across the rest of the app. Worth pulling into a
// shared lib/design_tokens.dart at some point instead of duplicating this
// class per file.
// ---------------------------------------------------------------------------
class _Tokens {
  static const navyDark = Color(0xFF131C31);
  static const navySlate = Color(0xFF24345C);
  static const amber = Color(0xFFE8973A);
  static const bg = Color(0xFFF5F6F8);
  static const textPrimary = Color(0xFF101828);
  static const textSecondary = Color(0xFF667085);
  static const border = Color(0xFFE4E7EC);
  static const error = Color(0xFFD92D20);
  static const green = Color(0xFF12B76A);

  static TextStyle display({double size = 18, Color? color, FontWeight w = FontWeight.w600}) =>
      GoogleFonts.sora(fontSize: size, fontWeight: w, color: color ?? textPrimary, height: 1.2);

  static TextStyle body({double size = 13, Color? color, FontWeight w = FontWeight.w400}) =>
      GoogleFonts.inter(fontSize: size, fontWeight: w, color: color ?? textPrimary);
}

class ProductTransactionsScreen extends StatefulWidget {
  final String productName;

  const ProductTransactionsScreen({Key? key, required this.productName})
      : super(key: key);

  @override
  State<ProductTransactionsScreen> createState() =>
      _ProductTransactionsScreenState();
}

class _ProductTransactionsScreenState extends State<ProductTransactionsScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final DateFormat _format = DateFormat('dd MMM yyyy, hh:mm a');
  bool _isLoading = true;

  List<Map<String, dynamic>> _transactions = [];

  @override
  void initState() {
    super.initState();
    _loadTransactions();
  }

  Future<void> _loadTransactions() async {
    setState(() => _isLoading = true);
    try {
      final productName = widget.productName;
      List<Map<String, dynamic>> transactions = [];

      // 🔹 Fetch restock (product creation as stock addition)
      final productDocs = await _firestore
          .collection('products')
          .where('productName', isEqualTo: productName)
          .get();

      for (var doc in productDocs.docs) {
        final data = doc.data();
        final createdAt = data['createdAt'] != null
            ? (data['createdAt'] as Timestamp).toDate()
            : null;
        final baseStock = int.tryParse(data['baseSize']?.toString() ?? '0') ?? 0;

        transactions.add({
          'type': 'credit',
          'description': 'Initial Stock Added',
          'qty': baseStock,
          'amount': 0,
          'user': 'System',
          'date': createdAt ?? DateTime.now(),
        });
      }

      // 🔹 Fetch sales (load_sheets)
      final loadSheets = await _firestore.collection('load_sheets').get();
      for (var doc in loadSheets.docs) {
        final data = doc.data();
        final date = data['generatedAt'] != null
            ? (data['generatedAt'] as Timestamp).toDate()
            : null;

        final userEmail = data['userEmail'] ?? 'Unknown User';
        final items = data['items'];

        if (items != null) {
          for (var item in items) {
            if (item['productName'] == productName) {
              transactions.add({
                'type': 'debit',
                'description': 'Sold by $userEmail',
                'qty': (item['qty'] ?? 0).toInt(),
                'amount': (item['amount'] ?? 0).toDouble(),
                'user': userEmail,
                'date': date ?? DateTime.now(),
              });
            }
          }
        }
      }

      // 🔹 Sort oldest → newest
      transactions.sort((a, b) =>
          (a['date'] ?? DateTime.now()).compareTo(b['date'] ?? DateTime.now()));

      // 🔹 Compute running balance
      num runningBalance = 0;
      for (var t in transactions) {
        if (t['type'] == 'credit') {
          runningBalance += t['qty'];
        } else if (t['type'] == 'debit') {
          runningBalance -= t['qty'];
        }
        t['balance'] = runningBalance < 0 ? 0 : runningBalance;
      }

      setState(() {
        _transactions = transactions;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint("Error loading transactions: $e");
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _Tokens.bg,
      appBar: AppBar(
        title: Text(
          "${widget.productName} Statement",
          style: _Tokens.display(size: 17, color: Colors.white),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        centerTitle: true,
        backgroundColor: _Tokens.navyDark,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: _Tokens.amber))
          : _transactions.isEmpty
          ? Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.receipt_long_outlined, size: 48, color: _Tokens.textSecondary),
            const SizedBox(height: 12),
            Text("No transactions found.", style: _Tokens.body(color: _Tokens.textSecondary, size: 14)),
          ],
        ),
      )
          : Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Header bar
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
              decoration: BoxDecoration(
                color: _Tokens.navyDark,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Expanded(
                      flex: 2,
                      child: Text("Date", style: _Tokens.body(color: Colors.white, w: FontWeight.w700, size: 12))),
                  Expanded(
                      flex: 3,
                      child: Text("Description", style: _Tokens.body(color: Colors.white, w: FontWeight.w700, size: 12))),
                  Expanded(
                      child: Text("Debit",
                          textAlign: TextAlign.right,
                          style: _Tokens.body(color: Colors.white, w: FontWeight.w700, size: 12))),
                  Expanded(
                      child: Text("Credit",
                          textAlign: TextAlign.right,
                          style: _Tokens.body(color: Colors.white, w: FontWeight.w700, size: 12))),
                  Expanded(
                      child: Text("Balance",
                          textAlign: TextAlign.right,
                          style: _Tokens.body(color: Colors.white, w: FontWeight.w700, size: 12))),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // Transaction list
            Expanded(
              child: ListView.builder(
                physics: const BouncingScrollPhysics(),
                itemCount: _transactions.length,
                itemBuilder: (context, index) {
                  final t = _transactions[index];
                  final isDebit = t['type'] == 'debit';
                  final dateStr = t['date'] != null
                      ? DateFormat('dd MMM').format(t['date'])
                      : '—';
                  final qty = t['qty'] ?? 0;
                  final balance = t['balance'] ?? 0;

                  return Container(
                    margin: const EdgeInsets.symmetric(vertical: 4.0),
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _Tokens.border),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2)),
                      ],
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: Text(dateStr, style: _Tokens.body(color: _Tokens.textSecondary)),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(
                            t['description'],
                            style: _Tokens.body(color: _Tokens.textPrimary),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            isDebit ? "-$qty" : "",
                            textAlign: TextAlign.right,
                            style: _Tokens.body(color: _Tokens.error, w: FontWeight.w600),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            isDebit ? "" : "+$qty",
                            textAlign: TextAlign.right,
                            style: _Tokens.body(color: _Tokens.green, w: FontWeight.w600),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            "$balance",
                            textAlign: TextAlign.right,
                            style: _Tokens.body(color: _Tokens.textPrimary, w: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
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