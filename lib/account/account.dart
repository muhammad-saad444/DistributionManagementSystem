// Who is signed in: their company and role.
//
//   - `companies/{companyId}`: name, status (active | suspended), modules, limits, ownerUid.
//   - `users/{uid}`: companyId, role (owner | admin | booker), status (active | pending | disabled),
//     name, email.
//
// A user's role decides admin vs booker screens (it used to be "is the email admin@gmail.com").
// Someone signing in without a `users` record gets a pending one and waits for an admin to approve
// them. Firestore rules (firestore.rules) stop anyone changing their own role or company.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

final _db = FirebaseFirestore.instance;

enum Role { owner, admin, booker }

enum UserStatus { active, pending, disabled }

Role _role(dynamic v) => Role.values.firstWhere((r) => r.name == v, orElse: () => Role.booker);
UserStatus _status(dynamic v) => UserStatus.values.firstWhere((s) => s.name == v, orElse: () => UserStatus.pending);

String roleLabel(Role r) => switch (r) {
      Role.owner => 'Owner',
      Role.admin => 'Admin',
      Role.booker => 'Booker',
    };

/// Every module a company can have switched on. Turning them on and off per company comes later;
/// for now every company gets all of them.
const allModules = ['crm', 'purchases', 'khata', 'dsr', 'loadsheet', 'reports'];

class AppUser {
  final String uid;
  final String? companyId;
  final Role role;
  final UserStatus status;
  final String name;
  final String email;

  const AppUser({
    required this.uid,
    required this.companyId,
    required this.role,
    required this.status,
    required this.name,
    required this.email,
  });

  factory AppUser.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data() ?? const {};
    return AppUser(
      uid: doc.id,
      companyId: m['companyId'] as String?,
      role: _role(m['role']),
      status: _status(m['status']),
      name: (m['name'] ?? '').toString(),
      email: (m['email'] ?? '').toString(),
    );
  }

  bool get isAdmin => role == Role.owner || role == Role.admin;
  bool get isActive => status == UserStatus.active;
  String get display => name.isNotEmpty ? name : email;
}

class Company {
  final String id;
  final String name;
  final bool suspended;
  final Set<String> modules;

  const Company({required this.id, required this.name, required this.suspended, required this.modules});

  factory Company.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data() ?? const {};
    final mods = m['modules'];
    return Company(
      id: doc.id,
      name: (m['name'] ?? doc.id).toString(),
      suspended: m['status'] == 'suspended',
      modules: mods is Map ? {for (final e in mods.entries) if (e.value == true) e.key.toString()} : allModules.toSet(),
    );
  }

  bool has(String module) => modules.contains(module);
}

/// The signed-in user and their company, set once they pass the account check.
class Account {
  static AppUser? user;
  static Company? company;

  static bool get isAdmin => user?.isAdmin ?? false;
  static String? get companyId => user?.companyId;

  static void clear() {
    user = null;
    company = null;
    _companyUsers = null;
  }
}

// =============================================================================
// Signing in
// =============================================================================

/// Where a signed-in user can go.
enum AccountState {
  ready, // active member of an active company
  pending, // waiting for an admin to approve them
  disabled, // switched off by an admin
  suspended, // their company is suspended
  needsSetup, // the original admin, before the company has been set up
  legacyBooker, // a booker, before the company has been set up: works as before
}

// The company this app ran as before it served several companies, and the admin login it used.
// Only used to recognise that admin the first time, so they can set the company up.
const legacyCompanyId = 'an-agency';
const legacyCompanyName = 'A.N Agency';
const _legacyAdminEmail = 'admin@gmail.com';

/// Looks up (or, for someone new, creates a pending) `users` record and decides what they see.
Future<AccountState> loadAccount(User authUser, {String name = ''}) async {
  Account.clear();
  final ref = _db.collection('users').doc(authUser.uid);
  final snap = await ref.get();

  if (!snap.exists) {
    // Until the original admin has set the company up, everyone carries on as before.
    if (!await _legacyCompanyExists()) {
      final email = (authUser.email ?? '').trim().toLowerCase();
      return email == _legacyAdminEmail ? AccountState.needsSetup : AccountState.legacyBooker;
    }
    // Someone new: ask to join and wait for an admin.
    await ref.set({
      'companyId': null,
      'role': 'booker',
      'status': 'pending',
      'name': name.isNotEmpty ? name : (authUser.displayName ?? ''),
      'email': authUser.email ?? '',
      'createdAt': FieldValue.serverTimestamp(),
    });
    Account.user = AppUser.fromDoc(await ref.get());
    return AccountState.pending;
  }

  final user = AppUser.fromDoc(snap);
  Account.user = user;
  if (user.status == UserStatus.disabled) return AccountState.disabled;
  if (user.status == UserStatus.pending || user.companyId == null) return AccountState.pending;

  final companySnap = await _db.collection('companies').doc(user.companyId).get();
  final company = Company.fromDoc(companySnap);
  Account.company = company;
  if (!companySnap.exists || company.suspended) return AccountState.suspended;

  // Keep the name current for lists (it's what bookers type at login).
  if (name.isNotEmpty && name != user.name) {
    ref.update({'name': name}).catchError((Object e) => debugPrint('Updating name failed: $e'));
  }
  return AccountState.ready;
}

