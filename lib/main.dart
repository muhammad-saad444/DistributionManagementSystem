import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'AuthScreen.dart';
import 'AuthorhomeScreen.dart';
import 'home.dart';
import 'ui/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  Future<void> _initializeFirebase() async {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    ).timeout(const Duration(seconds: 15));
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'An Agency',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: FutureBuilder(
        future: _initializeFirebase(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Scaffold(
              body: Center(
                child: SelectableText(
                  "Firebase Error: ${snapshot.error}",
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            );
          }

          if (snapshot.connectionState == ConnectionState.done) {
            return const AuthOrHome(); // Ensure this maps correctly to AuthScreen/HomeScreen
          }

          return const _Splash();
        },
      ),
    );
  }
}

/// Shown for the second or two while Firebase starts.
class _Splash extends StatelessWidget {
  const _Splash();

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