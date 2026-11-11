import 'dart:typed_data';
import 'package:an_agency/ui/app_theme.dart';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:printing/printing.dart';

// Same navy / amber tokens as the rest of the app.
const _navy = AppColors.navy;
const _navyDark = AppColors.navyDark;
const _amber = AppColors.amber;
const _border = AppColors.border;

/// Shows a PDF in a bottom sheet so the user can check it before printing.
///
/// [buildPdf] produces the document bytes; build them before calling this if the
/// screen's data may change while the preview is open. [fileName] is used when
/// the user prints or shares. Completes when the preview is closed.
Future<void> showPrintPreview(
  BuildContext context, {
  required String title,
  required Future<Uint8List> Function() buildPdf,
  String fileName = 'document.pdf',
}) {
  final bytes = buildPdf(); // build once; the preview and the Print button share it
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
    builder: (sheetContext) => DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.6,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, __) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Container(
              width: 40,
              height: 5,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(color: _border, borderRadius: BorderRadius.circular(10)),
            ),
            Text(title, style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w700, color: _navy)),
            const Divider(color: _border, height: 24),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: PdfPreview(
                  build: (_) => bytes,
                  pdfFileName: fileName,
                  allowPrinting: false, // printing is the explicit button below
                  allowSharing: true,
                  canChangePageFormat: false,
                  canChangeOrientation: false,
                  canDebug: false,
                  loadingWidget: const Center(child: CircularProgressIndicator(color: _navy)),
                ),
              ),
            ),
            const Divider(color: _border, height: 20),
            SafeArea(
              top: false,
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        side: const BorderSide(color: _navy),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () => Navigator.pop(sheetContext),
                      child: Text('Close', style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: _navy)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _amber,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.print_outlined, color: _navyDark, size: 20),
                      label: Text('Print', style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: _navyDark)),
                      onPressed: () async {
                        final data = await bytes;
                        await Printing.layoutPdf(onLayout: (_) async => data, name: fileName);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
