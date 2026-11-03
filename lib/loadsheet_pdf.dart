import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Load sheets print on A4 portrait with 14 mm margins, in the booker app and the admin panel alike.
const loadSheetPageFormat = PdfPageFormat(210 * PdfPageFormat.mm, 297 * PdfPageFormat.mm, marginAll: 14 * PdfPageFormat.mm);

/// One product line of a load sheet.
class LoadSheetPdfRow {
  final String product;
  final num qty;     // units sold (returns already taken off)
  final num bonus;   // free units, may be fractional
  final double amount; // TP x Qty, before invoice discounts

  const LoadSheetPdfRow({required this.product, required this.qty, required this.bonus, required this.amount});
}

final _money = NumberFormat('#,##0');

String _qty(num v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');

/// The one load sheet layout shared by the booker's print and the admin's print:
/// header, Product / Price / Qty / BNS / Amount table with a TOTAL row (header repeats on every page),
/// then Gross Amount, Discount and Net Amount. [netAmount] is the day's total after invoice discounts.
List<pw.Widget> loadSheetPdfContent({
  required String company,
  required String dateStr,
  required String booker,
  required String areas,
  required List<LoadSheetPdfRow> rows,
  required double netAmount,
}) {
  final sorted = [...rows]..sort((a, b) => a.product.toLowerCase().compareTo(b.product.toLowerCase()));
  final sumQty = sorted.fold<num>(0, (s, r) => s + r.qty);
  final sumBonus = sorted.fold<num>(0, (s, r) => s + r.bonus);
  final gross = sorted.fold<double>(0, (s, r) => s + r.amount);
  final discount = gross - netAmount;

  return [
    pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        pw.Text(company, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
        pw.Text('Load Sheet', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
        pw.Text(dateStr, style: const pw.TextStyle(fontSize: 11)),
      ],
    ),
    pw.SizedBox(height: 6),
    pw.Text('Booker: $booker  |  Area: $areas',
        style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.black)),
    pw.SizedBox(height: 14),
    pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey500, width: 0.5),
      columnWidths: const {
        0: pw.FlexColumnWidth(3.2),
        1: pw.FixedColumnWidth(62),
        2: pw.FixedColumnWidth(50),
        3: pw.FixedColumnWidth(50),
        4: pw.FixedColumnWidth(80),
      },
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
      children: [
        pw.TableRow(
          repeat: true, // header on every page
          decoration: const pw.BoxDecoration(color: PdfColors.grey300),
          children: [
            _cell('Product', bold: true, align: pw.TextAlign.left),
            _cell('Price', bold: true),
            _cell('Qty', bold: true),
            _cell('FOC', bold: true),
            _cell('Amount (PKR)', bold: true),
          ],
        ),
        ...sorted.map((r) => pw.TableRow(children: [
              _cell(r.product, align: pw.TextAlign.left),
              // Average trade price for the day (a product can be sold at different prices).
              _cell(r.qty > 0 ? (r.amount / r.qty).toStringAsFixed(2) : '-'),
              _cell(_qty(r.qty)),
              _cell(_qty(r.bonus)),
              _cell(_money.format(r.amount)),
            ])),
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey100),
          children: [
            _cell('TOTAL', bold: true, align: pw.TextAlign.left),
            _cell(''),
            _cell(_qty(sumQty), bold: true),
            _cell(_qty(sumBonus), bold: true),
            _cell(_money.format(gross), bold: true),
          ],
        ),
      ],
    ),
    pw.SizedBox(height: 10),
    pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Text('Gross Amount: PKR ${_money.format(gross)}', style: const pw.TextStyle(fontSize: 10)),
          pw.Text('Discount: PKR ${_money.format(discount > 0.5 ? discount : 0)}', style: const pw.TextStyle(fontSize: 10)),
          pw.SizedBox(height: 3),
          pw.Text('Net Amount: PKR ${_money.format(netAmount)}',
              style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.green800)),
        ],
      ),
    ),
  ];
}

pw.Widget _cell(String text, {bool bold = false, pw.TextAlign align = pw.TextAlign.right}) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4.5),
      child: pw.Text(text,
          textAlign: align,
          style: pw.TextStyle(fontSize: 9, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
    );
