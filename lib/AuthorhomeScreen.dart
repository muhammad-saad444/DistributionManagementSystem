// auth_or_home.dart
// Decides the first screen: sign-in, or the user's own screens.
//
// When this device remembers who was signed in (account/saved_account.dart), their screens open
// at once, before Firebase has even confirmed the sign-in; the checks then run in the background
// and only change the screen if something is wrong (signed out, session ended, switched off).
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'AuthScreen.dart';
import 'account/account_gate.dart';
import 'account/saved_account.dart';
import 'ui/app_splash.dart';

class AuthOrHome extends StatefulWidget {
  const AuthOrHome({super.key});

  @override
  State<AuthOrHome> createState() => _AuthOrHomeState();
}

class _AuthOrHomeState extends State<AuthOrHome> {
  SavedAccount? _saved;
  bool _savedRead = false;
  bool _authKnown = false;
  User? _user;
  StreamSubscription<User?>? _sub;

  @override
  void initState() {
    super.initState();
    SavedAccount.loaded().then((s) {
      if (!mounted) return;
      s?.apply();
      setState(() {
        _saved = s;
        _savedRead = true;
      });
    });
    _sub = FirebaseAuth.instance.authStateChanges().listen((u) {
      if (u == null) SavedAccount.clear(); // signed out: forget this device's account
      if (!mounted) return;
      setState(() {
        _user = u;
        _authKnown = true;
        if (u == null || (_saved != null && _saved!.uid != u.uid)) _saved = null;
      });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

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
    final saved = _saved;
    // Remembered on this device: open their screens now (the same gate stays as sign-in confirms).
    if (saved != null && (!_authKnown || _user?.uid == saved.uid)) {
      return AccountGate(key: ValueKey(saved.uid), expiresAt: saved.expiresAt, name: saved.name, saved: saved);
    }
    if (!_savedRead || !_authKnown) return const AppSplash();

    final user = _user;
    if (user == null) return const AuthScreen();

    // First time on this device: check the login session, then the account.
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      key: ValueKey('session-${user.uid}'),
      future: _session(user.uid),
      builder: (context, s) {
        if (s.connectionState == ConnectionState.waiting) return const AppSplash();

        final data = s.data?.data() ?? {};
        final expTs = data['expiresAt'];
        final exp = (expTs is Timestamp) ? expTs.toDate() : null;
        final username = (data['username'] ?? user.displayName ?? '').toString();

        // Expired or missing → sign out
        if (exp == null || DateTime.now().isAfter(exp)) {
          FirebaseAuth.instance.signOut();
          return const AuthScreen();
        }

        // Admin or booker screens come from the user's role in their company
        return AccountGate(key: ValueKey(user.uid), expiresAt: exp, name: username);
      },
    );
  }
}
