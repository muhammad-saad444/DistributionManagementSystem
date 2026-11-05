// Printable payslips and final settlements.
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../account/account.dart';
import 'hr_data.dart';

final _money = NumberFormat('#,##0');
String _rs(num v) => 'Rs. ${_money.format(v.round())}';
final _day = DateFormat('dd MMM yyyy');

pw.Widget _header(String title, String subtitle, String company) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Center(child: pw.Text(company, style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold))),
        pw.SizedBox(height: 4),
        pw.Center(child: pw.Text(title, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold))),
        pw.Center(child: pw.Text(subtitle, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700))),
        pw.SizedBox(height: 14),
      ],
    );

pw.Widget _row(String label, String value, {bool bold = false}) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2.5),
      child: pw.Row(children: [
        pw.Expanded(child: pw.Text(label, style: pw.TextStyle(fontSize: 10, fontWeight: bold ? pw.FontWeight.bold : null))),
        pw.Text(value, style: pw.TextStyle(fontSize: 10, fontWeight: bold ? pw.FontWeight.bold : null)),
      ]),
    );

pw.Widget _box(String title, List<pw.Widget> rows) => pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey400), borderRadius: pw.BorderRadius.circular(4)),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text(title, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
        pw.Divider(color: PdfColors.grey400),
        ...rows,
      ]),
    );

/// One person's payslip for a month.
Future<Uint8List> payslipPdf(String month, PayLine l, {String? companyName}) =>
    payslipsPdf(month, [l], companyName: companyName);

/// Several payslips, one per page (the whole month for printing).
Future<Uint8List> payslipsPdf(String month, List<PayLine> lines, {String? companyName}) async {
  final doc = pw.Document();
  for (final l in lines) {
    doc.addPage(_payslipPage(month, l, companyName ?? Account.companyName));
  }
  return doc.save();
}

pw.Page _payslipPage(String month, PayLine l, String company) {
  final monthLabel = DateFormat('MMMM yyyy').format(DateTime.parse('$month-01'));
  return pw.Page(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(32),
    build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      _header('Payslip', monthLabel, company),
      _box('Employee', [
        _row('Name', l.name),
        if (l.code.isNotEmpty) _row('Code', l.code),
        _row('Designation', l.designation),
        _row('Working days', '${l.workingDays}'),
        _row('Days at work', hrPlainPdf(l.daysAtWork)),
        if (l.paidLeave > 0) _row('Paid leave', hrPlainPdf(l.paidLeave)),
        if (l.unpaidDays > 0) _row('Unpaid days', hrPlainPdf(l.unpaidDays)),
        if (l.lates > 0) _row('Late arrivals', hrPlainPdf(l.lates)),
      ]),
      pw.SizedBox(height: 10),
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Expanded(
          child: _box('Earnings', [
            _row(l.salaryType == 'daily' ? 'Wages' : 'Basic salary', _rs(l.basic)),
            if (l.allowances > 0) _row('Allowances', _rs(l.allowances)),
            if (l.absenceDeduction > 0) _row('Less: absences', '- ${_rs(l.absenceDeduction)}'),
            if (l.lateDeduction > 0) _row('Less: late arrivals', '- ${_rs(l.lateDeduction)}'),
            if (l.commission > 0) _row('Commission (sales ${_rs(l.sales)})', _rs(l.commission)),
            if (l.targetBonus > 0) _row('Target bonus', _rs(l.targetBonus)),
            if (l.bonus > 0) _row('Bonus / other', _rs(l.bonus)),
            pw.Divider(color: PdfColors.grey400),
            _row('Total earnings', _rs(l.totalEarnings), bold: true),
          ]),
        ),
        pw.SizedBox(width: 10),
        pw.Expanded(
          child: _box('Deductions', [
            if (l.advanceDeduction > 0) _row('Advance repayment', _rs(l.advanceDeduction)),
            if (l.eobiEmployee > 0) _row('EOBI', _rs(l.eobiEmployee)),
            if (l.tax > 0) _row('Income tax', _rs(l.tax)),
            if (l.otherDeduction > 0) _row('Other', _rs(l.otherDeduction)),
            if (l.totalDeductions == 0) _row('None', _rs(0)),
            pw.Divider(color: PdfColors.grey400),
            _row('Total deductions', _rs(l.totalDeductions), bold: true),
          ]),
        ),
      ]),
      pw.SizedBox(height: 14),
      pw.Container(
        padding: const pw.EdgeInsets.all(10),
        color: PdfColors.grey200,
        child: _row('NET PAY', _rs(l.net), bold: true),
      ),
      if (l.note.isNotEmpty) ...[pw.SizedBox(height: 8), pw.Text('Note: ${l.note}', style: const pw.TextStyle(fontSize: 9))],
      pw.Spacer(),
      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Text('Employee signature: ____________', style: const pw.TextStyle(fontSize: 9)),
        pw.Text('Authorised by: ____________', style: const pw.TextStyle(fontSize: 9)),
      ]),
    ]),
  );
}

String hrPlainPdf(num v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

/// Final settlement for someone leaving.
Future<Uint8List> settlementPdf(Employee e, String status, Settlement s) async {
  final doc = pw.Document();
  doc.addPage(pw.Page(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(32),
    build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      _header('Final settlement', status == 'terminated' ? 'Termination' : 'Resignation', Account.companyName),
      _box('Employee', [
        _row('Name', e.name),
        if (e.code.isNotEmpty) _row('Code', e.code),
        if (e.cnic.isNotEmpty) _row('CNIC', e.cnic),
        _row('Designation', e.designation),
        if (e.joinDate != null) _row('Joined', _day.format(e.joinDate!)),
        _row('Last working day', _day.format(s.lastDay)),
      ]),
      pw.SizedBox(height: 10),
      _box('Settlement', [
        _row('Salary for the last month', _rs(s.salaryDue)),
        if (s.leaveEncashment > 0) _row('Unused annual leave (${hrPlainPdf(s.leaveDays)} days)', _rs(s.leaveEncashment)),
        if (s.otherDues > 0) _row('Other dues', _rs(s.otherDues)),
        if (s.advancesOutstanding > 0) _row('Less: advances outstanding', '- ${_rs(s.advancesOutstanding)}'),
        if (s.otherDeductions > 0) _row('Less: other deductions', '- ${_rs(s.otherDeductions)}'),
        pw.Divider(color: PdfColors.grey400),
        _row(s.net >= 0 ? 'Payable to employee' : 'Recoverable from employee', _rs(s.net.abs()), bold: true),
      ]),
      if (s.note.isNotEmpty) ...[pw.SizedBox(height: 8), pw.Text('Note: ${s.note}', style: const pw.TextStyle(fontSize: 9))],
      pw.Spacer(),
      pw.Text('I have received the above amount in full and final settlement of all my dues.',
          style: const pw.TextStyle(fontSize: 9)),
      pw.SizedBox(height: 24),
      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Text('Employee signature: ____________', style: const pw.TextStyle(fontSize: 9)),
        pw.Text('Authorised by: ____________', style: const pw.TextStyle(fontSize: 9)),
      ]),
    ]),
  ));
  return doc.save();
}
