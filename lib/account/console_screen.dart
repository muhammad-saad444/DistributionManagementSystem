// depotOS Console: the super admin's view of every company. Create companies, choose their
// modules and limits, suspend them, invite their admins, and open any company's admin panel.
import 'package:firebase_auth/firebase_auth.dart';
import 'package:an_agency/ui/app_theme.dart';
import 'package:flutter/material.dart';

import '../Admin/admin_home.dart';
import '../crm/crm_ui.dart';
import 'account.dart';
import 'add_user_dialog.dart';

class ConsoleScreen extends StatefulWidget {
  final VoidCallback onSignOut;
  const ConsoleScreen({super.key, required this.onSignOut});

  @override
  State<ConsoleScreen> createState() => _ConsoleScreenState();
}

class _ConsoleScreenState extends State<ConsoleScreen> {
  List<Company>? _companies;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final c = await loadCompanies();
      if (mounted) setState(() => _companies = c);
    } catch (e) {
      debugPrint('Console: loading companies failed: $e');
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _create() async {
    final created = await showDialog<({String id, String name})>(context: context, builder: (_) => const _NewCompanyDialog());
    if (created == null || !mounted) return;
    _load();
    // Straight on to the company admin's login.
    await showAddUserDialog(context, roles: const [Role.owner], companyId: created.id, companyName: created.name);
    _load();
  }

  Future<void> _open(Company c) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => CompanyDetailScreen(company: c)));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final companies = _companies;
    return Scaffold(
      backgroundColor: CrmTokens.bg,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Row(children: [
          const Icon(Icons.hub_outlined, color: CrmTokens.amber),
          const SizedBox(width: 10),
          Text('depotOS Console', style: CrmTokens.display(size: 18, color: AppColors.text, w: FontWeight.w600)),
        ]),
        actions: [
          IconButton(tooltip: 'Refresh', onPressed: _load, icon: const Icon(Icons.refresh, color: AppColors.text)),
          TextButton.icon(
            onPressed: widget.onSignOut,
            icon: const Icon(Icons.logout, color: AppColors.text, size: 18),
            label: Text('Sign out', style: CrmTokens.body(color: AppColors.text)),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: CrmTokens.amber,
        foregroundColor: CrmTokens.navyDark,
        onPressed: _create,
        icon: const Icon(Icons.add_business),
        label: Text('New company', style: CrmTokens.body(size: 13, color: CrmTokens.navyDark, w: FontWeight.w700)),
      ),
      body: companies == null
          ? Center(
              child: _error != null
                  ? Column(mainAxisSize: MainAxisSize.min, children: [
                      const CrmEmpty(icon: Icons.cloud_off, text: "Couldn't load companies."),
                      OutlinedButton(onPressed: _load, child: Text('Try again', style: CrmTokens.body(color: CrmTokens.navy))),
                    ])
                  : const CircularProgressIndicator(color: CrmTokens.navy),
            )
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                  children: [
                    Text('Signed in as ${FirebaseAuth.instance.currentUser?.email ?? ''} (super admin)',
                        style: CrmTokens.body(color: CrmTokens.muted)),
                    CrmSectionTitle('Companies',
                        trailing: Text('${companies.length}', style: CrmTokens.body(size: 12, color: CrmTokens.muted))),
                    if (companies.isEmpty)
                      const CrmEmpty(icon: Icons.business_outlined, text: 'No companies yet. Tap New company.')
                    else
                      for (final c in companies)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: CrmCard(
                            onTap: () => _open(c),
                            padding: const EdgeInsets.all(14),
                            child: Row(children: [
                              CircleAvatar(
                                backgroundColor: c.suspended ? CrmTokens.redBg : CrmTokens.blueBg,
                                child: Text(c.name.isEmpty ? '?' : c.name[0].toUpperCase(),
                                    style: CrmTokens.display(size: 16, color: c.suspended ? CrmTokens.red : CrmTokens.navy)),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(c.name, style: CrmTokens.body(size: 15, w: FontWeight.w600)),
                                  const SizedBox(height: 3),
                                  Text('${c.id}  ·  ${c.modules.length} of ${allModules.length} modules  ·  max ${c.maxBookers} bookers',
                                      style: CrmTokens.body(size: 12, color: CrmTokens.muted)),
                                ]),
                              ),
                              if (c.legacyData)
                                const Padding(
                                  padding: EdgeInsets.only(right: 6),
                                  child: CrmPill('Data not moved yet', color: CrmTokens.amber, background: CrmTokens.amberBg),
                                ),
                              if (c.suspended) const CrmPill('Suspended', color: CrmTokens.red, background: CrmTokens.redBg),
                              const Icon(Icons.chevron_right, color: CrmTokens.muted),
                            ]),
                          ),
                        ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _NewCompanyDialog extends StatefulWidget {
  const _NewCompanyDialog();

  @override
  State<_NewCompanyDialog> createState() => _NewCompanyDialogState();
}

class _NewCompanyDialogState extends State<_NewCompanyDialog> {
  final _name = TextEditingController();
  final _max = TextEditingController(text: '10');
  final Set<String> _modules = {...allModules};
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _max.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final id = companyIdFor(name);
    if (id.isEmpty) return setState(() => _error = 'Enter a company name');
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await createCompany(
        id: id,
        name: name,
        modules: _modules,
        maxBookers: int.tryParse(_max.text.trim()) ?? 10,
      );
      if (mounted) Navigator.pop(context, (id: id, name: name));
    } catch (e) {
      debugPrint('Creating company failed: $e');
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e is AccountCreationError ? e.message : "Couldn't create the company. Try again.";
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final id = companyIdFor(_name.text);
    return AlertDialog(
      title: Text('New company', style: CrmTokens.display(size: 18)),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(
              controller: _name,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              style: CrmTokens.body(),
              decoration: crmInput('Company name', icon: Icons.business_outlined),
            ),
            if (id.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 0, 0),
                child: Text('Id: $id', style: CrmTokens.body(size: 11.5, color: CrmTokens.muted)),
              ),
            const SizedBox(height: 10),
            TextField(
              controller: _max,
              keyboardType: TextInputType.number,
              style: CrmTokens.body(),
              decoration: crmInput('Max bookers', icon: Icons.people_outline),
            ),
            const CrmSectionTitle('Modules'),
            for (final m in allModules)
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                activeColor: CrmTokens.navy,
                value: _modules.contains(m),
                onChanged: (v) => setState(() => v == true ? _modules.add(m) : _modules.remove(m)),
                title: Text(moduleLabel(m), style: CrmTokens.body()),
              ),
            if (_error != null) Text(_error!, style: CrmTokens.body(color: CrmTokens.red)),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: Text('Cancel', style: CrmTokens.body())),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: CrmTokens.amber, elevation: 0),
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Creating…' : 'Create', style: CrmTokens.body(w: FontWeight.w700, color: CrmTokens.navyDark)),
        ),
      ],
    );
  }
}

