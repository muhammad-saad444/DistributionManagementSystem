// Who is signed in: their company and role.
//
//   - `companies/{companyId}`: name, status (active | suspended), modules, limits, ownerUid.
//   - `users/{uid}`: companyId, role (owner | admin | booker), status (active | pending | disabled),
//     name, email.
//
// A user's role decides admin vs booker screens (it used to be "is the email admin@gmail.com").
// Admins create every login (username, email, password); nobody signs themselves up. A login
// without a `users` record belongs to no company and reaches nothing. Firestore rules
// (firestore.rules) stop anyone changing their own role or company.
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

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

/// Modules the super admin switches on per company. Orders, invoices, products, areas and customers
/// are always on.
const allModules = ['crm', 'purchases', 'khata', 'dsr', 'loadsheet', 'hr'];

String moduleLabel(String m) => switch (m) {
      'crm' => 'CRM (customer visits and follow-ups)',
      'purchases' => 'Purchases, stock and profit',
      'khata' => 'Khata and booker credits',
      'dsr' => 'DSR reports',
      'loadsheet' => 'Load sheets',
      'hr' => 'HR: staff, attendance, leave and payroll',
      _ => m,
    };

class AppUser {
  final String uid;
  final String? companyId;
  final Role role;
  final UserStatus status;
  final String name;
  final String email;
  final String? warehouseId; // bookers: the warehouse their sales come from (null = Main)

  const AppUser({
    required this.uid,
    required this.companyId,
    required this.role,
    required this.status,
    required this.name,
    required this.email,
    this.warehouseId,
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
      warehouseId: m['warehouseId'] as String?,
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
  final int maxBookers;
  // The original company's data still lives in the shared top-level collections, until the
  // super admin moves it into companies/{id}/… (see moveLegacyData).
  final bool legacyData;

  const Company({
    required this.id,
    required this.name,
    required this.suspended,
    required this.modules,
    this.maxBookers = 0,
    this.legacyData = false,
  });

  factory Company.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data() ?? const {};
    final mods = m['modules'];
    final limits = m['limits'];
    return Company(
      id: doc.id,
      name: (m['name'] ?? doc.id).toString(),
      suspended: m['status'] == 'suspended',
      modules: mods is Map ? {for (final e in mods.entries) if (e.value == true) e.key.toString()} : allModules.toSet(),
      maxBookers: limits is Map && limits['maxBookers'] is num ? (limits['maxBookers'] as num).toInt() : 0,
      legacyData: m['legacyData'] == true,
    );
  }

  bool has(String module) => modules.contains(module);
}

/// A collection of the signed-in user's company: `companies/{id}/{name}`. Every screen reads and
/// writes business data through this, so a company only ever touches its own data (the rules
/// enforce the same on the server). Before the original company's data has been moved, and before
/// it is set up, this is the old shared top-level collection.
CollectionReference<Map<String, dynamic>> companyCol(String name) {
  final c = Account.company;
  if (c == null || c.legacyData) return _db.collection(name);
  return _db.collection('companies').doc(c.id).collection(name);
}

/// The signed-in user and their company, set once they pass the account check. For the super admin,
/// [company] is whichever company they have opened from the depotOS Console.
class Account {
  static AppUser? user;
  static Company? company;
  static bool isSuperAdmin = false;

  static bool get isAdmin => isSuperAdmin || (user?.isAdmin ?? false);
  static String? get companyId => company?.id ?? user?.companyId;
  static bool has(String module) => company?.has(module) ?? true;
  /// The open company's name, for printed invoices and reports.
  static String get companyName {
    final n = company?.name.trim() ?? '';
    return n.isEmpty ? legacyCompanyName : n;
  }

  /// Called when the company changes, so screens can drop data they cached for the old one.
  static final List<void Function()> onCompanyChanged = [];

  static void _setCompany(Company? c) {
    company = c;
    _companyUsers = null;
    for (final f in onCompanyChanged) {
      f();
    }
  }

  /// Super admin: work inside [c] (its admin panel, its data).
  static void openCompany(Company c) => _setCompany(c);

