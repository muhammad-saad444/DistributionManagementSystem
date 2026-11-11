// The app's one design system: colours, type and how every standard widget looks.
// Screens get these looks for free through the MaterialApp theme; use AppColors for anything custom.
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Every colour in the app. Screens use these names, so the whole app's look changes here.
/// A classic, quiet scheme: deep navy, a muted brass accent used sparingly, soft greys, and calm
/// status colours.
class AppColors {
  // Brand
  static const navy = Color(0xFF1F3A5F); // main colour: buttons, links, selected things
  static const navyDark = Color(0xFF15263F); // sidebar, dashboard header
  static const navyMid = Color(0xFF2E5584); // lighter navy for gradients and charts
  static const brandSoft = Color(0xFFEDF2F8); // light navy wash for selected rows and chips
  static const amber = Color(0xFFB7862C); // muted brass accent: active marker, main floating button
  static const amberBg = Color(0xFFF8F1E3);
  static const amberDark = Color(0xFF8A6418); // brass text on light backgrounds

  // Surfaces and text
  static const bg = Color(0xFFF4F5F7);
  static const surface = Colors.white;
  static const border = Color(0xFFE2E5EA);
  static const text = Color(0xFF1F2933);
  static const muted = Color(0xFF6B7280);

  // Meaning
  static const green = Color(0xFF2F7D4F);
  static const greenBg = Color(0xFFEAF4EE);
  static const red = Color(0xFFB42318);
  static const redBg = Color(0xFFFCECEA);
  static const blue = Color(0xFF2B5C9E);
  static const blueBg = Color(0xFFECF2FA);
}

class AppRadius {
  static const field = 8.0;
  static const card = 10.0;
  static const sheet = 14.0;
}

