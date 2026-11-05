// Payroll arithmetic: no Firestore, just the calculations.
import 'package:an_agency/hr/hr_data.dart';
import 'package:flutter_test/flutter_test.dart';

Attendance _a(String date, String status, {bool paid = true}) =>
    Attendance(employeeId: 'e1', date: date, status: status, paidLeave: paid);

void main() {
  const s = HrSettings(); // Sunday off, late after 09:30, 3 lates = 1 day, FY 2026-27 slabs

  group('income tax (FY 2026-27 salaried slabs)', () {
    test('tax-free up to Rs 600,000', () => expect(s.annualTax(600000), 0));
    test('1% band', () => expect(s.annualTax(1000000), 4000));
    test('11% band', () => expect(s.annualTax(1500000), 6000 + 33000));
    test('20% band', () => expect(s.annualTax(2700000), 116000 + 100000));
    test('top band', () => expect(s.annualTax(8000000), 1424000 + 350000));
  });

  test('working days skip the weekly off', () {
    // November 2026: 30 days, Sundays on 1, 8, 15, 22, 29.
    expect(s.workingDays('2026-11').length, 25);
  });

  test('late rule', () {
    expect(s.isLate(DateTime(2026, 11, 5, 9, 30)), isFalse);
    expect(s.isLate(DateTime(2026, 11, 5, 9, 31)), isTrue);
  });

  test('a booker\'s month: absences, lates, commission, target bonus, advance, EOBI', () {
    final e = Employee(
      id: 'e1',
      name: 'Ali',
      basic: 30000,
      allowances: const [Allowance('Fuel', 5000)],
      joinDate: DateTime(2025, 1, 1),
      commissionPct: 2,
      monthlyTarget: 400000,
      targetBonus: 5000,
      eobi: true,
      incomeTax: true,
      userUid: 'u1',
    );
    final days = {
      for (final a in [
        _a('2026-11-02', 'absent'),
        _a('2026-11-03', 'absent'),
        _a('2026-11-04', 'late'),
        _a('2026-11-05', 'late'),
        _a('2026-11-06', 'late'),
        _a('2026-11-07', 'late'),
      ])
        a.date: a,
    };
    final sales = BookerMonth()..sales = 500000;
    final advance = Advance(
        id: 'adv1', employeeId: 'e1', employeeName: 'Ali', amount: 10000, installment: 3000, date: DateTime(2026, 10, 20));
    final l = calculatePayLine(e: e, month: '2026-11', settings: s, days: days, sales: sales, advances: [advance]);

    expect(l.gross, 35000);
    expect(l.absenceDeduction, 2800); // 35,000 / 25 days × 2
    expect(l.lateDeduction, 1400); // 4 lates → 1 day
    expect(l.commission, 10000); // 2% of 500,000
    expect(l.targetBonus, 5000);
    expect(l.advanceDeduction, 3000);
    expect(l.advanceSplit, {'adv1': 3000});
    expect(l.eobiEmployee, 400); // 1% of 40,000
    expect(l.eobiEmployer, 2000);
    expect(l.tax, 0); // 45,800 × 12 = 549,600: under the tax-free limit
    expect(l.net, 35000 - 2800 - 1400 + 10000 + 5000 - 3000 - 400);
  });

  test('joined mid-month: only days employed are paid', () {
    final e = Employee(id: 'e2', name: 'New', basic: 25000, joinDate: DateTime(2026, 11, 16));
    final l = calculatePayLine(e: e, month: '2026-11', settings: s, days: const {}, sales: null, advances: const []);
    // 16–30 Nov: Sundays 22 and 29 off → 13 working days of 25.
    expect(l.workingDays, 13);
    expect(l.net, 25000 - (25000 / 25 * 12).round());
  });

  test('daily wager is paid for working days, minus absences', () {
    final e = Employee(id: 'e3', name: 'Daily', salaryType: 'daily', basic: 1500, joinDate: DateTime(2025, 1, 1));
    final l = calculatePayLine(
        e: e, month: '2026-11', settings: s, days: {'2026-11-02': _a('2026-11-02', 'absent')}, sales: null, advances: const []);
    expect(l.gross, 1500 * 25);
    expect(l.net, 1500 * 24);
  });

  test('unpaid leave costs a day, paid leave does not', () {
    final e = Employee(id: 'e1', name: 'X', basic: 25000, joinDate: DateTime(2025, 1, 1));
    final l = calculatePayLine(e: e, month: '2026-11', settings: s, days: {
      '2026-11-02': _a('2026-11-02', 'leave'),
      '2026-11-03': _a('2026-11-03', 'leave', paid: false),
    }, sales: null, advances: const []);
    expect(l.paidLeave, 1);
    expect(l.net, 25000 - 1000);
  });

  test('income tax is withheld monthly from the yearly slab', () {
    final e = Employee(id: 'e4', name: 'Manager', basic: 150000, incomeTax: true, joinDate: DateTime(2025, 1, 1));
    final l = calculatePayLine(e: e, month: '2026-11', settings: s, days: const {}, sales: null, advances: const []);
    // 1,800,000 a year → 6,000 + 11% × 600,000 = 72,000 → 6,000 a month.
    expect(l.tax, 6000);
  });

  test('advance installment never exceeds what is left', () {
    final e = Employee(id: 'e1', name: 'X', basic: 25000, joinDate: DateTime(2025, 1, 1));
    final adv = Advance(
        id: 'a', employeeId: 'e1', employeeName: 'X', amount: 5000, installment: 3000, repaid: 3000, date: DateTime(2026, 9, 1));
    final l = calculatePayLine(e: e, month: '2026-11', settings: s, days: const {}, sales: null, advances: [adv]);
    expect(l.advanceDeduction, 2000);
  });

  test('leave days skip weekly offs', () {
    expect(leaveDays(DateTime(2026, 11, 6), DateTime(2026, 11, 9), s).length, 3); // Fri, Sat, (Sun off), Mon
  });
}
