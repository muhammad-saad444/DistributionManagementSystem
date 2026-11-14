// The printed invoice, the same for the office and the booker: the company's details (name,
// address, NTN, STRN), the shop's (address, contact, NTN or CNIC), the goods, the discount, sales
// tax when the invoice has it, the amount in words, the company's note and signature lines.
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';

import '../account/account.dart';
import 'company_profile.dart';
import 'invoice_tax.dart';
import '../inventory/packs.dart';

/// The shop as the invoice shows it (from the customers list).
class Buyer {
  final String name;
  final String address;
  final String contact;
  final String ntn;
  final String cnic;
  const Buyer({this.name = '', this.address = '', this.contact = '', this.ntn = '', this.cnic = ''});
}

final Map<String, Buyer?> _buyers = {};

/// The shop called [name] in the customers list, if it's there.
Future<Buyer?> loadBuyer(String name) async {
  final key = name.trim().toLowerCase();
  if (key.isEmpty) return null;
  if (_buyers.containsKey(key)) return _buyers[key];
  try {
    final snap = await companyCol('customers').where('name', isEqualTo: name.trim()).limit(1).get();
    final m = snap.docs.isEmpty ? null : snap.docs.first.data();
    String s(String k) => (m?[k] ?? '').toString().trim();
    _buyers[key] = m == null ? null : Buyer(name: s('name'), address: s('address'), contact: s('contact'), ntn: s('ntn'), cnic: s('cnic'));
  } catch (_) {
    _buyers[key] = null; // e.g. no access: print without the shop's details
  }
  return _buyers[key];
}

/// Everything an invoice needs printed, read once.
Future<(CompanyProfile, Buyer?)> invoicePrintDetails(Map invoice) async =>
    (await loadCompanyProfile(), await loadBuyer('${invoice['customer'] ?? ''}'));