class AppTheme {
  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.navy,
      brightness: Brightness.light,
    ).copyWith(
      primary: AppColors.navy,
      onPrimary: Colors.white,
      primaryContainer: AppColors.brandSoft,
      onPrimaryContainer: AppColors.navyDark,
      secondary: AppColors.amber,
      onSecondary: AppColors.navyDark,
      secondaryContainer: AppColors.amberBg,
      onSecondaryContainer: const Color(0xFF6B4A0E),
      tertiary: AppColors.green,
      error: AppColors.red,
      surface: AppColors.surface,
      onSurface: AppColors.text,
      onSurfaceVariant: AppColors.muted,
      outline: const Color(0xFFCBD2DE),
      outlineVariant: AppColors.border,
      surfaceTint: Colors.transparent,
    );

    final base = ThemeData(useMaterial3: true, colorScheme: scheme, brightness: Brightness.light);
    final text = GoogleFonts.interTextTheme(base.textTheme).apply(
      bodyColor: AppColors.text,
      displayColor: AppColors.text,
    );

    OutlineInputBorder line(Color c, [double w = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.field),
          borderSide: BorderSide(color: c, width: w),
        );
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.field));
    const buttonPad = EdgeInsets.symmetric(horizontal: 18, vertical: 14);
    final buttonText = GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600);

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.bg,
      textTheme: text,
      primaryTextTheme: GoogleFonts.interTextTheme(base.primaryTextTheme),
      dividerColor: AppColors.border,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,

      // Page headers are white with a hairline, like the rest of the page; the sidebar carries the colour.
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.text,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        toolbarHeight: 60,
        shape: const Border(bottom: BorderSide(color: AppColors.border)),
        iconTheme: const IconThemeData(color: AppColors.text, size: 22),
        actionsIconTheme: const IconThemeData(color: AppColors.muted, size: 22),
        titleTextStyle: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.text, letterSpacing: -0.2),
      ),

      cardTheme: CardThemeData(
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: const BorderSide(color: AppColors.border),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        labelStyle: GoogleFonts.inter(fontSize: 13, color: AppColors.muted),
        floatingLabelStyle: GoogleFonts.inter(fontSize: 13, color: AppColors.navy, fontWeight: FontWeight.w500),
        hintStyle: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF9AA3B2)),
        helperStyle: GoogleFonts.inter(fontSize: 11.5, color: AppColors.muted),
        errorStyle: GoogleFonts.inter(fontSize: 11.5, color: AppColors.red),
        prefixIconColor: AppColors.muted,
        suffixIconColor: AppColors.muted,
        border: line(AppColors.border),
        enabledBorder: line(AppColors.border),
        focusedBorder: line(AppColors.navy, 1.6),
        errorBorder: line(AppColors.red),
        focusedErrorBorder: line(AppColors.red, 1.6),
        disabledBorder: line(AppColors.border.withValues(alpha: 0.6)),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.navy,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.border,
          disabledForegroundColor: AppColors.muted,
          elevation: 0,
          shadowColor: Colors.transparent,
          padding: buttonPad,
          shape: shape,
          textStyle: buttonText,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.navy,
          foregroundColor: Colors.white,
          padding: buttonPad,
          shape: shape,
          textStyle: buttonText,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.navy,
          side: const BorderSide(color: Color(0xFFCBD2DE)),
          padding: buttonPad,
          shape: shape,
          textStyle: buttonText,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.navy,
          shape: shape,
          textStyle: buttonText,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(shape: shape),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
        elevation: 2,
        focusElevation: 2,
        hoverElevation: 4,
        highlightElevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card)),
        extendedTextStyle: buttonText,
      ),

      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surface,
        selectedColor: AppColors.brandSoft,
        checkmarkColor: AppColors.navy,
        side: const BorderSide(color: AppColors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        labelStyle: GoogleFonts.inter(fontSize: 12.5, color: AppColors.text),
        secondaryLabelStyle: GoogleFonts.inter(fontSize: 12.5, color: AppColors.navy, fontWeight: FontWeight.w600),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      ),

      tabBarTheme: TabBarThemeData(
        labelColor: AppColors.navy,
        unselectedLabelColor: AppColors.muted,
        indicatorColor: AppColors.navy,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: Colors.transparent,
        labelStyle: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600),
        unselectedLabelStyle: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sheet)),
        titleTextStyle: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.text),
        contentTextStyle: GoogleFonts.inter(fontSize: 14, height: 1.45, color: AppColors.text),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: AppColors.border,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.navyDark,
        contentTextStyle: GoogleFonts.inter(fontSize: 13.5, color: Colors.white),
        actionTextColor: AppColors.amber,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.field)),
        insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.field),
          side: const BorderSide(color: AppColors.border),
        ),
        textStyle: GoogleFonts.inter(fontSize: 13.5, color: AppColors.text),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        textStyle: GoogleFonts.inter(fontSize: 13.5, color: AppColors.text),
        menuStyle: const MenuStyle(
          backgroundColor: WidgetStatePropertyAll(AppColors.surface),
          surfaceTintColor: WidgetStatePropertyAll(Colors.transparent),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: AppColors.muted,
        titleTextStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.text),
        subtitleTextStyle: GoogleFonts.inter(fontSize: 12.5, color: AppColors.muted),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.field)),
      ),
      dividerTheme: const DividerThemeData(color: AppColors.border, thickness: 1, space: 1),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.navy,
        linearTrackColor: AppColors.border,
        circularTrackColor: Colors.transparent,
      ),
      // Toggles: navy with a white knob when on, light grey with a grey knob when off.
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? Colors.white : const Color(0xFF9AA3AF)),
        trackColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? AppColors.navy : const Color(0xFFE5E7EB)),
        trackOutlineColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? Colors.transparent : const Color(0xFFD1D5DB)),
        thumbIcon: const WidgetStatePropertyAll(null),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? AppColors.navy : null),
        checkColor: const WidgetStatePropertyAll(Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        side: const BorderSide(color: Color(0xFFB3BCCB), width: 1.4),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? AppColors.navy : null),
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        headerBackgroundColor: AppColors.navy,
        headerForegroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sheet)),
        todayBorder: const BorderSide(color: AppColors.amber),
        todayForegroundColor: const WidgetStatePropertyAll(AppColors.navy),
        dayBackgroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? AppColors.navy : null),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(color: AppColors.navyDark, borderRadius: BorderRadius.circular(6)),
        textStyle: GoogleFonts.inter(fontSize: 12, color: Colors.white),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(AppColors.muted.withValues(alpha: 0.35)),
        radius: const Radius.circular(8),
        thickness: const WidgetStatePropertyAll(6),
      ),
      drawerTheme: const DrawerThemeData(
        backgroundColor: AppColors.navy,
        surfaceTintColor: Colors.transparent,
      ),
    );
  }
}
