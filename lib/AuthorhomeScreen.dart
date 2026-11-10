// auth_or_home.dart
import 'package:flutter/material.dart';
import 'ui/app_splash.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'AuthScreen.dart';
import 'account/account_gate.dart';

class AuthOrHome extends StatelessWidget {
  const AuthOrHome({super.key});

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
          future: FirebaseFirestore.instance
              .collection('sessions')
              .doc(user.uid)
              .get(),
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
