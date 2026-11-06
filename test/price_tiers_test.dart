// B2B / B2R / B2C: which price a shop pays, and prices from cost.
import 'package:an_agency/inventory/price_tiers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('shop tier', () {
    test('saved tier wins', () => expect(customerTier({'priceTier': 'b2c', 'type': 'WholeSeller'}), 'b2c'));
    test('older shops: read from the type', () {
      expect(customerTier({'type': 'WholeSeller'}), 'b2b');
      expect(customerTier({'type': 'Wholesaler'}), 'b2b');
      expect(customerTier({'type': 'Consumer'}), 'b2c');
      expect(customerTier({'type': 'Shop'}), 'b2r');
      expect(customerTier({'type': 'Retailer'}), 'b2r');
      expect(customerTier({}), 'b2r');
      expect(customerTier(null), 'b2r');
    });
  });

  group('product price for a tier', () {
    final p = {'dbPrice': 100, 'b2bPrice': 92, 'retailPrice': 120};
    test('each tier', () {
      expect(tierPrice(p, 'b2b'), 92);
      expect(tierPrice(p, 'b2r'), 100);
      expect(tierPrice(p, 'b2c'), 120);
    });
    test('no B2B or B2C price: sells at TP', () {
      final old = {'dbPrice': '50'};
      expect(tierPrice(old, 'b2b'), 50);
      expect(tierPrice(old, 'b2c'), 50);
      expect(tierPrice({'dbPrice': 50, 'b2bPrice': 0}, 'b2b'), 50);
    });
    test('old misspelt field still read', () => expect(tierPrice({'dbPrie': 30}, 'b2r'), 30));
  });

  test('price from cost: 9 at 5% is 9.45', () => expect(priceFromCost(9, 5), 9.45));

  test('a purchase sets B2B and B2C from their own %, skips a tier with none', () {
    expect(otherTierPricesFromCost({'b2bMarkupPct': 2, 'b2cMarkupPct': 20}, 100), {'b2bPrice': 102, 'retailPrice': 120});
    expect(otherTierPricesFromCost({'b2bMarkupPct': 2, 'b2cMarkupPct': null}, 100), {'b2bPrice': 102});
    expect(otherTierPricesFromCost({'b2bMarkupPct': 2}, 0), isEmpty);
  });
}
