// Export to Excel: the workbook has the title, bold headers, numbers as numbers, and totals.
import 'package:an_agency/ui/excel_export.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('builds a sheet with title, headers, rows and totals', () {
    final bytes = buildXlsx(
      title: 'Receivables',
      subtitle: 'All shops',
      company: 'Demo',
      sheets: [
        ExportSheet(
          name: 'Shops',
          headers: ['Shop', 'Owed', 'Date'],
          rows: [
            ['Shop A', 1200, DateTime(2026, 11, 5)],
            ['Shop B', 99.555, null],
          ],
          totals: ['Total', 1299.555, null],
        ),
        const ExportSheet(name: 'By booker: test/1', headers: ['Booker'], rows: [['Ali']]),
      ],
    );
    final book = Excel.decodeBytes(bytes);
    expect(book.tables.keys, containsAll(['Shops', 'By booker  test 1']));
    final rows = book.tables['Shops']!.rows;
    String? text(int r, int c) => rows[r][c]?.value?.toString();
    expect(text(0, 0), 'Demo · Receivables');
    expect(text(1, 0), startsWith('All shops · Exported '));
    expect(text(3, 0), 'Shop');
    expect(rows[4][1]?.value, isA<IntCellValue>());
    expect(text(4, 2), '05-11-2026');
    expect(rows[5][1]?.value, isA<DoubleCellValue>());
    expect(text(5, 1), '99.56');
    expect(text(6, 0), 'Total');
  });

  test('file names are plain and dated', () {
    expect(exportFileName('Cash & bank book'), matches(RegExp(r'^cash-bank-book-\d{4}-\d{2}-\d{2}$')));
  });
}
