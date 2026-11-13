// The month's sales tax, for filing: every invoice that carries tax, with the shop's NTN or CNIC,
// the value without tax and the tax, by rate.
import 'package:cloud_firestore/cloud_firestore.dart';

import '../account/account.dart';
import 'invoice_tax.dart';

class SalesTaxLine {
  final String invoiceId;
  final String number;
  final DateTime date;
  final String shop;
  final String ntn;
  final String cnic;
  final double rate; // the band's rate
  final double taxable;
  final double tax;
  final double total; // the invoice's whole bill (same on each of its bands)
  const SalesTaxLine({
    required this.invoiceId,
    required this.number,
    required this.date,
    required this.shop,
    required this.ntn,
    required this.cnic,
    required this.rate,
    required this.taxable,
    required this.tax,
    required this.total,
  });

  bool get registered => ntn.isNotEmpty;
}

/// One line per invoice and rate, for invoices that carry tax. [buyers]: shop name (lower case) →
/// (NTN, CNIC).
List<SalesTaxLine> salesTaxLines(Iterable<(String, Map<String, dynamic>)> invoices, Map<String, (String, String)> buyers) {
  final out = <SalesTaxLine>[];
  for (final (id, m) in invoices) {
    final t = savedInvoiceTax(m);
    if (t == null) continue;
    final shop = '${m['customer'] ?? ''}'.trim();
    final b = buyers[shop.toLowerCase()];
    final ts = m['salesDateTs'];
    for (final band in t.bands) {
      out.add(SalesTaxLine(
        invoiceId: id,
        number: '${m['invoiceNumber'] ?? ''}',
        date: ts is Timestamp ? ts.toDate() : DateTime(2000),
        shop: shop,
        ntn: b?.$1 ?? '',
        cnic: b?.$2 ?? '',
        rate: band.rate,
        taxable: band.taxable,
        tax: band.tax,
        total: t.grandTotal,
      ));
    }
  }
  out.sort((a, b) {
    final d = a.date.compareTo(b.date);
    return d != 0 ? d : (int.tryParse(a.number) ?? 0).compareTo(int.tryParse(b.number) ?? 0);
  });
  return out;
}

/// The month starting [month]: its taxed invoices, and how many invoices it had in all.
Future<(List<SalesTaxLine>, int)> loadSalesTax(DateTime month) async {
  final from = DateTime(month.year, month.month);
  final to = DateTime(month.year, month.month + 1);
  final results = await Future.wait([
    companyCol('invoices')
        .where('salesDateTs', isGreaterThanOrEqualTo: Timestamp.fromDate(from))
        .where('salesDateTs', isLessThan: Timestamp.fromDate(to))
        .get(),
    companyCol('customers').get(),
  ]);
  final buyers = <String, (String, String)>{
    for (final d in results[1].docs)
      '${d.data()['name'] ?? ''}'.trim().toLowerCase(): ('${d.data()['ntn'] ?? ''}'.trim(), '${d.data()['cnic'] ?? ''}'.trim()),
  };
  final invoices = results[0].docs;
  return (salesTaxLines([for (final d in invoices) (d.id, d.data())], buyers), invoices.length);
}
