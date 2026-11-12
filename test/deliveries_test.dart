// Deliveries: the load sheet for a trip and the settlement totals.
import 'package:an_agency/deliveries/deliveries_data.dart';
import 'package:flutter_test/flutter_test.dart';

DeliveryInvoice _inv(String id, double amount, List<Map<String, dynamic>> items) => DeliveryInvoice(
    id: id, number: id, shop: 'Shop $id', area: 'A', bookerId: 'b', bookerEmail: '', amount: amount, items: items);

void main() {
  final a = _inv('1', 1000, [
    {'Product Name': 'Soap', 'Size': 'Piece', 'QTY': '10', 'BNS': '1', 'TP': '50'},
    {'Product Name': 'Oil', 'Size': 'Bottle', 'QTY': '2', 'TP': '250', 'returnQty': '1'},
  ]);
  final b = _inv('2', 500, [
    {'Product Name': 'soap', 'Size': 'Piece', 'QTY': '6', 'TP': '50'},
  ]);

  test('load sheet adds up products across invoices, free goods included, returns left out', () {
    final lines = loadSheet([a, b]);
    expect(lines.map((l) => l.product), ['Soap', 'Oil']);
    final soap = lines.first;
    expect(soap.qty, 16);
    expect(soap.free, 1);
    expect(soap.units, 17);
    expect(soap.value, 800);
    expect(lines.last.qty, 1); // 2 sold, 1 already returned
  });

  test('settlement totals', () {
    final s = TripSummary.of([
      InvoiceSettlement(a, DeliveryOutcome.delivered, 1000),
      InvoiceSettlement(b, DeliveryOutcome.returned, 0),
    ]);
    expect(s.delivered, 1);
    expect(s.returned, 1);
    expect(s.partial, 0);
    expect(s.cash, 1000);
    expect(s.value, 1500);
  });

  test('reads an invoice and a trip', () {
    final inv = DeliveryInvoice.fromMap('x', {'invoiceNumber': 7, 'customer': 'Shop', 'grandTotal': '900', 'dispatchId': 't1', 'deliveryStatus': 'out'});
    expect(inv.dispatched, isTrue);
    expect(inv.amount, 900);
    expect(DeliveryInvoice.fromMap('y', const {}).dispatched, isFalse);
    expect(Trip.fromMap('t', {'number': '2', 'status': 'out', 'invoiceIds': ['x']}).statusLabel, 'Out for delivery');
  });
}
