// Targets: progress, pace against the month, and what was achieved.
import 'package:an_agency/targets/targets_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('how much of the month has gone, and days left', () {
    final nov = DateTime(2026, 11);
    expect(monthShare(nov, DateTime(2026, 11, 15)), closeTo(0.5, 0.001)); // 15 of 30
    expect(monthShare(nov, DateTime(2026, 11, 30)), 1);
    expect(monthShare(nov, DateTime(2026, 12, 3)), 1);
    expect(monthShare(nov, DateTime(2026, 10, 30)), 0);
    expect(daysLeft(nov, DateTime(2026, 11, 15)), 16); // 15th to 30th
    expect(daysLeft(nov, DateTime(2026, 11, 30)), 1);
    expect(daysLeft(nov, DateTime(2026, 12, 1)), 0);
    expect(daysLeft(nov, DateTime(2026, 10, 20)), 30);
  });

  test('pace: ahead, on track, behind, done', () {
    expect(const TargetProgress(1000, 700, 0.5).pace, Pace.ahead); // 70% at half-month
    expect(const TargetProgress(1000, 520, 0.5).pace, Pace.onTrack);
    expect(const TargetProgress(1000, 300, 0.5).pace, Pace.behind);
    expect(const TargetProgress(1000, 1000, 0.2).pace, Pace.done);
    expect(const TargetProgress(0, 500, 0.5).pace, Pace.none);
    const p = TargetProgress(1000, 400, 0.5);
    expect(p.pct, 40);
    expect(p.left, 600);
    expect(p.perDayNeeded(15), 40);
  });

  test('achievement from invoices, khata payments and office recoveries', () {
    final (sales, count, rec) = achievedFrom(
      invoices: [
        {'userId': 'a', 'grandTotal': 1000},
        {'userId': 'a', 'total': 500},
        {'userId': 'b', 'grandTotal': 200},
      ],
      khataEntries: [
        {'userId': 'a', 'type': 'payment', 'amount': 300},
        {'userId': 'a', 'type': 'udhaar', 'amount': 999}, // not a recovery
      ],
      officeRecoveries: [
        {'userId': 'b', 'amountPaid': 150},
      ],
    );
    expect(sales, {'a': 1500, 'b': 200});
    expect(count, {'a': 2, 'b': 1});
    expect(rec, {'a': 300, 'b': 150});
    expect(targetDocId(DateTime(2026, 11, 20), 'a'), '2026-11__a');
  });
}
