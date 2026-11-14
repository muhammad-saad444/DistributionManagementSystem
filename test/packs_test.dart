// Cartons + pieces: quantities stay in the product's unit and are shown as cartons and pieces.
import 'package:an_agency/deliveries/deliveries_data.dart';
import 'package:an_agency/inventory/packs.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('units split into cartons and pieces', () {
    expect(splitCartons(29, 12), (2, 5.0));
    expect(splitCartons(24, 12), (2, 0.0));
    expect(splitCartons(7, 12), (0, 7.0));
    expect(splitCartons(29, 0), (0, 29.0)); // not sold by the carton
    expect(unitsOf(2, 5, 12), 29);
    expect(unitsOf(3, 0, 0), 3); // no carton size: a "carton" is one unit
  });

  test('labels', () {
    expect(cartonLabel(29, 12), '2 ctn + 5');
    expect(cartonLabel(36, 12), '3 ctn');
    expect(cartonLabel(7, 12), '7');
    expect(cartonLabel(7.5, 0), '7.5');
    expect(cartonShort(29, 12), '2c+5');
    expect(cartonShort(5, 12), '');
  });

  test('carton size from a product or an invoice line', () {
    expect(perCartonOf({'unitsPerCarton': 24}), 24);
    expect(perCartonOf({'perCarton': '12'}), 12);
    expect(perCartonOf({'unitsPerCarton': 1}), 0); // one in a carton is just a unit
    expect(perCartonOf(null), 0);
  });

  test('the load sheet shows each product in cartons', () {
    final lines = loadSheet([
      DeliveryInvoice(id: '1', number: '1', shop: 'A', area: '', bookerId: '', bookerEmail: '', amount: 0, items: [
        {'Product Name': 'Soap', 'QTY': '20', 'TP': '10', 'perCarton': '12'},
      ]),
      DeliveryInvoice(id: '2', number: '2', shop: 'B', area: '', bookerId: '', bookerEmail: '', amount: 0, items: [
        {'Product Name': 'Soap', 'QTY': '9', 'BNS': '1', 'TP': '10', 'perCarton': '12'},
      ]),
    ]);
    expect(lines.single.units, 30);
    expect(cartonLabel(lines.single.units, lines.single.perCarton), '2 ctn + 6');
  });
}
