// Sales tax on an invoice.
//
// The company sets a rate (e.g. 18% GST) and whether its prices already include it. A product may
// have its own rate (exempt = 0), which a new invoice line keeps as `GST`. When an invoice is made,
// the rate and mode are saved on it (taxRate, taxInclusive), so changing the settings later never
// changes old invoices; edits and returns use what the invoice was saved with.
//
//   Prices include tax: the bill stays the same; the tax inside it is shown
//                       (tax = amount × rate / (100 + rate)).
//   Prices exclude tax: tax is added on top of the bill after discount (tax = amount × rate / 100).
//
// The discount is spread over the lines by their value, so each rate's tax is on what was really
// charged. Tax is rounded to whole rupees.

double _n(dynamic v) => (num.tryParse('${v ?? 0}') ?? 0).toDouble();

/// A line's value as sold now: (quantity − returned) × trade price.
double lineValue(Map item) => (_n(item['QTY']) - _n(item['returnQty'])) * _n(item['TP']);

/// The rate for one line: its own `GST` if it has one, else the invoice's.
double lineRate(Map item, double invoiceRate) {
  final own = '${item['GST'] ?? ''}'.trim();
  return own.isEmpty ? invoiceRate : (double.tryParse(own) ?? invoiceRate);
}

/// What a product's tax setting puts on an invoice line: null = the company rate.
String? productTaxRate(Map<String, dynamic> product) {
  final r = '${product['taxRate'] ?? ''}'.trim();
  return r.isEmpty ? null : r;
}

class TaxBand {
  final double rate;
  double taxable = 0; // value of goods without tax
  double tax = 0;
  TaxBand(this.rate);
}

class InvoiceTax {
  final double rate; // the invoice's own rate
  final bool inclusive;
  final double net; // after discount, as the lines are priced
  final List<TaxBand> bands; // by rate, biggest first
  const InvoiceTax(this.rate, this.inclusive, this.net, this.bands);

  double get tax => bands.fold(0.0, (s, b) => s + b.tax);
  double get taxable => bands.fold(0.0, (s, b) => s + b.taxable);
  double get grandTotal => inclusive ? net : net + tax;

  /// Saved on the invoice.
  Map<String, dynamic> get fields => {
        'taxRate': rate,
        'taxInclusive': inclusive,
        'taxAmount': tax,
        'taxableValue': double.parse(taxable.toStringAsFixed(2)),
        'grandTotal': grandTotal,
      };
}

/// Tax on an invoice whose lines are [items] and whose total after discount is [net].
InvoiceTax computeTax(List items, double net, {required double rate, required bool inclusive}) {
  final lines = [for (final it in items) if (it is Map) it];
  final sum = lines.fold<double>(0, (s, it) => s + lineValue(it));
  final byRate = <double, double>{}; // rate → share of net
  for (final it in lines) {
    final v = lineValue(it);
    if (v == 0) continue;
    final r = lineRate(it, rate);
    byRate[r] = (byRate[r] ?? 0) + (sum == 0 ? 0 : v / sum * net);
  }
  if (byRate.isEmpty && net != 0) byRate[rate] = net;
  final bands = <TaxBand>[];
  for (final e in byRate.entries) {
    final b = TaxBand(e.key);
    final tax = (inclusive ? e.value * e.key / (100 + e.key) : e.value * e.key / 100).roundToDouble();
    b.tax = tax;
    b.taxable = inclusive ? e.value - tax : e.value;
    bands.add(b);
  }
  bands.sort((a, b) => b.taxable.compareTo(a.taxable));
  return InvoiceTax(rate, inclusive, net, bands);
}

/// The tax a saved invoice was made with, or null if it has none.
({double rate, bool inclusive})? taxOf(Map invoice) {
  final r = invoice['taxRate'];
  if (r == null || '$r'.trim().isEmpty) return null;
  return (rate: _n(r), inclusive: invoice['taxInclusive'] != false);
}

/// For a saved invoice: its tax worked out again from its lines (for printing), or null.
InvoiceTax? savedInvoiceTax(Map invoice) {
  final t = taxOf(invoice);
  if (t == null) return null;
  final grand = _n(invoice['grandTotal'] ?? invoice['total']);
  final net = t.inclusive ? grand : grand - _n(invoice['taxAmount']);
  return computeTax(invoice['items'] as List? ?? const [], net, rate: t.rate, inclusive: t.inclusive);
}

/// After an edit or return changed an invoice's lines or discount: its new tax fields (including
/// grandTotal) from [net], using the rate it was saved with. Empty if it has no tax.
Map<String, dynamic> retax(Map invoice, List items, double net) {
  final t = taxOf(invoice);
  if (t == null) return const {};
  return computeTax(items, net, rate: t.rate, inclusive: t.inclusive).fields;
}

/// An invoice's tax fields with sales tax switched [on] or off (an office edit can add tax to an
/// invoice made without it, or take it off). Off: the tax fields are cleared and the bill is [net].
Map<String, dynamic> taxFieldsSwitched(List items, double net, {required bool on, required double rate, required bool inclusive}) =>
    on
        ? computeTax(items, net, rate: rate, inclusive: inclusive).fields
        : {'taxRate': null, 'taxInclusive': null, 'taxAmount': null, 'taxableValue': null, 'grandTotal': net};

/// "Rupees eight thousand nine hundred ten only", for the printed invoice.
String rupeesInWords(double amount) {
  final whole = amount.round();
  if (whole == 0) return 'Rupees zero only';
  const ones = [
    '', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine', 'ten', 'eleven', 'twelve',
    'thirteen', 'fourteen', 'fifteen', 'sixteen', 'seventeen', 'eighteen', 'nineteen',
  ];
  const tens = ['', '', 'twenty', 'thirty', 'forty', 'fifty', 'sixty', 'seventy', 'eighty', 'ninety'];
  String upTo99(int n) => n < 20 ? ones[n] : '${tens[n ~/ 10]}${n % 10 == 0 ? '' : '-${ones[n % 10]}'}';
  String upTo999(int n) {
    final h = n ~/ 100, r = n % 100;
    return [if (h > 0) '${ones[h]} hundred', if (r > 0) upTo99(r)].join(' ');
  }

  // Pakistani grouping: crore, lakh, thousand, hundred.
  var n = whole.abs();
  final parts = <String>[];
  for (final (size, name) in const [(10000000, 'crore'), (100000, 'lakh'), (1000, 'thousand')]) {
    if (n >= size) {
      final q = n ~/ size;
      parts.add('${q >= 100 ? upTo999(q) : upTo99(q)} $name');
      n %= size;
    }
  }
  if (n > 0) parts.add(upTo999(n));
  return 'Rupees ${whole < 0 ? 'minus ' : ''}${parts.join(' ')} only';
}
