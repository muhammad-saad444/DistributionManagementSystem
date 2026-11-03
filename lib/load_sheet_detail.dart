import 'package:flutter/material.dart';
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

class LoadSheetDetailPage extends StatelessWidget {
  final Map<String, dynamic> data;
  const LoadSheetDetailPage({super.key, required this.data});

  static const double _desktopBreakpoint = 700;

  @override
  Widget build(BuildContext context) {
    final items = List<Map<String, dynamic>>.from(data["items"] ?? []);
    final totals = data["totals"] ?? {};
    final String dateStr = data["dateStr"] ?? '';
    final String userEmail = data["userEmail"] ?? '';
    final generatedAt = data["generatedAt"];

    items.sort((a, b) =>
        (a["productName"] ?? "").toString().compareTo((b["productName"] ?? "").toString()));

    return Scaffold(
      backgroundColor: _Tokens.bg,
      appBar: AppBar(
        backgroundColor: _Tokens.navy,
        elevation: 0,
        centerTitle: false,
        title: Text(
          "Load Sheet — $dateStr",
          style: GoogleFonts.sora(
            fontWeight: FontWeight.w600,
            fontSize: 18,
            color: Colors.white,
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
                    // TOP INFO CARD
                    Container(
                      padding: const EdgeInsets.all(14),
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
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: _Tokens.navy.withOpacity(0.06),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(Icons.badge_outlined, color: _Tokens.navy, size: 22),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "User: $userEmail",
                                  style: GoogleFonts.sora(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14.5,
                                    color: _Tokens.textDark,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  "Date: $dateStr  •  Generated: ${generatedAt != null ? generatedAt.toDate().toLocal() : '-'}",
                                  style: GoogleFonts.sora(fontSize: 12.5, color: _Tokens.muted),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),

                    // METRIC CARDS — full-width row on desktop, wrap on mobile
                    if (isDesktop)
                      Row(
                        children: [
                          Expanded(
                            child: _metricCard("Unique Products", "${totals['uniqueProducts']}",
                                Icons.category_outlined),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _metricCard("Total Qty", "${totals['sumQty']}",
                                Icons.inventory_2_outlined),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _metricCard("Total FOC", _fmtQty(totals['sumBns']),
                                Icons.card_giftcard_outlined),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _metricCard("Total Sale (PKR)", _fmtMoney(totals['sumAmount']),
                                Icons.payments_outlined, highlight: true),
                          ),
                        ],
                      )
                    else
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          _metricCard("Unique Products", "${totals['uniqueProducts']}",
                              Icons.category_outlined, fixedWidth: 168),
                          _metricCard("Total Qty", "${totals['sumQty']}",
                              Icons.inventory_2_outlined, fixedWidth: 168),
                          _metricCard("Total FOC", _fmtQty(totals['sumBns']),
                              Icons.card_giftcard_outlined, fixedWidth: 168),
                          _metricCard("Total Sale (PKR)", _fmtMoney(totals['sumAmount']),
                              Icons.payments_outlined, highlight: true, fixedWidth: 168),
                        ],
                      ),

                    const SizedBox(height: 12),

                    // TABLE — fills available width, denser on mobile, roomier on desktop
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
                        padding: EdgeInsets.all(isDesktop ? 18 : 14),
                        child: LayoutBuilder(
                          builder: (context, tableConstraints) {
                            return SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: ConstrainedBox(
                                // forces the table to stretch to fill the card
                                // instead of shrink-wrapping to its content
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
                                  headingTextStyle: GoogleFonts.sora(
                                    fontWeight: FontWeight.w600,
                                    color: _Tokens.navy,
                                    fontSize: isDesktop ? 14 : 13,
                                  ),
                                  dataTextStyle: GoogleFonts.sora(
                                    fontSize: isDesktop ? 14 : 13,
                                    color: _Tokens.textDark,
                                  ),
                                  columns: const [
                                    DataColumn(label: Text("Product")),
                                    DataColumn(label: Text("Qty")),
                                    DataColumn(label: Text("FOC")),
                                    DataColumn(label: Text("Amount")),
                                  ],
                                  rows: items.map((r) {
                                    return DataRow(
                                      cells: [
                                        DataCell(Text(r["productName"].toString())),
                                        DataCell(Text(r["qty"].toString())),
                                        DataCell(Text(_fmtQty(r["bns"]))),
                                        DataCell(Text(
                                          _fmtMoney(r["amount"]),
                                          style: GoogleFonts.sora(
                                            fontWeight: FontWeight.w600,
                                            color: _Tokens.navy,
                                          ),
                                        )),
                                      ],
                                    );
                                  }).toList(),
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

  Widget _metricCard(String title, String value, IconData icon,
      {bool highlight = false, double? fixedWidth}) {
    final card = Container(
      padding: const EdgeInsets.all(14),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: highlight ? _Tokens.amber : _Tokens.navy),
          const SizedBox(height: 8),
          Text(
            title,
            style: GoogleFonts.sora(fontSize: 12, fontWeight: FontWeight.w600, color: _Tokens.muted),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: GoogleFonts.sora(fontSize: 18, fontWeight: FontWeight.w700, color: _Tokens.textDark),
          ),
        ],
      ),
    );

    return fixedWidth != null ? SizedBox(width: fixedWidth, child: card) : card;
  }

  /// Bonus can be fractional: whole numbers without ".0", fractions to at most 2 decimals.
  String _fmtQty(dynamic v) {
    final d = double.tryParse((v ?? 0).toString()) ?? 0.0;
    if (d == d.roundToDouble()) return d.toInt().toString();
    return d.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');
  }

  String _fmtMoney(dynamic v) {
    if (v == null) return "0.00";
    try {
      return double.parse(v.toString()).toStringAsFixed(2);
    } catch (_) {
      return v.toString();
    }
  }
}