// "Export to Excel" for any page: builds a real .xlsx (opens straight in Excel, numbers stay
// numbers, and Excel can save it as CSV) and saves it: a download on the web, the Downloads
// folder on Windows and Android.
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../account/account.dart';

/// One tab of the workbook.
class ExportSheet {
  final String name;
  final List<String> headers;
  final List<List<Object?>> rows; // String, num, DateTime or null per cell
  final List<Object?>? totals; // a bold last row, e.g. ['Total', null, 1200]

  const ExportSheet({required this.name, required this.headers, required this.rows, this.totals});
}

final _day = DateFormat('dd-MM-yyyy');

CellValue? _cell(Object? v) {
  if (v == null) return null;
  if (v is int) return IntCellValue(v);
  if (v is num) {
    if (v == v.roundToDouble() && v.abs() < 1e15) return IntCellValue(v.toInt());
    return DoubleCellValue(double.parse(v.toStringAsFixed(2)));
  }
  if (v is DateTime) return TextCellValue(_day.format(v));
  return TextCellValue(v.toString());
}

/// Excel sheet names: at most 31 characters, none of : \ / ? * [ ].
String _sheetName(String s, Set<String> used) {
  var n = s.replaceAll(RegExp(r'[:\\/?*\[\]]'), ' ').trim();
  if (n.isEmpty) n = 'Sheet';
  if (n.length > 31) n = n.substring(0, 31);
  var unique = n;
  var i = 2;
  while (used.contains(unique)) {
    final suffix = ' ($i)';
    unique = (n.length + suffix.length > 31 ? n.substring(0, 31 - suffix.length) : n) + suffix;
    i++;
  }
  used.add(unique);
  return unique;
}

/// The workbook as bytes. Each sheet starts with the company and [title] (and [subtitle]), then a
/// bold header row, the rows, and the totals row if given.
Uint8List buildXlsx({required String title, String subtitle = '', required List<ExportSheet> sheets, String? company}) {
  final excel = Excel.createExcel();
  final defaultName = excel.getDefaultSheet() ?? 'Sheet1';
  final used = <String>{};
  final bold = CellStyle(bold: true);
  final heading = CellStyle(bold: true, fontSize: 13);

  for (var s = 0; s < sheets.length; s++) {
    final spec = sheets[s];
    final name = _sheetName(spec.name, used);
    if (s == 0) {
      excel.rename(defaultName, name);
    }
    final sheet = excel[name];
    var r = 0;
    void styleRow(int row, int cols, CellStyle style) {
      for (var c = 0; c < cols; c++) {
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: row)).cellStyle = style;
      }
    }

    sheet.appendRow([TextCellValue('${company ?? Account.companyName} · $title')]);
    styleRow(r++, 1, heading);
    final note = [subtitle, 'Exported ${_day.format(DateTime.now())}'].where((x) => x.isNotEmpty).join(' · ');
    sheet.appendRow([TextCellValue(note)]);
    r++;
    sheet.appendRow([TextCellValue('')]); // a blank line (an empty row would be skipped)
    r++;
    sheet.appendRow([for (final h in spec.headers) TextCellValue(h)]);
    styleRow(r++, spec.headers.length, bold);
    for (final row in spec.rows) {
      sheet.appendRow([for (final v in row) _cell(v)]);
      r++;
    }
    if (spec.totals != null) {
      sheet.appendRow([for (final v in spec.totals!) _cell(v)]);
      styleRow(r++, spec.totals!.length, bold);
    }

    // Wide enough for the longest value in each column (within reason).
    for (var c = 0; c < spec.headers.length; c++) {
      var longest = spec.headers[c].length;
      for (final row in spec.rows) {
        if (c < row.length && row[c] != null) {
          final v = row[c];
          final len = v is DateTime ? 10 : v.toString().length;
          if (len > longest) longest = len;
        }
      }
      sheet.setColumnWidth(c, (longest + 3).clamp(8, 48).toDouble());
    }
  }
  excel.setDefaultSheet(_sheetName(sheets.first.name, {}));
  return Uint8List.fromList(excel.encode()!);
}

/// A file name that is safe everywhere: "receivables-2026-11-12".
String exportFileName(String base) =>
    '${base.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '')}-${DateFormat('yyyy-MM-dd').format(DateTime.now())}';

/// Builds the workbook and saves it, then says where it went.
Future<void> exportToExcel(
  BuildContext context, {
  required String fileName,
  required String title,
  String subtitle = '',
  required List<ExportSheet> sheets,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final bytes = buildXlsx(title: title, subtitle: subtitle, sheets: sheets);
    final where = await FileSaver.instance.saveFile(
      name: fileName,
      bytes: bytes,
      fileExtension: 'xlsx',
      mimeType: MimeType.microsoftExcel,
    );
    messenger.showSnackBar(SnackBar(
      content: Text(kIsWeb || where.isEmpty ? 'Downloaded $fileName.xlsx' : 'Saved to $where'),
    ));
  } catch (e) {
    debugPrint('Export failed: $e');
    messenger.showSnackBar(SnackBar(content: Text("Couldn't export: $e")));
  }
}

/// The toolbar button pages use.
class ExcelButton extends StatelessWidget {
  final VoidCallback? onPressed;
  const ExcelButton({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) => TextButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.grid_on_outlined, size: 18),
        label: const Text('Excel'),
      );
}
