import 'package:flutter/material.dart';
import 'package:an_agency/ui/app_theme.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'DSR.dart';
import 'print_preview.dart';

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

class DsrDetailPage extends StatelessWidget {
  final Map<String, dynamic> data;
  const DsrDetailPage({super.key, required this.data});

  static const double _desktopBreakpoint = 700;

  @override
  Widget build(BuildContext context) {
    final List<dynamic> rowsData = data['rows'] ?? [];

    final List<Map<String, dynamic>> tableItems = [];
    double totalSumQty = 0;
    Set<String> uniqueProducts = {};
    double totalNetSale = 0;

    for (var row in rowsData) {
      final String customer = row["customer"] ?? "N/A";
      final double netSale = (row["netSale"] ?? 0).toDouble();
      totalNetSale += netSale;

      final Map<String, dynamic> productQtyMap =
      Map<String, dynamic>.from(row["productQty"] ?? {});

      productQtyMap.forEach((pName, pQty) {
        uniqueProducts.add(pName);
        double qty = (pQty is num) ? pQty.toDouble() : 0;
        totalSumQty += qty;

        tableItems.add({
          "customer": customer,
          "productName": pName,
          "qty": qty,
          "netSale": netSale,
        });
      });
    }

    tableItems.sort((a, b) =>
        a["productName"].toString().compareTo(b["productName"].toString()));

    return Scaffold(
      backgroundColor: _Tokens.bg,
      appBar: AppBar(
        elevation: 0,
        centerTitle: false,
        actions: [
          IconButton(
            tooltip: 'Print',
            icon: const Icon(Icons.print_outlined, color: AppColors.text),
            onPressed: rowsData.isEmpty ? null : () => _print(context),
          ),
        ],
        title: Text(
          "DSR Detail — ${data["dateStr"] ?? 'Report'}",
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w600,
            fontSize: 18,
            color: AppColors.text,
          ),
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isDesktop = constraints.maxWidth >= _desktopBreakpoint;
          final maxContentWidth = isDesktop ? 1100.0 : constraints.maxWidth;

          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxContentWidth),
              child: Padding(
                padding: EdgeInsets.all(isDesktop ? 24 : 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // SUMMARY CARDS
                    if (isDesktop)
                      Row(
                        children: [
                          Expanded(
                            child: _summaryCard("Invoices", rowsData.length.toString(),
                                Icons.receipt_long_outlined),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _summaryCard("Products", uniqueProducts.length.toString(),
                                Icons.category_outlined),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _summaryCard("Net Sale", totalNetSale.toStringAsFixed(0),
                                Icons.payments_outlined, highlight: true),
                          ),
                        ],
                      )
                    else
                      Row(
                        children: [
                          Expanded(
                            child: _summaryCard("Invoices", rowsData.length.toString(),
                                Icons.receipt_long_outlined),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _summaryCard("Products", uniqueProducts.length.toString(),
                                Icons.category_outlined),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _summaryCard("Net Sale", totalNetSale.toStringAsFixed(0),
                                Icons.payments_outlined, highlight: true),
                          ),
                        ],
                      ),

                    const SizedBox(height: 12),

                    // DATA TABLE — fills available width on desktop, denser on mobile
                    Expanded(
                      child: Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: _Tokens.border),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        padding: EdgeInsets.all(isDesktop ? 18 : 12),
                        child: LayoutBuilder(
                          builder: (context, tableConstraints) {
                            return SingleChildScrollView(
                              scrollDirection: Axis.vertical,
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    minWidth: tableConstraints.maxWidth,
                                  ),
                                  child: DataTable(
                                    columnSpacing: isDesktop ? 60 : 22,
                                    horizontalMargin: isDesktop ? 20 : 12,
                                    dataRowMinHeight: isDesktop ? 52 : 44,
                                    dataRowMaxHeight: isDesktop ? 56 : 48,
                                    headingRowHeight: isDesktop ? 52 : 44,
                                    headingRowColor:
                                    MaterialStateProperty.all(_Tokens.navy.withOpacity(0.06)),
                                    headingTextStyle: GoogleFonts.inter(
                                      fontWeight: FontWeight.w600,
                                      color: _Tokens.navy,
                                      fontSize: isDesktop ? 14 : 13,
                                    ),
                                    dataTextStyle: GoogleFonts.inter(
                                      fontSize: isDesktop ? 14 : 13,
                                      color: _Tokens.textDark,
                                    ),
                                    columns: const [
                                      DataColumn(label: Text("Customer")),
                                      DataColumn(label: Text("Product")),
                                      DataColumn(label: Text("Qty")),
                                      DataColumn(label: Text("Net Sale")),
                                    ],
                                    rows: tableItems.map((item) => DataRow(cells: [
                                      DataCell(Text(item["customer"])),
                                      DataCell(Text(item["productName"])),
                                      DataCell(Text(item["qty"].toString())),
                                      DataCell(Text(
                                        item["netSale"].toString(),
                                        style: GoogleFonts.inter(
                                          fontWeight: FontWeight.w600,
                                          color: _Tokens.navy,
                                        ),
                                      )),
                                    ])).toList(),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// The saved report, in the same printed layout as today's DSR.
  InvoiceDsrReport _report() => InvoiceDsrReport(
        dateStr: '${data['dateStr'] ?? ''}',
        generatedAt: data['generatedAt'] is Timestamp ? data['generatedAt'] as Timestamp : Timestamp.now(),
        userId: '${data['userId'] ?? ''}',
        userEmail: data['userEmail']?.toString(),
        rows: [
          for (final r in (data['rows'] as List? ?? const []))
            if (r is Map) InvoiceDsrRow.fromMap({...Map<String, dynamic>.from(r), 'customer': '${r['customer'] ?? 'N/A'}'}),
        ],
      );

  void _print(BuildContext context) {
    final report = _report();
    showPrintPreview(
      context,
      title: 'DSR ${report.dateStr}',
      buildPdf: () async => (await buildDsrPdf(report)).save(),
      fileName: 'DSR_${report.dateStr}.pdf',
    );
  }

  Widget _summaryCard(String label, String value, IconData icon, {bool highlight = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: BoxDecoration(
        color: highlight ? _Tokens.amber.withOpacity(0.14) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: highlight ? _Tokens.amber.withOpacity(0.4) : _Tokens.border,
        ),
        boxShadow: highlight
            ? []
            : [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, size: 18, color: highlight ? _Tokens.amber : _Tokens.navy),
          const SizedBox(height: 8),
          Text(
            label,
            style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: _Tokens.muted),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700, color: _Tokens.textDark),
          ),
        ],
      ),
    );
  }
}