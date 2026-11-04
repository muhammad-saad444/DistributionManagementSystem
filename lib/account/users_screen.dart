// Settings → Users (admins): the company's people, their roles, and requests waiting for approval.
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../crm/crm_ui.dart';
import 'account.dart';

class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  List<AppUser>? _users;
  List<AppUser> _pending = [];
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final results = await Future.wait([loadCompanyUsers(fresh: true), loadPendingUsers()]);
      if (!mounted) return;
      setState(() {
        _users = results[0];
        _pending = results[1];
      });
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

  Future<void> _approve(AppUser u) async {
    final role = await showDialog<Role>(
      context: context,
      builder: (d) => SimpleDialog(
        title: Text('Approve ${u.display} as…', style: CrmTokens.display(size: 17)),
        children: [
          for (final r in [Role.booker, Role.admin])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(d, r),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  r == Role.booker ? 'Booker: books orders, sees their own shops' : 'Admin: full admin panel',
                  style: CrmTokens.body(size: 14),
                ),
              ),
            ),
        ],
      ),
    );
    if (role == null) return;
    await _run(() => approveUser(u, role), '${u.display} added to ${Account.company?.name ?? 'your company'}');
  }

  @override
  Widget build(BuildContext context) {
    final users = _users;
    final me = FirebaseAuth.instance.currentUser?.uid;
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
            if (_pending.isNotEmpty) ...[
              const CrmSectionTitle('Waiting for approval'),
              for (final u in _pending)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: CrmCard(
                    padding: const EdgeInsets.all(12),
                    child: Row(children: [
                      const Icon(Icons.hourglass_top, color: CrmTokens.amber),
                      const SizedBox(width: 12),
                      Expanded(child: _who(u)),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: CrmTokens.amber, elevation: 0),
                        onPressed: () => _approve(u),
                        child: Text('Approve', style: CrmTokens.body(w: FontWeight.w700, color: CrmTokens.navyDark)),
                      ),
                    ]),
                  ),
                ),
            ],
            CrmSectionTitle(Account.company?.name ?? 'Your company',
                trailing: Text('${users.length} people', style: CrmTokens.body(size: 12, color: CrmTokens.muted))),
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
                            case 'off':
                              _run(() => setUserActive(u, false), '${u.display} switched off');
                            case 'on':
                              _run(() => setUserActive(u, true), '${u.display} switched on');
                          }
                        },
                        itemBuilder: (_) => [
                          if (u.role != Role.admin) const PopupMenuItem(value: 'admin', child: Text('Make admin')),
                          if (u.role != Role.booker) const PopupMenuItem(value: 'booker', child: Text('Make booker')),
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
              'New people sign in with the login you give them; they then appear under "Waiting for approval". '
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
        backgroundColor: CrmTokens.navy,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text('Users', style: CrmTokens.display(size: 18, color: Colors.white, w: FontWeight.w600)),
      ),
      body: body,
    );
  }

  Widget _who(AppUser u, {bool you = false}) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${u.display}${you ? '  (you)' : ''}', style: CrmTokens.body(size: 14, w: FontWeight.w600)),
        Text(u.email, style: CrmTokens.body(size: 12, color: CrmTokens.muted)),
      ]);
}