/// One company: modules, limits, status, people and invitations, and a way into its admin panel.
class CompanyDetailScreen extends StatefulWidget {
  final Company company;
  const CompanyDetailScreen({super.key, required this.company});

  @override
  State<CompanyDetailScreen> createState() => _CompanyDetailScreenState();
}

class _CompanyDetailScreenState extends State<CompanyDetailScreen> {
  late Company _c = widget.company;
  late final Set<String> _modules = {..._c.modules};
  late final _max = TextEditingController(text: '${_c.maxBookers}');
  List<AppUser>? _users;
  bool _saving = false;
  String? _moveProgress;

  @override
  void initState() {
    super.initState();
    _loadPeople();
  }

  @override
  void dispose() {
    _max.dispose();
    super.dispose();
  }

  Future<void> _reloadCompany() async {
    final all = await loadCompanies();
    final c = all.where((x) => x.id == _c.id).firstOrNull;
    if (c != null && mounted) setState(() => _c = c);
  }

  Future<void> _loadPeople() async {
    try {
      final users = await loadUsersOf(_c.id);
      if (mounted) setState(() => _users = users);
    } catch (e) {
      debugPrint('Console: loading people failed: $e');
    }
  }

  Future<void> _saveSettings() async {
    setState(() => _saving = true);
    try {
      await updateCompany(_c.id, modules: _modules, maxBookers: int.tryParse(_max.text.trim()) ?? _c.maxBookers);
      await _reloadCompany();
      if (mounted) crmSnack(context, 'Saved');
    } catch (e) {
      if (mounted) crmSnack(context, "Couldn't save. Try again.", error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _toggleSuspend() async {
    final suspend = !_c.suspended;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(suspend ? 'Suspend ${_c.name}?' : 'Reactivate ${_c.name}?', style: CrmTokens.display(size: 17)),
        content: Text(
          suspend ? 'Nobody in this company can open the app until you reactivate it. Their data is kept.' : 'Its people can use the app again.',
          style: CrmTokens.body(),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: Text('Cancel', style: CrmTokens.body())),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: suspend ? CrmTokens.red : CrmTokens.amber, elevation: 0),
            onPressed: () => Navigator.pop(d, true),
            child: Text(suspend ? 'Suspend' : 'Reactivate',
                style: CrmTokens.body(w: FontWeight.w700, color: suspend ? Colors.white : CrmTokens.navyDark)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await updateCompany(_c.id, suspended: suspend);
      await _reloadCompany();
    } catch (_) {
      if (mounted) crmSnack(context, "Couldn't save. Try again.", error: true);
    }
  }

  Future<void> _addUser() async {
    if (await showAddUserDialog(context, roles: Role.values, companyId: _c.id, companyName: _c.name)) _loadPeople();
  }

  Future<void> _resetPassword(AppUser u) async {
    try {
      await sendPasswordReset(u.email);
      if (mounted) crmSnack(context, 'Password reset email sent to ${u.email}');
    } catch (_) {
      if (mounted) crmSnack(context, "Couldn't send the email. Try again.", error: true);
    }
  }

  Future<void> _moveData() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text("Move ${_c.name}'s data into its own section?", style: CrmTokens.display(size: 17)),
        content: Text(
          'This copies every invoice, product, customer, khata entry and all other records from the shared '
          'collections into this company, checks every one arrived, then switches the company over.\n\n'
          'Before you do this, install the new app on every booker\'s phone: older versions can\'t see the moved '
          'data. The shared copy is kept as a backup that only you can read.',
          style: CrmTokens.body(),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: Text('Cancel', style: CrmTokens.body())),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: CrmTokens.amber, elevation: 0),
            onPressed: () => Navigator.pop(d, true),
            child: Text('Move data', style: CrmTokens.body(w: FontWeight.w700, color: CrmTokens.navyDark)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _moveProgress = 'Starting…');
    try {
      final counts = await moveLegacyData(_c.id, progress: (s) {
        if (mounted) setState(() => _moveProgress = s);
      });
      final total = counts.values.fold<int>(0, (a, b) => a + b);
      await _reloadCompany();
      if (mounted) crmSnack(context, 'Moved $total records. ${_c.name} now uses its own data.');
    } catch (e) {
      debugPrint('Moving data failed: $e');
      if (mounted) crmSnack(context, 'Move stopped: ${e is StateError ? e.message : e}. Nothing was switched over; you can run it again.', error: true);
    } finally {
      if (mounted) setState(() => _moveProgress = null);
    }
  }

