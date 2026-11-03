import 'dart:math' as math;

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// DSR prints are wide (one column per product), so they use A4 landscape with 10 mm margins.
const dsrPageFormat = PdfPageFormat(297 * PdfPageFormat.mm, 210 * PdfPageFormat.mm, marginAll: 10 * PdfPageFormat.mm);

/// One invoice row of a DSR, already formatted for printing.
class DsrPdfRow {
  final String invoice;
  final String customer;
  final Map<String, String> qty; // product -> printed quantity ("12", or "12\nR:3" with returns)
  final String totalSale, discount, netSale;

  const DsrPdfRow({
    required this.invoice,
    required this.customer,
    required this.qty,
    required this.totalSale,
    required this.discount,
    required this.netSale,
  });
}

// Column widths in points. A product column never gets narrower than _minProductW,
// which fits a 5-digit quantity at 7 pt without wrapping.
const double _invoiceW = 34, _customerW = 96, _saleW = 46, _discountW = 40, _netW = 46;
const double _minProductW = 24, _maxProductW = 46;

/// Builds the DSR table for a [pw.MultiPage] so it stays readable however many products there are:
///  - product names are printed vertically, so a long name doesn't need a wide column;
///  - when there are more products than fit across the page, the table continues in further
///    blocks ("Products 26 to 40 of 40"), each repeating Invoice # and Customer;
///  - the header row repeats at the top of every page, and Total Sale / Discount / Net Sale
///    appear in the last block.
List<pw.Widget> dsrPdfTables({
  required double availableWidth,
  required List<String> products,
  required List<DsrPdfRow> rows,
  required Map<String, String> productTotals,
  required String totalSale,
  required String discount,
  required String netSale,
  Map<String, String>? productBonus, // bonus units per product, printed as a BONUS row above TOTAL
}) {
  const moneyW = _saleW + _discountW + _netW;
  final perBlock = math.max(1, ((availableWidth - _invoiceW - _customerW - moneyW) / _minProductW).floor());

  final blocks = <List<String>>[];
  for (var i = 0; i < products.length; i += perBlock) {
    blocks.add(products.sublist(i, math.min(i + perBlock, products.length)));
  }
  if (blocks.isEmpty) blocks.add(const []);

  final out = <pw.Widget>[];
  var first = 0;
  for (var b = 0; b < blocks.length; b++) {
    final chunk = blocks[b];
    final isLast = b == blocks.length - 1;
    if (blocks.length > 1) {
      out.add(pw.Padding(
        padding: pw.EdgeInsets.only(top: b == 0 ? 0 : 14, bottom: 4),
        child: pw.Text(
          'Products ${first + 1} to ${first + chunk.length} of ${products.length}', // plain text: the built-in PDF font has no en dash
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
        ),
      ));
    }
    // Spread spare width over the product columns (capped), the customer column takes the rest.
    final fixed = _invoiceW + _customerW + (isLast ? moneyW : 0);
    final productW = chunk.isEmpty
        ? _minProductW
        : ((availableWidth - fixed) / chunk.length).clamp(_minProductW, _maxProductW).toDouble();
    out.add(_table(
      chunk: chunk,
      productW: productW,
      withMoney: isLast,
      rows: rows,
      productTotals: productTotals,
      productBonus: productBonus,
      totalSale: totalSale,
      discount: discount,
      netSale: netSale,
    ));
    first += chunk.length;
  }
  return out;
}

pw.Widget _table({
  required List<String> chunk,
  required double productW,
  required bool withMoney,
  required List<DsrPdfRow> rows,
  required Map<String, String> productTotals,
  required Map<String, String>? productBonus,
  required String totalSale,
  required String discount,
  required String netSale,
}) {
  final widths = <int, pw.TableColumnWidth>{
    0: const pw.FixedColumnWidth(_invoiceW),
    1: const pw.FlexColumnWidth(1),
  };
  var c = 2;
  for (var _ in chunk) {
    widths[c++] = pw.FixedColumnWidth(productW);
  }
  if (withMoney) {
    widths[c++] = const pw.FixedColumnWidth(_saleW);
    widths[c++] = const pw.FixedColumnWidth(_discountW);
    widths[c++] = const pw.FixedColumnWidth(_netW);
  }

  return pw.Table(
    border: pw.TableBorder.all(color: PdfColors.grey500, width: 0.5),
    columnWidths: widths,
    defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
    children: [
      pw.TableRow(
        repeat: true, // header on every page
        decoration: const pw.BoxDecoration(color: PdfColors.grey300),
        verticalAlignment: pw.TableCellVerticalAlignment.bottom,
        children: [
          _head('Invoice #'),
          _head('Customer Name', align: pw.TextAlign.left),
          ...chunk.map(_productHead),
          if (withMoney) ...[_head('Total Sale'), _head('Discount'), _head('Net Sale')],
        ],
      ),
      ...rows.map((r) => pw.TableRow(children: [
            _cell(r.invoice, align: pw.TextAlign.center),
            _cell(r.customer, align: pw.TextAlign.left, maxLines: 2),
            ...chunk.map((p) => _cell(r.qty[p] ?? '0', maxLines: 2)),
            if (withMoney) ...[_cell(r.totalSale), _cell(r.discount), _cell(r.netSale)],
          ])),
      // Bonus units are free goods: shown for the warehouse, never priced into the sale columns.
      if (productBonus != null)
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFFFF4DC)),
          children: [
            _cell(''),
            _cell('FOC', align: pw.TextAlign.left, bold: true),
            ...chunk.map((p) => _cell(productBonus[p] ?? '0', bold: true)),
            if (withMoney) ...[_cell(''), _cell(''), _cell('')],
          ],
        ),
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey100),
        children: [
          _cell(''),
          _cell('TOTAL', align: pw.TextAlign.left, bold: true),
          ...chunk.map((p) => _cell(productTotals[p] ?? '0', bold: true, maxLines: 2)),
          if (withMoney) ...[
            _cell(totalSale, bold: true),
            _cell(discount, bold: true),
            _cell(netSale, bold: true, color: PdfColors.green800),
          ],
        ],
      ),
    ],
  );
}

pw.Widget _head(String text, {pw.TextAlign align = pw.TextAlign.center}) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 4),
      child: pw.Text(text, textAlign: align, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 7.5)),
    );

/// Product names run bottom-to-top, wrapping onto a second line after ~120 pt.
pw.Widget _productHead(String name) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 4),
      child: pw.Center(
        child: pw.Transform.rotateBox(
          angle: math.pi / 2,
          unconstrained: true, // lay the name out at full length first, then turn it into the narrow column
          child: pw.ConstrainedBox(
            constraints: const pw.BoxConstraints(maxWidth: 120),
            child: pw.Text(name, maxLines: 2, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 7)),
          ),
        ),
      ),
    );

pw.Widget _cell(String text,
        {pw.TextAlign align = pw.TextAlign.right, bool bold = false, PdfColor? color, int maxLines = 1}) =>
    pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 3.5),
      child: pw.Text(
        text,
        textAlign: align,
        maxLines: maxLines,
        style: pw.TextStyle(fontSize: 7.5, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal, color: color),
      ),
    );
