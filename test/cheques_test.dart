// Cheques: when they can be deposited, and the figures at the top of the page.
import 'package:an_agency/cheques/cheques_data.dart';
import 'package:flutter_test/flutter_test.dart';

Cheque _c(String id, double amount, DateTime date, ChequeStatus status, {DateTime? bounced}) => Cheque(
    id: id, customer: 'Shop $id', userId: 'b', bank: 'HBL', number: id, amount: amount, chequeDate: date,
    receivedOn: DateTime(2026, 11, 1), status: status, bouncedOn: bounced);

void main() {
  final today = DateTime(2026, 11, 13, 15);

  test('a cheque can be deposited from the date written on it', () {
    final later = _c('1', 100, DateTime(2026, 11, 16), ChequeStatus.inHand);
    expect(later.daysToDate(today), 3);
    expect(later.dueToDeposit(today), isFalse);
    expect(_c('2', 100, DateTime(2026, 11, 13), ChequeStatus.inHand).dueToDeposit(today), isTrue);
    expect(_c('3', 100, DateTime(2026, 11, 2), ChequeStatus.deposited).dueToDeposit(today), isFalse); // already in the bank
  });

  test('summary: in hand, deposit now, in the bank, bounced this month', () {
    final s = ChequeSummary.of([
      _c('1', 1000, DateTime(2026, 11, 20), ChequeStatus.inHand),
      _c('2', 500, DateTime(2026, 11, 10), ChequeStatus.inHand),
      _c('3', 700, DateTime(2026, 11, 5), ChequeStatus.deposited),
      _c('4', 300, DateTime(2026, 11, 1), ChequeStatus.bounced, bounced: DateTime(2026, 11, 8)),
      _c('5', 900, DateTime(2026, 10, 1), ChequeStatus.bounced, bounced: DateTime(2026, 10, 9)),
      _c('6', 400, DateTime(2026, 11, 1), ChequeStatus.cleared),
    ], today);
    expect((s.inHand, s.inHandAmount), (2, 1500));
    expect((s.due, s.dueAmount), (1, 500));
    expect((s.deposited, s.depositedAmount), (1, 700));
    expect((s.bounced, s.bouncedAmount), (1, 300));
  });

  test('only in hand and deposited cheques are still open', () {
    expect(ChequeStatus.values.where((s) => s.open), [ChequeStatus.inHand, ChequeStatus.deposited]);
  });
}
