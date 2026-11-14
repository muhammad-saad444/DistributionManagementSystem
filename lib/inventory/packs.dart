// Cartons and pieces. Quantities are always kept in the product's own unit (pieces, packs...),
// which is what prices and stock count in. A product with "units per carton" can be booked as
// cartons + pieces, and quantities are shown that way too: 29 pieces at 12 a carton = "2 ctn + 5".
// An invoice line keeps the carton size it was sold with (`perCarton`), so prints and load sheets
// don't depend on the product's current setting.

double _n(dynamic v) => (num.tryParse('${v ?? 0}') ?? 0).toDouble();

/// Units per carton of a product or invoice line, or 0 when it isn't sold by the carton.
int perCartonOf(Map? m) {
  final v = _n(m?['perCarton'] ?? m?['unitsPerCarton']).floor();
  return v > 1 ? v : 0;
}

/// [units] as whole cartons and the pieces left over.
(int cartons, double pieces) splitCartons(double units, int perCarton) {
  if (perCarton <= 1 || units <= 0) return (0, units);
  final cartons = (units / perCarton).floor();
  final pieces = units - cartons * perCarton;
  return (cartons, double.parse(pieces.toStringAsFixed(3)));
}

/// Cartons + pieces back to units.
double unitsOf(double cartons, double pieces, int perCarton) => cartons * (perCarton > 1 ? perCarton : 1) + pieces;

String _q(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

/// "2 ctn + 5", "3 ctn", "7" (fewer than a carton, or no carton size).
String cartonLabel(double units, int perCarton) {
  final (c, p) = splitCartons(units, perCarton);
  if (c == 0) return _q(units);
  return p == 0 ? '$c ctn' : '$c ctn + ${_q(p)}';
}

/// Short form for a narrow box: "2c+5", "3c", or '' when it's under a carton.
String cartonShort(double units, int perCarton) {
  final (c, p) = splitCartons(units, perCarton);
  if (c == 0) return '';
  return p == 0 ? '${c}c' : '${c}c+${_q(p)}';
}
