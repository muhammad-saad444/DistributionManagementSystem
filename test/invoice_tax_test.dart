// Sales tax on invoices: included in prices or added on top, product rates, discounts, returns,
// the amount in words and the month's sales tax lines.
import 'package:an_agency/invoices/invoice_tax.dart';
import 'package:an_agency/invoices/sales_tax_data.dart';
import 'package:an_agency/returns/returns_data.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final items = [
    {'Product Name': 'Soap', 'QTY': '10', 'TP': '118'}, // 1,180
    {'Product Name': 'Tea', 'QTY': '2', 'TP': '410'}, // 820
  ];

  test('prices include tax: the bill stays, the tax inside it is shown', () {
    final t = computeTax(items, 2000, rate: 18, inclusive: true);
    expect(t.grandTotal, 2000);
    expect(t.tax, 305); // 2000 × 18 / 118
    expect(t.taxable, 1695);
    expect(t.fields['taxInclusive'], isTrue);
  });

  test('tax on top: added after the discount', () {
    final t = computeTax(items, 1800, rate: 18, inclusive: false); // Rs 200 discount
    expect(t.tax, 324);
    expect(t.taxable, 1800);
    expect(t.grandTotal, 2124);
  });

  test('a product with its own rate: the discount is spread by value', () {
    final mixed = [
      {'Product Name': 'Soap', 'QTY': '10', 'TP': '100'}, // 1,000 at 18%
      {'Product Name': 'Milk', 'QTY': '10', 'TP': '100', 'GST': '0'}, // 1,000 exempt
    ];
    final t = computeTax(mixed, 1800, rate: 18, inclusive: false);
    expect(t.bands.map((b) => b.rate), [18, 0]);
    expect(t.bands.first.taxable, 900);
    expect(t.bands.first.tax, 162);
    expect(t.bands.last.tax, 0);
    expect(t.grandTotal, 1962);
  });

  test('returned units are left out of the tax', () {
    final t = computeTax([
      {'QTY': '10', 'TP': '100', 'returnQty': '4'},
    ], 600, rate: 10, inclusive: false);
    expect(t.tax, 60);
  });

  test('an invoice made without tax stays without it', () {
    expect(taxOf({'grandTotal': 500}), isNull);
    expect(retax({'grandTotal': 500}, items, 400), isEmpty);
    expect(savedInvoiceTax({'grandTotal': 500}), isNull);
  });

  test('a saved invoice prints the tax it was made with', () {
    final saved = {'items': items, ...computeTax(items, 1800, rate: 18, inclusive: false).fields};
    final again = savedInvoiceTax(saved)!;
    expect(again.net, 1800);
    expect(again.tax, 324);
    expect(again.grandTotal, 2124);
  });

  test('a return on a tax-on-top invoice takes the tax off too', () {
    final invoice = <String, dynamic>{
      'items': [
        {'Product Name': 'Soap', 'QTY': '10', 'TP': '100'},
      ],
      'total': 1000,
      ...computeTax([
        {'QTY': '10', 'TP': '100'},
      ], 1000, rate: 18, inclusive: false).fields,
    };
    expect(invoice['grandTotal'], 1180);
    final out = applyReturn(invoice, [const ReturnLine(0, 2)]);
    expect(out.grandTotal, 944); // 800 + 144 tax
    expect(out.refund, 236); // 200 + 36 tax
    expect(out.tax['taxAmount'], 144);
  });

  test('a return on a tax-included invoice works as before', () {
    final invoice = <String, dynamic>{
      'items': [
        {'Product Name': 'Soap', 'QTY': '10', 'TP': '118'},
      ],
      'total': 1180,
      ...computeTax([
        {'QTY': '10', 'TP': '118'},
      ], 1180, rate: 18, inclusive: true).fields,
    };
    final out = applyReturn(invoice, [const ReturnLine(0, 5)]);
    expect(out.grandTotal, 590);
    expect(out.refund, 590);
    expect(out.tax['taxAmount'], 90);
  });

  test('amount in words, Pakistani style', () {
    expect(rupeesInWords(8910), 'Rupees eight thousand nine hundred ten only');
    expect(rupeesInWords(143550), 'Rupees one lakh forty-three thousand five hundred fifty only');
    expect(rupeesInWords(25000000), 'Rupees two crore fifty lakh only');
    expect(rupeesInWords(0), 'Rupees zero only');
  });

  test("the month's sales tax lines carry the shop's NTN", () {
    final inv = {
      'invoiceNumber': '7',
      'customer': 'Test Store',
      'salesDateTs': Timestamp.fromDate(DateTime(2026, 11, 5)),
      'items': items,
      ...computeTax(items, 2000, rate: 18, inclusive: true).fields,
    };
    final lines = salesTaxLines([('a', inv), ('b', {'customer': 'x', 'grandTotal': 100})], {'test store': ('1234567-8', '')});
    expect(lines, hasLength(1));
    expect(lines.single.registered, isTrue);
    expect(lines.single.tax, 305);
  });
}
