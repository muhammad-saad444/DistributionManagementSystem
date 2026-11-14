// Who was signed in on this device last time, kept in local storage, so the app can open their
// screens the moment it starts and check with the server in the background.
//
// Kept: the user's role and company (what decides which screens open), and when the login
// session ends. Cleared when they sign out. Nothing secret is kept here: no password or token.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'account.dart';

const _key = 'saved_account_v1';

class SavedAccount {
  final String uid;
  final AccountState state; // ready or superAdmin
  final DateTime expiresAt; // when the login session ends
  final String name;
  final AppUser? user;
  final Company? company;

  const SavedAccount({
    required this.uid,
    required this.state,
    required this.expiresAt,
    required this.name,
    this.user,
    this.company,
  });

  bool get usable => DateTime.now().isBefore(expiresAt);

  /// Puts this account in place (Account.user / company) so screens can open with it.
  void apply() {
    Account.user = user;
    Account.isSuperAdmin = state == AccountState.superAdmin;
    if (state != AccountState.superAdmin) Account.company = company;
  }

  /// The account Account holds now, for [uid], after a successful check.
  static SavedAccount? fromCurrent(String uid, AccountState state, DateTime expiresAt, String name) {
    if (state != AccountState.ready && state != AccountState.superAdmin) return null;
    return SavedAccount(
      uid: uid,
      state: state,
      expiresAt: expiresAt,
      name: name,
      user: Account.user,
      company: state == AccountState.superAdmin ? null : Account.company,
    );
  }

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'state': state.name,
        'expiresAt': expiresAt.millisecondsSinceEpoch,
        'name': name,
        if (user != null)
          'user': {
            'companyId': user!.companyId,
            'role': user!.role.name,
            'status': user!.status.name,
            'name': user!.name,
            'email': user!.email,
            'warehouseId': user!.warehouseId,
            if (user!.sections != null) 'sections': user!.sections!.toList(),
          },
        if (company != null)
          'company': {
            'id': company!.id,
            'name': company!.name,
            'suspended': company!.suspended,
            'modules': company!.modules.toList(),
            'maxBookers': company!.maxBookers,
            'legacyData': company!.legacyData,
          },
      };

  static SavedAccount? fromJson(Map<String, dynamic> m) {
    final state = AccountState.values.where((s) => s.name == m['state']).firstOrNull;
    final uid = m['uid'];
    final exp = m['expiresAt'];
    if (state == null || uid is! String || exp is! int) return null;
    final u = m['user'];
    final c = m['company'];
    return SavedAccount(
      uid: uid,
      state: state,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(exp),
      name: (m['name'] ?? '').toString(),
      user: u is Map
          ? AppUser(
              uid: uid,
              companyId: u['companyId'] as String?,
              role: Role.values.firstWhere((r) => r.name == u['role'], orElse: () => Role.booker),
              status: UserStatus.values.firstWhere((s) => s.name == u['status'], orElse: () => UserStatus.pending),
              name: (u['name'] ?? '').toString(),
              email: (u['email'] ?? '').toString(),
              warehouseId: u['warehouseId'] as String?,
              sections: sectionsFrom(u['sections']),
            )
          : null,
      company: c is Map
          ? Company(
              id: (c['id'] ?? '').toString(),
              name: (c['name'] ?? '').toString(),
              suspended: c['suspended'] == true,
              modules: {for (final x in (c['modules'] as List? ?? const [])) x.toString()},
              maxBookers: (c['maxBookers'] as num?)?.toInt() ?? 0,
              legacyData: c['legacyData'] == true,
            )
          : null,
    );
  }

  static Future<SavedAccount?>? _early;

  /// Starts reading at app start-up, alongside Firebase, so it is ready the moment it's needed.
  static void preload() => _early ??= read();

  /// The read started by [preload], used once (later opens, e.g. after signing out, read afresh).
  static Future<SavedAccount?> loaded() {
    final f = _early;
    _early = null;
    return f ?? read();
  }

  /// What this device saved last time, if it can still be used.
  static Future<SavedAccount?> read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return null;
      final saved = fromJson(jsonDecode(raw) as Map<String, dynamic>);
      if (saved == null || !saved.usable) return null;
      if (saved.state == AccountState.ready && (saved.user == null || saved.company == null)) return null;
      return saved;
    } catch (e) {
      debugPrint('Reading the saved account failed: $e');
      return null;
    }
  }

  Future<void> save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(toJson()));
    } catch (e) {
      debugPrint('Saving the account failed: $e');
    }
  }

  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {}
  }
}