double _n(dynamic v) => (num.tryParse('${v ?? 0}') ?? 0).toDouble();
final _money = NumberFormat('#,##0.00');
String _q(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();
String _pct(double v) => '${_q(v)}%';

const _navy = PdfColor.fromInt(0xFF1F3A5F);
const _brass = PdfColor.fromInt(0xFFB7862C);
const _muted = PdfColor.fromInt(0xFF6B7280);
const _line = PdfColor.fromInt(0xFFE2E5EA);
const _soft = PdfColor.fromInt(0xFFEDF2F8);

/// One invoice as pages. [booker]: who booked it (name or email).
pw.MultiPage invoicePdfPage(Map invoice, {required CompanyProfile profile, Buyer? buyer, String booker = '', String area = ''}) {
  final items = [for (final it in (invoice['items'] as List? ?? const [])) if (it is Map) it];
  final tax = savedInvoiceTax(invoice);
  final grand = _n(invoice['grandTotal'] ?? invoice['total']);
  final goods = items.fold<double>(0, (s, it) => s + lineValue(it));
  final net = tax?.net ?? grand;
  final discount = goods - net;
  final hasReturns = items.any((it) => _n(it['returnQty']) > 0);
  final mixedRates = tax != null && items.any((it) => lineRate(it, tax.rate) != tax.rate);
  final title = tax != null ? 'SALES TAX INVOICE' : 'INVOICE';
  final shopArea = area.isNotEmpty ? area : '${invoice['area'] ?? ''}';

  pw.Widget small(String t, {PdfColor color = _muted, pw.FontWeight? weight}) =>
      pw.Text(t, style: pw.TextStyle(fontSize: 8.5, color: color, fontWeight: weight));
  pw.Widget kv(String k, String v) => v.trim().isEmpty
      ? pw.SizedBox()
      : pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 1.5),
          child: pw.RichText(
            text: pw.TextSpan(children: [
              pw.TextSpan(text: '$k  ', style: const pw.TextStyle(fontSize: 8.5, color: _muted)),
              pw.TextSpan(text: v, style: const pw.TextStyle(fontSize: 9)),
            ]),
          ),
        );
  pw.Widget totalRow(String k, String v, {bool strong = false, PdfColor? color}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Row(children: [
          pw.Expanded(child: pw.Text(k, style: pw.TextStyle(fontSize: strong ? 10.5 : 9, fontWeight: strong ? pw.FontWeight.bold : null, color: color))),
          pw.Text(v, style: pw.TextStyle(fontSize: strong ? 10.5 : 9, fontWeight: strong ? pw.FontWeight.bold : null, color: color)),
        ]),
      );

  final headers = ['#', 'Product', 'Size', 'Qty', 'Free', if (hasReturns) 'Ret', 'Rate', if (mixedRates) 'Tax', 'Amount'];
  final rows = <List<String>>[
    for (var i = 0; i < items.length; i++)
      [
        '${i + 1}',
        '${items[i]['Product Name'] ?? ''}',
        '${items[i]['Size'] ?? ''}',
        cartonLabel(_n(items[i]['QTY']) - _n(items[i]['returnQty']), perCartonOf(items[i])),
        _q(_n(items[i]['BNS'] ?? items[i]['FOC'])),
        if (hasReturns) _q(_n(items[i]['returnQty'])),
        _money.format(_n(items[i]['TP'])),
        if (mixedRates) _pct(lineRate(items[i], tax.rate)),
        _money.format(lineValue(items[i])),
      ],
  ];
  final right = <int>{3, 4, if (hasReturns) 5, headers.indexOf('Rate'), if (mixedRates) headers.indexOf('Tax'), headers.length - 1};

  return pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(32, 30, 32, 30),
    footer: (c) => pw.Row(children: [
      pw.Expanded(child: small('Computer-generated invoice · depotOS')),
      small('Page ${c.pageNumber} of ${c.pagesCount}'),
    ]),
    build: (c) => [
      // ---- header: the company, and the invoice
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Expanded(
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(profile.name, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: _navy)),
            pw.SizedBox(height: 3),
            if (profile.address.isNotEmpty) small(profile.address),
            if (profile.phone.isNotEmpty || profile.email.isNotEmpty)
              small([profile.phone, profile.email].where((s) => s.isNotEmpty).join('  ·  ')),
            if (profile.ntn.isNotEmpty || profile.strn.isNotEmpty)
              small([if (profile.ntn.isNotEmpty) 'NTN ${profile.ntn}', if (profile.strn.isNotEmpty) 'STRN ${profile.strn}'].join('  ·  '),
                  color: PdfColors.black),
          ]),
        ),
        pw.SizedBox(width: 16),
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
          pw.Text(title, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: _brass, letterSpacing: 1)),
          pw.SizedBox(height: 6),
          pw.Text('No. ${invoice['invoiceNumber'] ?? '-'}', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
          small('Date ${invoice['salesDate'] ?? '-'}', color: PdfColors.black),
          if (booker.isNotEmpty) small('Booked by $booker'),
        ]),
      ]),
      pw.SizedBox(height: 10),
      pw.Container(height: 2, color: _navy),
      pw.SizedBox(height: 10),

      // ---- the shop
      pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.all(9),
        decoration: pw.BoxDecoration(color: _soft, borderRadius: pw.BorderRadius.circular(4)),
        child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Expanded(
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              small('BILL TO', weight: pw.FontWeight.bold),
              pw.SizedBox(height: 2),
              pw.Text('${invoice['customer'] ?? '-'}', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
              if ((buyer?.address ?? '').isNotEmpty) small(buyer!.address, color: PdfColors.black),
            ]),
          ),
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            kv('Area', shopArea),
            kv('Contact', buyer?.contact ?? ''),
            kv('NTN', buyer?.ntn ?? ''),
            if ((buyer?.ntn ?? '').isEmpty) kv('CNIC', buyer?.cnic ?? ''),
          ]),
        ]),
      ),
      pw.SizedBox(height: 12),

      // ---- the goods
      pw.TableHelper.fromTextArray(
        headers: headers,
        data: rows,
        border: null,
        headerStyle: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
        headerDecoration: const pw.BoxDecoration(color: _navy),
        cellStyle: const pw.TextStyle(fontSize: 9),
        cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
        rowDecoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: _line, width: .6))),
        columnWidths: {0: const pw.FixedColumnWidth(20), 1: const pw.FlexColumnWidth(3)},
        cellAlignments: {for (final i in right) i: pw.Alignment.centerRight},
        headerAlignments: {for (var i = 0; i < headers.length; i++) i: right.contains(i) ? pw.Alignment.centerRight : pw.Alignment.centerLeft},
      ),
      pw.SizedBox(height: 10),

      // ---- totals
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Expanded(
          child: pw.Padding(
            padding: const pw.EdgeInsets.only(right: 24, top: 2),
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              small('AMOUNT IN WORDS', weight: pw.FontWeight.bold),
              pw.SizedBox(height: 2),
              pw.Text(rupeesInWords(grand), style: const pw.TextStyle(fontSize: 9)),
              if (tax != null && tax.inclusive) ...[
                pw.SizedBox(height: 6),
                small('Prices include sales tax.'),
              ],
            ]),
          ),
        ),
        pw.SizedBox(
          width: 220,
          child: pw.Column(children: [
            totalRow('Total', _money.format(goods)),
            if (discount.abs() >= 0.5)
              totalRow(
                  'Discount${invoice['discountType'] == 'percent' ? ' (${_q(_n(invoice['discountPercent']))}%)' : ''}',
                  '- ${_money.format(discount)}'),
            if (tax != null) ...[
              totalRow('Value excluding sales tax', _money.format(tax.taxable)),
              for (final b in tax.bands)
                totalRow(b.rate == 0 ? 'Sales tax (exempt)' : 'Sales tax @ ${_pct(b.rate)}', _money.format(b.tax)),
            ],
            pw.Divider(color: _navy, thickness: 1, height: 8),
            totalRow('Total payable (Rs)', _money.format(grand), strong: true, color: _navy),
          ]),
        ),
      ]),

      // ---- note and signatures
      if (profile.invoiceNote.isNotEmpty) ...[
        pw.SizedBox(height: 14),
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(border: pw.Border.all(color: _line), borderRadius: pw.BorderRadius.circular(4)),
          child: pw.Text(profile.invoiceNote, style: const pw.TextStyle(fontSize: 8.5, color: _muted)),
        ),
      ],
      pw.SizedBox(height: 36),
      pw.Row(children: [
        pw.Expanded(child: _signature('Received by (shop stamp and signature)')),
        pw.SizedBox(width: 40),
        pw.Expanded(child: _signature('For ${profile.name}')),
      ]),
    ],
  );
}

pw.Widget _signature(String label) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Container(height: .8, color: PdfColors.grey600),
      pw.SizedBox(height: 3),
      pw.Text(label, style: const pw.TextStyle(fontSize: 8.5, color: _muted)),
    ]);
