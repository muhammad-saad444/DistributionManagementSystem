// Booker cash handover: what each booker collected in cash, handed over, and still holds.
import 'package:an_agency/accounts/cashbook_data.dart';
import 'package:an_agency/accounts/handover_data.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _pay(String uid, double amount, int day, {String method = 'Cash'}) => {
      'type': 'payment',
      'userId': uid,
      'amount': amount,
      'method': method,
      'date': Timestamp.fromDate(DateTime(2026, 11, day)),
    };

void main() {
  test('only cash a booker collected in the field counts', () {
    expect(isBookerCash(_pay('a', 1, 1)), isTrue);
    expect(isBookerCash(_pay('a', 1, 1, method: '')), isTrue); // older entries had no method
    expect(isBookerCash(_pay('a', 1, 1, method: 'Online')), isFalse);
    expect(isBookerCash(_pay('a', 1, 1, method: 'Cheque')), isFalse);
    expect(isBookerCash(_pay('a', 1, 1, method: 'Office recovery')), isFalse);
    expect(isBookerCash({..._pay('a', 1, 1), 'type': 'udhaar'}), isFalse);
  });

  test('holding = collected − handed over; handovers clear the oldest cash first', () {
    final rows = bookerCash(
      [
        _pay('ali', 1000, 2),
        _pay('ali', 2000, 5),
        _pay('ali', 500, 9),
        _pay('ali', 9999, 9, method: 'Online'), // went to the bank
        _pay('babar', 300, 8),
      ],
      [
        Handover(bookerUid: 'ali', bookerName: 'Ali', amount: 1500, date: DateTime(2026, 11, 6)),
      ],
      {'ali': 'Ali', 'babar': 'Babar'},
      start: DateTime(2026, 11, 5),
      end: DateTime(2026, 11, 10),
    );
    final ali = rows.firstWhere((r) => r.uid == 'ali');
    expect(ali.collected, 3500);
    expect(ali.handedOver, 1500);
    expect(ali.holding, 2000);
    expect(ali.collectedInPeriod, 2500); // 5th and 9th
    expect(ali.handedInPeriod, 1500);
    expect(ali.lastHandover, DateTime(2026, 11, 6));
    // 1,500 cleared the 1,000 of the 2nd; the 2,000 of the 5th is only partly covered → oldest unhanded
    expect(ali.oldestUnhanded, DateTime(2026, 11, 5));
    expect(rows.first.uid, 'ali'); // most held first
    expect(rows.last.holding, 300);
  });

  test('fully handed over: nothing outstanding', () {
    final rows = bookerCash([_pay('ali', 1000, 2)], [Handover(bookerUid: 'ali', bookerName: 'Ali', amount: 1000, date: DateTime(2026, 11, 3))], const {});
    expect(rows.single.holding, 0);
    expect(rows.single.oldestUnhanded, isNull);
  });

  test('a handover lands in the cash book in the chosen account', () {
    final l = Handover(bookerUid: 'ali', bookerName: 'Ali', amount: 800, date: DateTime(2026, 11, 3), into: MoneyAccount.bank).cashLine;
    expect(l.account, MoneyAccount.bank);
    expect(l.amount, 800);
    expect(l.source, CashSource.handover);
  });
}