  void _openAdminPanel() {
    Account.openCompany(_c);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Column(children: [
          Material(
            color: CrmTokens.amber,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Row(children: [
                  const Icon(Icons.visibility_outlined, size: 18, color: CrmTokens.navyDark),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Super admin: viewing ${_c.name}',
                        style: CrmTokens.body(w: FontWeight.w700, color: CrmTokens.navyDark)),
                  ),
                  Builder(
                    builder: (ctx) => TextButton.icon(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.arrow_back, size: 18, color: CrmTokens.navyDark),
                      label: Text('Back to console', style: CrmTokens.body(w: FontWeight.w700, color: CrmTokens.navyDark)),
                    ),
                  ),
                ]),
              ),
            ),
          ),
          Expanded(child: AdminHome()),
        ]),
      ),
    ).then((_) => Account.openCompany(_c)); // stay pointed at this company while on its page
  }

  @override
  Widget build(BuildContext context) {
    final users = _users;
    return Scaffold(
      backgroundColor: CrmTokens.bg,
      appBar: AppBar(
        title: Text(_c.name, style: CrmTokens.display(size: 18, color: AppColors.text, w: FontWeight.w600)),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
            children: [
              Wrap(spacing: 8, runSpacing: 8, children: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: CrmTokens.amber, elevation: 0),
                  onPressed: _openAdminPanel,
                  icon: const Icon(Icons.dashboard_outlined, color: CrmTokens.navyDark, size: 18),
                  label: Text('Open admin panel', style: CrmTokens.body(color: CrmTokens.navyDark, w: FontWeight.w700)),
                ),
                OutlinedButton.icon(
                  onPressed: _toggleSuspend,
                  icon: Icon(_c.suspended ? Icons.play_arrow : Icons.pause, size: 18, color: _c.suspended ? CrmTokens.green : CrmTokens.red),
                  label: Text(_c.suspended ? 'Reactivate' : 'Suspend',
                      style: CrmTokens.body(color: _c.suspended ? CrmTokens.green : CrmTokens.red, w: FontWeight.w600)),
                ),
              ]),
              if (_c.legacyData) ...[
                const SizedBox(height: 14),
                CrmCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text("This company's data is still in the shared collections", style: CrmTokens.body(size: 14, w: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(
                      'It works, but it is not separated yet. Move it into this company once every booker has the new app.',
                      style: CrmTokens.body(color: CrmTokens.muted),
                    ),
                    const SizedBox(height: 10),
                    if (_moveProgress != null)
                      Row(children: [
                        const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: CrmTokens.navy)),
                        const SizedBox(width: 10),
                        Expanded(child: Text(_moveProgress!, style: CrmTokens.body(color: CrmTokens.muted))),
                      ])
                    else
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: CrmTokens.navy, elevation: 0),
                        onPressed: _moveData,
                        icon: const Icon(Icons.drive_file_move_outline, color: Colors.white, size: 18),
                        label: Text('Move data into ${_c.name}', style: CrmTokens.body(color: Colors.white, w: FontWeight.w700)),
                      ),
                  ]),
                ),
              ],
              const CrmSectionTitle('Modules'),
              CrmCard(
                padding: const EdgeInsets.fromLTRB(8, 4, 12, 12),
                child: Column(children: [
                  for (final m in allModules)
                    CheckboxListTile(
                      dense: true,
                      activeColor: CrmTokens.navy,
                      value: _modules.contains(m),
                      onChanged: (v) => setState(() => v == true ? _modules.add(m) : _modules.remove(m)),
                      title: Text(moduleLabel(m), style: CrmTokens.body()),
                    ),
                  Row(children: [
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 160,
                      child: TextField(
                        controller: _max,
                        keyboardType: TextInputType.number,
                        style: CrmTokens.body(),
                        decoration: crmInput('Max bookers'),
                      ),
                    ),
                    const Spacer(),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: CrmTokens.amber, elevation: 0),
                      onPressed: _saving ? null : _saveSettings,
                      child: Text('Save', style: CrmTokens.body(w: FontWeight.w700, color: CrmTokens.navyDark)),
                    ),
                  ]),
                ]),
              ),
              CrmSectionTitle('People',
                  trailing: TextButton.icon(
                    onPressed: _addUser,
                    icon: const Icon(Icons.person_add_alt, size: 18, color: CrmTokens.navy),
                    label: Text('Add user', style: CrmTokens.body(color: CrmTokens.navy, w: FontWeight.w600)),
                  )),
              if (users == null)
                const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator(color: CrmTokens.navy)))
              else ...[
                if (users.isEmpty)
                  const CrmEmpty(icon: Icons.people_outline, text: "Nobody yet. Add the company admin's login (role: Owner)."),
                for (final u in users)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: CrmCard(
                      padding: const EdgeInsets.all(12),
                      child: Row(children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(u.display, style: CrmTokens.body(w: FontWeight.w600)),
                            Text(u.email, style: CrmTokens.body(size: 12, color: CrmTokens.muted)),
                          ]),
                        ),
                        if (!u.isActive) const CrmPill('Switched off', color: CrmTokens.red, background: CrmTokens.redBg),
                        const SizedBox(width: 6),
                        CrmPill(roleLabel(u.role), color: CrmTokens.navy, background: CrmTokens.blueBg),
                        IconButton(
                          tooltip: 'Send password reset email',
                          onPressed: () => _resetPassword(u),
                          icon: const Icon(Icons.lock_reset, size: 18, color: CrmTokens.muted),
                        ),
                      ]),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
