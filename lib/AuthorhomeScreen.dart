// auth_or_home.dart
import 'package:flutter/material.dart';
import 'ui/app_splash.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'AuthScreen.dart';
import 'account/account_gate.dart';

class AuthOrHome extends StatelessWidget {
  const AuthOrHome({super.key});

  /// The login session: this device's saved copy when it is still valid (instant), else the server's.
  static Future<DocumentSnapshot<Map<String, dynamic>>> _session(String uid) async {
    final ref = FirebaseFirestore.instance.collection('sessions').doc(uid);
    try {
      final saved = await ref.get(const GetOptions(source: Source.cache));
      final exp = saved.data()?['expiresAt'];
      if (exp is Timestamp && DateTime.now().isBefore(exp.toDate())) return saved;
    } catch (_) {
      // Not saved on this device yet.
    }
    return ref.get();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const AppSplash();
        }

        final user = snap.data;
        if (user == null) {
          return const AuthScreen();
        }

        // ✅ User logged in → check Firestore session
        return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          future: _session(user.uid),
          builder: (context, s) {
            if (s.connectionState == ConnectionState.waiting) {
              return const AppSplash();
            }

            final data = s.data?.data() ?? {};
            final expTs = data['expiresAt'];
            final exp = (expTs is Timestamp) ? expTs.toDate() : null;
            final username = (data['username'] ?? user.displayName ?? '').toString();

            // 🔹 If expired or missing → logout
            if (exp == null || DateTime.now().isAfter(exp)) {
              FirebaseAuth.instance.signOut();
              return const AuthScreen();
            }

            // 🔹 Admin or booker screens come from the user's role in their company
            return AccountGate(expiresAt: exp, name: username);
          },
        );
      },
    );
  }
}
