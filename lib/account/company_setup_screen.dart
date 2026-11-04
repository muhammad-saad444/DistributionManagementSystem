// Shown once to the original admin: creates the company and gives everyone who has logged in a
// role. Nothing is written until they press Set up.
import 'package:flutter/material.dart';

import '../crm/crm_ui.dart';
import 'account.dart';

class CompanySetupScreen extends StatefulWidget {
  final String ownerName;
  final VoidCallback onDone;
  final VoidCallback onSkip; // carry on with the old admin panel for now
  const CompanySetupScreen({super.key, required this.ownerName, required this.onDone, required this.onSkip});

  @override
  State<CompanySetupScreen> createState() => _CompanySetupScreenState();
}

class _CompanySetupScreenState extends State<CompanySetupScreen> {
  List<SetupPerson>? _people;
  Object? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final p = await loadSetupPeople();
      if (mounted) setState(() => _people = p);
    } catch (e) {
      debugPrint('Loading people for setup failed: $e');
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await setUpCompany(_people!, ownerName: widget.ownerName.isEmpty ? 'admin' : widget.ownerName);
      if (!mounted) return;
      crmSnack(context, '$legacyCompanyName is set up');
      widget.onDone();
    } catch (e) {
      debugPrint('Company setup failed: $e');
      if (!mounted) return;
      setState(() => _saving = false);
      crmSnack(context, "Couldn't save. Check your connection and try again.", error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final people = _people;
    final included = people?.where((p) => p.include).length ?? 0;
    return Scaffold(
      backgroundColor: CrmTokens.bg,
      appBar: AppBar(
        backgroundColor: CrmTokens.navy,
        automaticallyImplyLeading: false,
        title: Text('Set up your company', style: CrmTokens.display(size: 18, color: Colors.white, w: FontWeight.w600)),
        actions: [
          TextButton(
            onPressed: _saving ? null : widget.onSkip,
            child: Text('Not now', style: CrmTokens.body(color: Colors.white, w: FontWeight.w600)),
          ),
        ],
      ),
      body: people == null
          ? Center(
              child: _error != null
                  ? OutlinedButton(onPressed: _load, child: Text('Try again', style: CrmTokens.body(color: CrmTokens.navy)))
                  : const CircularProgressIndicator(color: CrmTokens.navy),
            )
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 100),
                  children: [
                    Text('One-time step', style: CrmTokens.display(size: 18)),
                    const SizedBox(height: 6),
                    Text(
                      'The app now gives every user a company and a role instead of recognising the admin by email. '
                      'This creates "$legacyCompanyName" with you as its owner and adds the people below. '
                      'Untick anyone who no longer works for you. They can still be approved later.',
                      style: CrmTokens.body(color: CrmTokens.muted),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Admins see the admin panel. Bookers see the booking app. Until you press Set up, bookers keep '
                      'working exactly as before.',
                      style: CrmTokens.body(color: CrmTokens.muted),
                    ),
                    CrmSectionTitle('People who have logged in',
                        trailing: Text('$included of ${people.length} included', style: CrmTokens.body(size: 12, color: CrmTokens.muted))),
                    if (people.isEmpty)
                      const CrmEmpty(icon: Icons.people_outline, text: 'No one else has logged in yet.')
                    else
                      for (final p in people)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: CrmCard(
                            padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
                            child: Row(children: [
                              Checkbox(
                                value: p.include,
                                activeColor: CrmTokens.navy,
                                onChanged: (v) => setState(() => p.include = v ?? false),
                              ),
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(p.name.isEmpty ? '(no name)' : p.name, style: CrmTokens.body(w: FontWeight.w600)),
                                  Text(p.email, style: CrmTokens.body(size: 12, color: CrmTokens.muted)),
                                ]),
                              ),
                              SizedBox(
                                width: 130,
                                child: DropdownButtonFormField<Role>(
                                  initialValue: p.role,
                                  decoration: crmInput('Role'),
                                  items: [
                                    for (final r in [Role.booker, Role.admin])
                                      DropdownMenuItem(value: r, child: Text(roleLabel(r), style: CrmTokens.body())),
                                  ],
                                  onChanged: p.include ? (v) => setState(() => p.role = v ?? Role.booker) : null,
                                ),
                              ),
                            ]),
                          ),
                        ),
                  ],
                ),
              ),
            ),
      floatingActionButton: people == null
          ? null
          : FloatingActionButton.extended(
              backgroundColor: CrmTokens.amber,
              foregroundColor: CrmTokens.navyDark,
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: CrmTokens.navyDark))
                  : const Icon(Icons.check),
              label: Text('Set up with $included ${included == 1 ? 'person' : 'people'}',
                  style: CrmTokens.body(size: 13, color: CrmTokens.navyDark, w: FontWeight.w700)),
            ),
    );
  }
}
