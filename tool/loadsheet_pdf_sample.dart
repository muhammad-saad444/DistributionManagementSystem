// Renders a sample load sheet with lib/loadsheet_pdf.dart, to check the shared layout.
// Run: dart run tool/loadsheet_pdf_sample.dart <out.pdf>
import 'dart:io';
import 'package:an_agency/loadsheet_pdf.dart';
import 'package:pdf/widgets.dart' as pw;

void main(List<String> args) async {
  final rows = [
    const LoadSheetPdfRow(product: 'Mango Juice 250ml', qty: 144, bonus: 10, amount: 6480),
    const LoadSheetPdfRow(product: 'Tea Whitener 400g', qty: 36, bonus: 3, amount: 14040),
    const LoadSheetPdfRow(product: 'Dish Soap 500ml', qty: 72, bonus: 4.5, amount: 11880),
    const LoadSheetPdfRow(product: 'Cooking Oil 1L', qty: 24, bonus: 2, amount: 13200),
    const LoadSheetPdfRow(product: 'Super Crisp Chips Masala 30g Family Pack', qty: 100, bonus: 0, amount: 2200),
  ];
  final doc = pw.Document()
    ..addPage(pw.MultiPage(
      pageFormat: loadSheetPageFormat,
      build: (_) => loadSheetPdfContent(
        company: 'A.N Agency', dateStr: '2026-10-23', booker: 'noor (noor@example.com)', areas: 'GULSHAN',
        rows: rows, netAmount: 46682,
      ),
    ));
  await File(args.isEmpty ? 'loadsheet_sample.pdf' : args[0]).writeAsBytes(await doc.save());
}
