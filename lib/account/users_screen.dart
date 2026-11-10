// Settings → Users (admins): the company's people and their roles. Admins create every account here.
import 'package:firebase_auth/firebase_auth.dart';
import 'package:an_agency/ui/app_theme.dart';
import 'package:flutter/material.dart';

import '../crm/crm_ui.dart';
import 'account.dart';
import 'add_user_dialog.dart';

class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  List<AppUser>? _users;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final users = await loadCompanyUsers(fresh: true);
      if (!mounted) return;
      setState(() => _users = users);
    } catch (e) {
      debugPrint('Loading users failed: $e');
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _run(Future<void> Function() action, String done) async {
    try {
      await action();
      if (mounted) crmSnack(context, done);
      _load();
    } catch (e) {
      debugPrint('User change failed: $e');
      if (mounted) crmSnack(context, "Couldn't save. Try again.", error: true);
    }
  }

  /// Bookers the company may still add under its plan (null = no limit).
  int? get _bookersLeft {
    final max = Account.company?.maxBookers ?? 0;
    if (max <= 0) return null;
    final bookers = (_users ?? const <AppUser>[]).where((u) => u.role == Role.booker && u.isActive).length;
    return max - bookers;
  }

  Future<void> _addUser() async {
    final left = _bookersLeft;
    final roles = left != null && left <= 0 ? [Role.admin] : [Role.booker, Role.admin];
    if (roles.length == 1) {
      crmSnack(
        context,
        'Your plan allows ${Account.company?.maxBookers} bookers, so only admins can be added. '
        'Switch a booker off, or ask depotOS for more.',
        error: true,
      );
    }
    if (await showAddUserDialog(context, roles: roles)) _load();
  }

  Future<void> _resetPassword(AppUser u) async {
    try {
      await sendPasswordReset(u.email);
      if (mounted) crmSnack(context, 'Password reset email sent to ${u.email}');
    } catch (e) {
      debugPrint('Password reset failed: $e');
      if (mounted) crmSnack(context, "Couldn't send the email. Try again.", error: true);
    }
  }

  /// Turning a booker back on counts against the plan's booker limit.
  void _switchOn(AppUser u) {
    final left = _bookersLeft;
    if (u.role == Role.booker && left != null && left <= 0) {
      crmSnack(context, 'Your plan allows ${Account.company?.maxBookers} bookers. Switch another one off first.', error: true);
      return;
    }
    _run(() => setUserActive(u, true), '${u.display} switched on');
  }

  @override
  Widget build(BuildContext context) {
    final users = _users;
    final me = FirebaseAuth.instance.currentUser?.uid;
    final left = _bookersLeft;
    Widget body;
    if (users == null) {
      body = Center(
        child: _error != null
            ? OutlinedButton(onPressed: _load, child: Text('Try again', style: CrmTokens.body(color: CrmTokens.navy)))
            : const CircularProgressIndicator(color: CrmTokens.navy),
      );
    } else {
      body = RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 40),
          children: [
            if (left != null)
              Text('Bookers: ${Account.company!.maxBookers - left} of ${Account.company!.maxBookers} on your plan',
                  style: CrmTokens.body(color: left <= 0 ? CrmTokens.red : CrmTokens.muted)),
            CrmSectionTitle(Account.company?.name ?? 'Your company',
                trailing: TextButton.icon(
                  onPressed: _addUser,
                  icon: const Icon(Icons.person_add_alt, size: 18, color: CrmTokens.navy),
                  label: Text('Add user', style: CrmTokens.body(color: CrmTokens.navy, w: FontWeight.w600)),
                )),
            for (final u in users)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: CrmCard(
                  padding: const EdgeInsets.all(12),
                  child: Row(children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: u.isActive ? CrmTokens.blueBg : CrmTokens.bg,
                      child: Icon(u.isAdmin ? Icons.admin_panel_settings_outlined : Icons.person_outline,
                          size: 18, color: u.isActive ? CrmTokens.navy : CrmTokens.muted),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: _who(u, you: u.uid == me)),
                    if (!u.isActive) const CrmPill('Switched off', color: CrmTokens.red, background: CrmTokens.redBg),
                    const SizedBox(width: 8),
                    // The owner and your own account can't be changed here.
                    if (u.role == Role.owner || u.uid == me)
                      CrmPill(roleLabel(u.role), color: CrmTokens.navy, background: CrmTokens.blueBg)
                    else
                      PopupMenuButton<String>(
                        tooltip: 'Change',
                        onSelected: (v) {
                          switch (v) {
                            case 'admin':
                              _run(() => setUserRole(u, Role.admin), '${u.display} is now an admin');
                            case 'booker':
                              _run(() => setUserRole(u, Role.booker), '${u.display} is now a booker');
                            case 'reset':
                              _resetPassword(u);
                            case 'off':
                              _run(() => setUserActive(u, false), '${u.display} switched off');
                            case 'on':
                              _switchOn(u);
                          }
                        },
                        itemBuilder: (_) => [
                          if (u.role != Role.admin) const PopupMenuItem(value: 'admin', child: Text('Make admin')),
                          if (u.role != Role.booker) const PopupMenuItem(value: 'booker', child: Text('Make booker')),
                          const PopupMenuItem(value: 'reset', child: Text('Send password reset email')),
                          u.isActive
                              ? const PopupMenuItem(value: 'off', child: Text('Switch off (can\'t log in)'))
                              : const PopupMenuItem(value: 'on', child: Text('Switch on')),
                        ],
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          CrmPill(roleLabel(u.role), color: CrmTokens.navy, background: CrmTokens.blueBg),
                          const Icon(Icons.arrow_drop_down, color: CrmTokens.muted),
                        ]),
                      ),
                  ]),
                ),
              ),
            const SizedBox(height: 8),
            Text(
              'Add user creates the login; send the person their username, email and password yourself. '
              'Switched-off people can\'t open the app, but their past orders stay in reports.',
              style: CrmTokens.body(size: 12, color: CrmTokens.muted),
            ),
          ],
        ),
      );
    }
    return Scaffold(
      backgroundColor: CrmTokens.bg,
      appBar: AppBar(
        title: Text('Users', style: CrmTokens.display(size: 18, color: AppColors.text, w: FontWeight.w600)),
      ),
      body: body,
    );
  }

  Widget _who(AppUser u, {bool you = false}) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${u.display}${you ? '  (you)' : ''}', style: CrmTokens.body(size: 14, w: FontWeight.w600)),
        Text(u.email, style: CrmTokens.body(size: 12, color: CrmTokens.muted)),
      ]);
}
