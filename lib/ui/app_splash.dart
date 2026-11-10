// The branded loading screen, shown while the app starts and while it checks who is signed in.
import 'package:flutter/material.dart';

import 'app_theme.dart';

/// The depotOS logo on the brand gradient, with a small spinner.
class AppSplash extends StatelessWidget {
  const AppSplash({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [AppColors.navyDark, AppColors.navy, AppColors.navyMid],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(color: AppColors.amber, borderRadius: BorderRadius.circular(18)),
              child: const Icon(Icons.local_shipping_rounded, color: AppColors.navyDark, size: 34),
            ),
            const SizedBox(height: 18),
            Text('depotOS', style: t.headlineSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text('Getting things ready…', style: t.bodySmall?.copyWith(color: Colors.white70)),
            const SizedBox(height: 22),
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.amber),
            ),
          ]),
        ),
      ),
    );
  }
}