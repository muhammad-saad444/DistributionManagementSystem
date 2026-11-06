// Three selling prices per product, one per kind of customer:
//   B2B  business to business: wholesalers and other distributors (lowest)
//   B2R  business to retailer: shops; this is the TP every product already had (dbPrice)
//   B2C  business to consumer: walk-in buyers (retail price / MRP, saved as retailPrice)
// A shop's type picks which one Book Order charges. A product with no B2B or B2C price
// sells at its B2R TP, so older products keep working unchanged.

const priceTiers = ['b2b', 'b2r', 'b2c'];

String tierShort(String tier) => switch (tier) { 'b2b' => 'B2B', 'b2c' => 'B2C', _ => 'B2R' };

String tierLabel(String tier) => switch (tier) {
      'b2b' => 'B2B · Wholesaler',
      'b2c' => 'B2C · Consumer',
      _ => 'B2R · Retailer',
    };

/// The shop-type choices on Add Shop, and the price tier each one pays.
const shopTypes = {'Wholesaler': 'b2b', 'Retailer': 'b2r', 'Shop': 'b2r', 'Consumer': 'b2c'};

/// Product fields holding each tier's price and its profit %.
String tierPriceField(String tier) => switch (tier) { 'b2b' => 'b2bPrice', 'b2c' => 'retailPrice', _ => 'dbPrice' };
String tierMarkupField(String tier) => switch (tier) { 'b2b' => 'b2bMarkupPct', 'b2c' => 'b2cMarkupPct', _ => 'markupPct' };

num _n(dynamic v) => v is num ? v : num.tryParse((v ?? '').toString().trim()) ?? 0;

/// The tier a customer document pays: its saved priceTier, else read from its type
/// (WholeSeller and Wholesaler pay B2B, Consumer pays B2C, everyone else B2R).
String customerTier(Map<String, dynamic>? customer) {
  if (customer == null) return 'b2r';
  final t = (customer['priceTier'] ?? '').toString();
  if (priceTiers.contains(t)) return t;
  final type = (customer['type'] ?? '').toString().trim().toLowerCase();
  if (type.startsWith('whole')) return 'b2b';
  if (type == 'consumer') return 'b2c';
  return 'b2r';
}

/// What a product sells for to a tier. B2B and B2C fall back to the B2R TP when not set.
num tierPrice(Map<String, dynamic>? product, String tier) {
  if (product == null) return 0;
  final tp = _n(product['dbPrice'] ?? product['dbPrie']);
  if (tier == 'b2r') return tp;
  final own = _n(product[tierPriceField(tier)]);
  return own > 0 ? own : tp;
}

/// Price from cost plus a profit %, to the paisa: cost 9 at 5% is 9.45.
num priceFromCost(num cost, num pct) => (cost * (100 + pct)).round() / 100;

/// For a profit-% product: the B2B and B2C prices a new cost gives, from each tier's saved %.
/// A tier with no % saved is left alone (it keeps its typed price or falls back to TP).
Map<String, num> otherTierPricesFromCost(Map<String, dynamic> product, num cost) {
  if (cost <= 0) return const {};
  final out = <String, num>{};
  for (final tier in const ['b2b', 'b2c']) {
    final pct = product[tierMarkupField(tier)];
    if (pct == null || pct.toString().trim().isEmpty) continue;
    out[tierPriceField(tier)] = priceFromCost(cost, _n(pct));
  }
  return out;
}
