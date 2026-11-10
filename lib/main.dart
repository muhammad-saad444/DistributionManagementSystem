import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'AuthScreen.dart';
import 'AuthorhomeScreen.dart';
import 'home.dart';
import 'ui/app_splash.dart';
import 'ui/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // Started once for the life of the app, however often this widget rebuilds.
  static final Future<void> _ready = _initializeFirebase();

  static Future<void> _initializeFirebase() async {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    ).timeout(const Duration(seconds: 15));
    // Keep what was read on this device (the web doesn't by default), so the next open shows the
    // last data straight away and only fetches what changed.
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'depotOS',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: FutureBuilder(
        future: _ready,
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

          return const AppSplash();
        },
      ),
    );
  }
}