  static void clear() {
    user = null;
    isSuperAdmin = false;
    _setCompany(null);
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
  superAdmin, // depotOS: the console for all companies
  superAdminSetup, // the depotOS login, before it has been made super admin in the Firebase console
}

// The company this app ran as before it served several companies, and the admin login it used.
// Only used to recognise that admin the first time, so they can set the company up.
const legacyCompanyId = 'an-agency';
const legacyCompanyName = 'A.N Agency';
const _legacyAdminEmail = 'admin@gmail.com';

/// The depotOS owner's login. They become super admin once `platform_admins/{uid}` exists for it,
/// which only the Firebase console can create (see the rules).
const superAdminEmail = 'depotos@gmail.com';

/// Looks up (or, for someone new, creates a pending) `users` record and decides what they see.
Future<AccountState> loadAccount(User authUser, {String name = ''}) async {
  Account.clear();
  final email = (authUser.email ?? '').trim().toLowerCase();

  if (await _existsOrDenied(_db.collection('platform_admins').doc(authUser.uid))) {
    Account.isSuperAdmin = true;
    return AccountState.superAdmin;
  }
  if (email == superAdminEmail) return AccountState.superAdminSetup;

  final ref = _db.collection('users').doc(authUser.uid);
  final snap = await ref.get();

  if (!snap.exists) {
    // Until the original admin has set the company up, everyone carries on as before.
    if (!await _legacyCompanyExists()) {
      return email == _legacyAdminEmail ? AccountState.needsSetup : AccountState.legacyBooker;
    }
    // A login no admin created: it belongs to no company and reaches nothing.
    return AccountState.pending;
  }

  final user = AppUser.fromDoc(snap);
  Account.user = user;
  if (user.status == UserStatus.disabled) return AccountState.disabled;
  if (user.status == UserStatus.pending || user.companyId == null) return AccountState.pending;

  final companySnap = await _db.collection('companies').doc(user.companyId).get();
  final company = Company.fromDoc(companySnap);
  Account._setCompany(company);
  if (!companySnap.exists || company.suspended) return AccountState.suspended;

  // The username the admin gave this person is what reports and shop lists go by. Older records
  // (from before admins created accounts) take the name typed at login.
  if (user.name.isEmpty && name.isNotEmpty) {
    ref.update({'name': name}).catchError((Object e) => debugPrint('Updating name failed: $e'));
  }
  final username = user.name.isNotEmpty ? user.name : name;
  // The company's own copy of the login session: screens list the company's people from it.
  if (!company.legacyData) {
    final session = (await _db.collection('sessions').doc(authUser.uid).get()).data() ?? const {};
    await companyCol('sessions').doc(authUser.uid).set({
      ...session,
      'uid': authUser.uid,
      'email': authUser.email ?? '',
      'username': username,
    }, SetOptions(merge: true));
  }
  return AccountState.ready;
}

/// Whether [ref] exists. A refusal counts as "no", so the app still works while older security
/// rules (without super admins or invitations) are deployed.
Future<bool> _existsOrDenied(DocumentReference<Map<String, dynamic>> ref) async {
  try {
    return (await ref.get()).exists;
  } on FirebaseException catch (e) {
    if (e.code == 'permission-denied') return false;
    rethrow;
  }
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
    'legacyData': true, // its data is still in the shared collections until the super admin moves it
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

// =============================================================================
// Creating accounts (admins only: nobody signs themselves up)
// =============================================================================

/// Why creating a login failed, in words for the admin.
class AccountCreationError implements Exception {
  final String message;
  const AccountCreationError(this.message);
  @override
  String toString() => message;
}

/// Creates a login (email + password) without signing the admin out, using Firebase's sign-up
/// service directly. Returns the new user's uid.
Future<String> _createLogin(String email, String password) async {
  final key = Firebase.app().options.apiKey;
  final res = await http.post(
    Uri.parse('https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=$key'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({'email': email, 'password': password, 'returnSecureToken': false}),
  );
  final body = jsonDecode(res.body) as Map<String, dynamic>;
  if (res.statusCode == 200 && body['localId'] is String) return body['localId'] as String;
  final code = ((body['error'] as Map?)?['message'] ?? '').toString();
  throw AccountCreationError(switch (code) {
    'EMAIL_EXISTS' => 'This email already has a login. Use a different email.',
    'INVALID_EMAIL' => 'That email address is not valid.',
    final c when c.startsWith('WEAK_PASSWORD') => 'The password must be at least 6 characters.',
    'OPERATION_NOT_ALLOWED' => 'Email/password logins are switched off in Firebase Authentication.',
    'TOO_MANY_ATTEMPTS_TRY_LATER' => 'Too many attempts. Wait a few minutes and try again.',
    _ => "Couldn't create the login ($code).",
  });
}

/// Creates someone's login and puts them in [companyId] (default: the admin's company) as [role].
/// The admin then gives them the username, email and password.
Future<void> createAccount({
  required String username,
  required String email,
  required String password,
  required Role role,
  String? companyId,
}) async {
  final c = companyId ?? Account.companyId;
  if (c == null) throw const AccountCreationError('No company selected.');
  final e = email.trim().toLowerCase();
  final uid = await _createLogin(e, password);
  try {
    final batch = _db.batch();
    batch.set(_db.collection('users').doc(uid), {
      'companyId': c,
      'role': role.name,
      'status': 'active',
      'name': username.trim(),
      'email': e,
      'createdBy': FirebaseAuth.instance.currentUser?.uid,
      'createdAt': FieldValue.serverTimestamp(),
    });
    // Only the super admin creates owners (the company's main admin).
    if (role == Role.owner) batch.update(_db.collection('companies').doc(c), {'ownerUid': uid});
    await batch.commit();
  } catch (err) {
    debugPrint('Login $e created but its company record failed: $err');
    throw AccountCreationError(
        'The login was created but not added to the company. Ask depotOS support to finish it ($e).');
  }
  _companyUsers = null;
}

/// Emails the person a link to choose a new password (Firebase sends it).
Future<void> sendPasswordReset(String email) => FirebaseAuth.instance.sendPasswordResetEmail(email: email.trim());

// =============================================================================
// Super admin (depotOS)
// =============================================================================

/// Every company, for the depotOS Console.
Future<List<Company>> loadCompanies() async {
  final snap = await _db.collection('companies').get();
  return snap.docs.map(Company.fromDoc).toList()..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
}

/// Everyone in [companyId] (super admin), or in the signed-in user's company.
Future<List<AppUser>> loadUsersOf(String companyId) async {
  final snap = await _db.collection('users').where('companyId', isEqualTo: companyId).get();
  return snap.docs.map(AppUser.fromDoc).toList()
    ..sort((a, b) => a.display.toLowerCase().compareTo(b.display.toLowerCase()));
}

/// A company id from its name: "XYZ Traders" → "xyz-traders".
String companyIdFor(String name) =>
    name.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');

/// Creates a company (super admin). Its admin's login is added next, as its owner.
Future<void> createCompany({
  required String id,
  required String name,
  required Set<String> modules,
  required int maxBookers,
}) async {
  final ref = _db.collection('companies').doc(id);
  if ((await ref.get()).exists) throw AccountCreationError('A company with id "$id" already exists.');
  await ref.set({
    'name': name,
    'status': 'active',
    'modules': {for (final m in allModules) m: modules.contains(m)},
    'limits': {'maxBookers': maxBookers},
    'legacyData': false,
    'createdAt': FieldValue.serverTimestamp(),
    'createdBy': FirebaseAuth.instance.currentUser?.uid,
  });
}

Future<void> updateCompany(String id, {String? name, Set<String>? modules, int? maxBookers, bool? suspended}) =>
    _db.collection('companies').doc(id).update({
      'name': ?name,
      if (modules != null) 'modules': {for (final m in allModules) m: modules.contains(m)},
      if (maxBookers != null) 'limits.maxBookers': maxBookers,
      if (suspended != null) 'status': suspended ? 'suspended' : 'active',
    });

/// Every business collection a company has. Moving the original company copies each of them.
const companyCollections = [
  'areas', 'booker_credits', 'crm_followups', 'crm_visits', 'customer_recoveries', 'customers',
  'dsr_reports', 'invoices', 'khata_entries', 'load_sheets', 'products', 'purchases', 'quotations', 'sessions',
  'settings', 'stock_moves', 'supplier_payments', 'suppliers', 'user_areas', 'user_customers', 'warehouses',
  // Orders
  'purchase_orders', 'sales_orders',
  // HR
  'employees', 'advances', 'payroll', 'payslips', 'hr_links', 'attendance', 'leave_requests',
];

/// Super admin, once: copies the original company's data from the shared top-level collections
/// into companies/{id}/…, then switches the company over to it. The top-level copy is left as a
/// backup (only the super admin can read it afterwards). [progress] gets "collection: n docs".
Future<Map<String, int>> moveLegacyData(String companyId, {void Function(String)? progress}) async {
  final counts = <String, int>{};
  final target = _db.collection('companies').doc(companyId);
  for (final name in companyCollections) {
    progress?.call('Reading $name…');
    final snap = await _db.collection(name).get();
    var n = 0;
    for (var i = 0; i < snap.docs.length; i += 400) {
      final batch = _db.batch();
      for (final d in snap.docs.skip(i).take(400)) {
        batch.set(target.collection(name).doc(d.id), d.data());
        n++;
      }
      await batch.commit();
      progress?.call('$name: $n of ${snap.docs.length}');
    }
    counts[name] = n;
  }
  // Check every document arrived before switching over.
  for (final name in companyCollections) {
    final copied = (await target.collection(name).get()).docs.length;
    if (copied < (counts[name] ?? 0)) {
      throw StateError('$name: only $copied of ${counts[name]} documents copied; nothing was switched over');
    }
  }
  await target.update({'legacyData': false, 'dataMovedAt': FieldValue.serverTimestamp()});
  return counts;
}
