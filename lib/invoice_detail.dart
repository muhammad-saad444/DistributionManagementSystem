import 'package:flutter/material.dart';
import 'print_preview.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

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
  static const errorBg = Color(0xFFFCE9E7);
  static const green = Color(0xFF12B76A);
  static const amberBg = Color(0xFFFCEEDA);

  static TextStyle display({double size = 18, Color? color, FontWeight w = FontWeight.w600}) =>
      GoogleFonts.sora(fontSize: size, fontWeight: w, color: color ?? textPrimary, height: 1.2);

  static TextStyle body({double size = 13, Color? color, FontWeight w = FontWeight.w400}) =>
      GoogleFonts.inter(fontSize: size, fontWeight: w, color: color ?? textPrimary);
}

class InvoiceDetailPage extends StatefulWidget {
  final Map<String, dynamic> invoiceData;
  final String docId;

  const InvoiceDetailPage({super.key, required this.invoiceData, required this.docId});

  @override
  State<InvoiceDetailPage> createState() => _InvoiceDetailPageState();
}

class _InvoiceDetailPageState extends State<InvoiceDetailPage> {
  late List<dynamic> items;
  late double grandTotal;
  late double total;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    // Load local state
    items = List.from(widget.invoiceData['items'] ?? []);
    grandTotal = (widget.invoiceData['grandTotal'] ?? 0).toDouble();
    total = (widget.invoiceData['total'] ?? 0).toDouble();
  }

  // --- 1. PDF PRINTING LOGIC ---
  Future<void> _printInvoice() async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          pw.Header(
            level: 0,
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text("A.N AGENCY", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 24)),
                pw.Text("INVOICE REPORT", style: pw.TextStyle(fontSize: 18, color: PdfColors.grey700)),
              ],
            ),
          ),
          pw.SizedBox(height: 20),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text("Customer: ${widget.invoiceData['customer']}", style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  pw.Text("Area: ${widget.invoiceData['area'] ?? '-'}"),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text("Invoice #: ${widget.invoiceData['invoiceNumber']}"),
                  pw.Text("Date: ${widget.invoiceData['salesDate']}"),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 20),

          // Items Table
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            headers: ['Product', 'Qty', 'Ret', 'Price', 'Gross', 'Net'],
            data: items.map((item) {
              double qty = double.tryParse(item['QTY'].toString()) ?? 0;
              double retQty = double.tryParse(item['returnQty']?.toString() ?? "0") ?? 0;
              double tp = double.tryParse(item['TP'].toString()) ?? 0;
              double gross = double.tryParse(item['Gross Total'].toString()) ?? 0;
              double netItemTotal = gross - (retQty * tp);

              return [
                item['Product Name'],
                qty.toStringAsFixed(0),
                retQty > 0 ? "-${retQty.toStringAsFixed(0)}" : "0",
                tp.toStringAsFixed(2),
                gross.toStringAsFixed(2),
                netItemTotal.toStringAsFixed(2),
              ];
            }).toList(),
          ),

          pw.SizedBox(height: 30),
          pw.Divider(),
          pw.Container(
            alignment: pw.Alignment.centerRight,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text("Original Total: Rs. ${widget.invoiceData['total']}"),
                pw.Text("Total Returns: Rs. ${(double.parse(widget.invoiceData['total'].toString()) - total).toStringAsFixed(2)}",
                    style: pw.TextStyle(color: PdfColors.red)),
                pw.SizedBox(height: 5),
                pw.Text("Adjusted Grand Total: Rs. ${grandTotal.toStringAsFixed(2)}",
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16, color: PdfColors.green900)),
              ],
            ),
          ),
        ],
      ),
    );

    if (!mounted) return;
    await showPrintPreview(
      context,
      title: 'Invoice #${widget.invoiceData['invoiceNumber']}',
      buildPdf: pdf.save,
      fileName: 'Invoice_${widget.invoiceData['invoiceNumber']}.pdf',
    );
  }

  // --- 2. RETURN CALCULATION LOGIC ---
  Future<void> _processReturn(int index) async {
    final item = items[index];
    final TextEditingController returnQtyController = TextEditingController();

    double originalQty = double.tryParse(item['QTY'].toString()) ?? 0;
    double tp = double.tryParse(item['TP'].toString()) ?? 0;
    double currentRetQty = double.tryParse(item['returnQty']?.toString() ?? "0") ?? 0;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text("Add Return", style: _Tokens.display(size: 18)),
        content: TextField(
          controller: returnQtyController,
          keyboardType: TextInputType.number,
          style: _Tokens.body(),
          decoration: InputDecoration(
            labelText: "Quantity to Return",
            labelStyle: _Tokens.body(color: _Tokens.textSecondary),
            helperText: "Remaining for return: ${originalQty - currentRetQty}",
            helperStyle: _Tokens.body(size: 12, color: _Tokens.textSecondary),
            filled: true,
            fillColor: _Tokens.bg,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _Tokens.border)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _Tokens.amber, width: 1.5)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("Cancel", style: _Tokens.body(color: _Tokens.textSecondary, w: FontWeight.w600)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _Tokens.amber,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              double addedRetQty = double.tryParse(returnQtyController.text) ?? 0;
              if (addedRetQty > 0 && addedRetQty <= (originalQty - currentRetQty)) {
                setState(() {
                  double deduction = addedRetQty * tp;

                  // Update return fields without touching original QTY/Gross
                  items[index]['returnQty'] = (currentRetQty + addedRetQty).toStringAsFixed(0);
                  items[index]['returnAmount'] =
                      ((double.tryParse(item['returnAmount']?.toString() ?? "0") ?? 0) + deduction).toStringAsFixed(2);

                  // Update overall Invoice Totals
                  grandTotal -= deduction;
                  total -= deduction;
                });
                Navigator.pop(context);
                _saveToFirestore();
              }
            },
            child: Text("Apply", style: _Tokens.body(w: FontWeight.w600, color: _Tokens.navyDark)),
          ),
        ],
      ),
    );
  }

  // --- 3. FIRESTORE SYNC ---
  Future<void> _saveToFirestore() async {
    setState(() => _isSaving = true);
    try {
      await FirebaseFirestore.instance
          .collection('invoices')
          .doc(widget.docId)
          .update({
        'items': items,
        'grandTotal': grandTotal,
        'total': total,
      });
      _toast("Update synced to cloud");
    } catch (e) {
      _toast("Cloud sync error: $e", error: true);
    } finally {
      setState(() => _isSaving = false);
    }
  }

  void _toast(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: error ? _Tokens.error : _Tokens.navyDark,
        content: Text(msg, style: _Tokens.body(color: Colors.white)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _Tokens.bg,
      appBar: AppBar(
        title: Text(
          'Manage Returns',
          style: _Tokens.display(size: 18, color: Colors.white),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        backgroundColor: _Tokens.navyDark,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(tooltip: 'Print Preview', icon: const Icon(Icons.print_outlined), onPressed: _printInvoice),
        ],
        bottom: _isSaving
            ? PreferredSize(
          preferredSize: const Size.fromHeight(3),
          child: LinearProgressIndicator(color: _Tokens.amber, backgroundColor: _Tokens.navySlate),
        )
            : null,
      ),
      body: Column(
        children: [
          // SUMMARY CARD
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            color: _Tokens.navyDark,
            child: Column(
              children: [
                _summaryRow("Original Total", "Rs. ${widget.invoiceData['total']}", Colors.white70),
                const SizedBox(height: 10),
                _summaryRow("Adjusted Total", "Rs. ${grandTotal.toStringAsFixed(2)}", _Tokens.amber, isBold: true),
              ],
            ),
          ),

          // ITEMS TABLE
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _Tokens.border),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2)),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Items', style: _Tokens.display(size: 16)),
                    const SizedBox(height: 12),
                    LayoutBuilder(builder: (context, constraints) {
                      final isMobile = constraints.maxWidth < 620;
                      return isMobile ? _buildItemsCardList() : _buildItemsGrid();
                    }),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Wide-screen layout: hand-built grid with exact flex-based column
  // widths, so it can never hit the classic DataTable overflow issue.
  Widget _buildItemsGrid() {
    const flexes = [3, 2, 2, 2, 1];
    final headers = ['Product', 'Orig Qty', 'Ret Qty', 'Gross', 'Action'];

    Widget row(List<Widget> cells, {bool isHeader = false}) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        decoration: BoxDecoration(
          color: isHeader ? _Tokens.bg : Colors.transparent,
          borderRadius: isHeader ? BorderRadius.circular(8) : null,
          border: isHeader ? null : const Border(bottom: BorderSide(color: _Tokens.border, width: 1)),
        ),
        child: Row(
          children: List.generate(cells.length, (i) => Expanded(flex: flexes[i], child: cells[i])),
        ),
      );
    }

    return Column(
      children: [
        row(headers.map((h) => Text(h, style: _Tokens.body(color: _Tokens.textPrimary, w: FontWeight.w700))).toList(), isHeader: true),
        ...List.generate(items.length, (index) {
          final item = items[index];
          final retQty = item['returnQty'] ?? "0";
          return row([
            Text(item['Product Name'] ?? "-", style: _Tokens.body(color: _Tokens.textPrimary), overflow: TextOverflow.ellipsis),
            Text(item['QTY'] ?? "0", style: _Tokens.body(color: _Tokens.textSecondary)),
            Text(retQty, style: _Tokens.body(color: _Tokens.error, w: FontWeight.w600)),
            Text(item['Gross Total'] ?? "0", style: _Tokens.body(color: _Tokens.textPrimary)),
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                icon: const Icon(Icons.keyboard_return, color: _Tokens.amber),
                onPressed: () => _processReturn(index),
                tooltip: 'Add return',
              ),
            ),
          ]);
        }),
      ],
    );
  }

  // Mobile layout: each item as a compact card instead of a squeezed table.
  Widget _buildItemsCardList() {
    return Column(
      children: List.generate(items.length, (index) {
        final item = items[index];
        final retQty = item['returnQty'] ?? "0";
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _Tokens.bg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _Tokens.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(child: Text(item['Product Name'] ?? "-", style: _Tokens.display(size: 14))),
                  IconButton(
                    icon: const Icon(Icons.keyboard_return, color: _Tokens.amber, size: 20),
                    onPressed: () => _processReturn(index),
                    tooltip: 'Add return',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Qty: ${item['QTY'] ?? "0"}', style: _Tokens.body(color: _Tokens.textSecondary)),
                  Text('Returned: $retQty', style: _Tokens.body(color: _Tokens.error, w: FontWeight.w600)),
                  Text('Gross: ${item['Gross Total'] ?? "0"}', style: _Tokens.body(color: _Tokens.textPrimary, w: FontWeight.w600)),
                ],
              ),
            ],
          ),
        );
      }),
    );
  }

  Widget _summaryRow(String label, String value, Color color, {bool isBold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: _Tokens.body(color: color, size: 14)),
        Text(
          value,
          style: isBold
              ? _Tokens.display(size: 20, color: color)
              : _Tokens.body(color: color, size: 14),
        ),
      ],
    );
  }
}