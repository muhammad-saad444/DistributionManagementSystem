// Renders a worst-case DSR (40 products, 30 invoices) with lib/dsr_pdf_table.dart, to check the layout.
// Run: dart run tool/dsr_pdf_sample.dart <out.pdf>
import 'dart:io';
import 'package:an_agency/dsr_pdf_table.dart';
import 'package:pdf/widgets.dart' as pw;

void main(List<String> args) async {
  final names = [
    'Mango Juice 250ml', 'Tea Whitener 400g', 'Dish Soap 500ml', 'Cooking Oil 1L', 'Detergent 1kg',
    'Biscuits Family Pack', 'ktb 101', 'ktb 102', 'sfc 10', 'sfc 12', 'sig gel', 'sm p70', 'spl 10', 'spl ash',
    'star sfl', 'Super Crisp Chips Masala 30g', 'Orange Drink 1.5L', 'Milk Pack 1L', 'Yogurt 500g', 'Toothpaste 150g',
  ];
  final products = [for (var i = 0; i < 40; i++) i < names.length ? names[i] : '${names[i % names.length]} B${i ~/ names.length}']..sort();
  final rows = [
    for (var i = 0; i < 30; i++)
      DsrPdfRow(
        invoice: '${1000 + i}',
        customer: i % 4 == 0 ? 'Al-Madina General Store & Sons' : 'Shop ${i + 1}',
        qty: {for (var j = 0; j < products.length; j++) products[j]: (i + j) % 7 == 0 ? '${(i * j) % 150}\nR:2' : '${(i * 3 + j) % 120}'},
        totalSale: '${12000 + i * 731}', discount: '${i * 13}', netSale: '${12000 + i * 718}',
      ),
  ];
  final doc = pw.Document();
  doc.addPage(pw.MultiPage(
    pageFormat: dsrPageFormat,
    build: (_) => [
      pw.Text('Daily Sales Report - layout check', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 8),
      ...dsrPdfTables(
        availableWidth: dsrPageFormat.availableWidth,
        products: products,
        rows: rows,
        productTotals: {for (final p in products) p: '12345'},
        productBonus: {for (var j = 0; j < products.length; j++) products[j]: j % 3 == 0 ? '2.5' : '${j % 5}'},
        totalSale: '689,955', discount: '5,655', netSale: '684,300',
      ),
    ],
  ));
  await File(args.isEmpty ? 'dsr_sample.pdf' : args[0]).writeAsBytes(await doc.save());
}