Future<bool> _legacyCompanyExists() async {
  try {
    return (await _db.collection('companies').doc(legacyCompanyId).get()).exists;
  } on FirebaseException catch (e) {
    // The rules only let outsiders see that a company is missing; a refusal means it exists.
    if (e.code == 'permission-denied') return true;
    rethrow;
  }
}

// =============================================================================
// The company's people
// =============================================================================

List<AppUser>? _companyUsers;

/// Everyone in the signed-in user's company (cached until [fresh]).
Future<List<AppUser>> loadCompanyUsers({bool fresh = false}) async {
  final companyId = Account.companyId;
  if (companyId == null) return const [];
  if (!fresh && _companyUsers != null) return _companyUsers!;
  final snap = await _db.collection('users').where('companyId', isEqualTo: companyId).get();
  _companyUsers = snap.docs.map(AppUser.fromDoc).toList()
    ..sort((a, b) => a.display.toLowerCase().compareTo(b.display.toLowerCase()));
  return _companyUsers!;
}

/// The uids of the company's bookers (disabled ones too, so their past sales still show in reports).
Future<Set<String>> companyBookerUids() async {
  final users = await loadCompanyUsers();
  return {for (final u in users) if (u.role == Role.booker && u.status != UserStatus.pending) u.uid};
}

/// Tells booker lists (built from `sessions`) who counts as a booker: the company's bookers by role,
/// or, before the company is set up, everyone except the original admin login.
Future<bool Function(String uid, String email)> bookerFilter() async {
  if (Account.companyId == null) {
    return (uid, email) => email.trim().toLowerCase() != _legacyAdminEmail;
  }
  final uids = await companyBookerUids();
  return (uid, email) => uids.contains(uid);
}

/// People waiting to be approved into a company.
Future<List<AppUser>> loadPendingUsers() async {
  final snap =
      await _db.collection('users').where('status', isEqualTo: 'pending').where('companyId', isNull: true).get();
  return snap.docs.map(AppUser.fromDoc).toList()
    ..sort((a, b) => a.display.toLowerCase().compareTo(b.display.toLowerCase()));
}

/// Approves a pending person into the admin's company with [role].
Future<void> approveUser(AppUser u, Role role) async {
  await _db.collection('users').doc(u.uid).update({
    'companyId': Account.companyId,
    'role': role.name,
    'status': 'active',
    'approvedBy': FirebaseAuth.instance.currentUser?.uid,
    'approvedAt': FieldValue.serverTimestamp(),
  });
  _companyUsers = null;
}

Future<void> setUserRole(AppUser u, Role role) async {
  await _db.collection('users').doc(u.uid).update({'role': role.name});
  _companyUsers = null;
}

Future<void> setUserActive(AppUser u, bool active) async {
  await _db.collection('users').doc(u.uid).update({'status': active ? 'active' : 'disabled'});
  _companyUsers = null;
}

// =============================================================================
// First-time company setup (the original admin, once)
// =============================================================================

class SetupPerson {
  final String uid;
  final String name;
  final String email;
  Role role;
  bool include;
  SetupPerson(this.uid, this.name, this.email, this.role) : include = true;
}

/// Everyone who has logged in before (from `sessions`), with a suggested role.
Future<List<SetupPerson>> loadSetupPeople() async {
  final me = FirebaseAuth.instance.currentUser?.uid;
  final snap = await _db.collection('sessions').get();
  final people = <SetupPerson>[];
  for (final d in snap.docs) {
    final m = d.data();
    final uid = (m['uid'] ?? d.id).toString();
    if (uid.isEmpty || uid == me) continue;
    final email = (m['email'] ?? '').toString().trim();
    people.add(SetupPerson(uid, (m['username'] ?? '').toString().trim(), email,
        email.toLowerCase() == _legacyAdminEmail ? Role.admin : Role.booker));
  }
  return people..sort((a, b) => (a.name.isEmpty ? a.email : a.name).toLowerCase().compareTo((b.name.isEmpty ? b.email : b.name).toLowerCase()));
}

/// Creates the company with the signed-in user as owner, then adds the chosen people.
Future<void> setUpCompany(List<SetupPerson> people, {required String ownerName}) async {
  final me = FirebaseAuth.instance.currentUser!;
  final companyRef = _db.collection('companies').doc(legacyCompanyId);
  // The company and its owner first, together: the rules only let the owner add people after this.
  final first = _db.batch();
  first.set(companyRef, {
    'name': legacyCompanyName,
    'status': 'active',
    'modules': {for (final m in allModules) m: true},
    'limits': {'maxBookers': 50},
    'ownerUid': me.uid,
    'createdAt': FieldValue.serverTimestamp(),
  });
  first.set(_db.collection('users').doc(me.uid), {
    'companyId': legacyCompanyId,
    'role': 'owner',
    'status': 'active',
    'name': ownerName,
    'email': me.email ?? '',
    'createdAt': FieldValue.serverTimestamp(),
  });
  await first.commit();

  final chosen = people.where((p) => p.include).toList();
  for (var i = 0; i < chosen.length; i += 400) {
    final batch = _db.batch();
    for (final p in chosen.skip(i).take(400)) {
      // merge: someone who already logged in after the update has a pending record to replace
      batch.set(_db.collection('users').doc(p.uid), {
        'companyId': legacyCompanyId,
        'role': p.role.name,
        'status': 'active',
        'name': p.name,
        'email': p.email,
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    await batch.commit();
  }
}
