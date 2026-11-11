// The cash and bank book: where each payment lands, opening and closing balances, transfers.
import 'package:an_agency/accounts/cashbook_data.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

Timestamp _d(int m, int d) => Timestamp.fromDate(DateTime(2026, m, d, 12));

void main() {
  test('payment methods map to cash, bank or wallet', () {
    expect(accountForMethod('Cash'), MoneyAccount.cash);
    expect(accountForMethod(''), MoneyAccount.cash);
    expect(accountForMethod('Office recovery'), MoneyAccount.cash);
    expect(accountForMethod('Other'), MoneyAccount.cash);
    expect(accountForMethod('Bank transfer'), MoneyAccount.bank);
    expect(accountForMethod('Online'), MoneyAccount.bank);
    expect(accountForMethod('Cheque'), MoneyAccount.bank);
    expect(accountForMethod('JazzCash / EasyPaisa'), MoneyAccount.wallet);
  });

  final lines = buildCashLines(
    manual: [
      CashEntry(date: DateTime(2026, 10, 1), type: CashEntryType.opening, account: MoneyAccount.cash, amount: 10000),
      CashEntry(date: DateTime(2026, 10, 1), type: CashEntryType.opening, account: MoneyAccount.bank, amount: 50000),
      CashEntry(
          date: DateTime(2026, 11, 10),
          type: CashEntryType.transfer,
          account: MoneyAccount.cash,
          toAccount: MoneyAccount.bank,
          amount: 5000,
          note: 'Deposit'),
    ],
    khataEntries: [
      {'type': 'payment', 'amount': 3000, 'date': _d(10, 20), 'method': 'Cash', 'customer': 'Shop A'},
      {'type': 'payment', 'amount': 2000, 'date': _d(11, 5), 'method': 'Online', 'customer': 'Shop B'},
      {'type': 'udhaar', 'amount': 999, 'date': _d(11, 5), 'customer': 'Shop B'}, // not money
    ],
    officeRecoveries: [
      {'amountPaid': 1500, 'dateStr': '2026-11-03', 'customerName': 'Shop C'},
    ],
    expenses: [
      {'amount': 800, 'date': _d(11, 6), 'method': 'Cash', 'category': 'Fuel'},
    ],
    supplierPayments: [
      {'amount': 20000, 'date': _d(11, 8), 'method': 'Bank transfer', 'supplierName': 'Supplier X'},
    ],
  );

  test('opening balance carries everything before the period', () {
    final p = cashPeriod(lines, DateTime(2026, 11), DateTime(2026, 12));
    expect(p.opening[MoneyAccount.cash], 13000); // 10,000 opening + 3,000 October payment
    expect(p.opening[MoneyAccount.bank], 50000);
    expect(p.opening[MoneyAccount.wallet], 0);
  });

  test('money in, out and closing per account, with the transfer on both sides', () {
    final p = cashPeriod(lines, DateTime(2026, 11), DateTime(2026, 12));
    // Cash: +1,500 recovery, −800 fuel, −5,000 deposited
    expect(p.moneyIn[MoneyAccount.cash], 1500);
    expect(p.moneyOut[MoneyAccount.cash], 5800);
    expect(p.closing(MoneyAccount.cash), 13000 + 1500 - 5800);
    // Bank: +2,000 online payment, +5,000 deposit, −20,000 supplier
    expect(p.moneyIn[MoneyAccount.bank], 7000);
    expect(p.moneyOut[MoneyAccount.bank], 20000);
    expect(p.closing(MoneyAccount.bank), 37000);
    // A transfer moves money; it doesn't change the total.
    expect(p.totalClosing, p.totalOpening + 1500 + 2000 - 800 - 20000);
    expect(p.lines.where((l) => l.title.startsWith('Transfer')).map((l) => l.amount), [-5000, 5000]);
  });

  test('daily balance runs through the period', () {
    final p = cashPeriod(lines, DateTime(2026, 11), DateTime(2026, 12));
    final cash = p.dailyBalance(MoneyAccount.cash);
    expect(cash, hasLength(30));
    expect(cash.first, 13000); // 1 Nov: nothing yet
    expect(cash[2], 14500); // 3 Nov: recovery
    expect(cash.last, p.closing(MoneyAccount.cash));
  });
}
