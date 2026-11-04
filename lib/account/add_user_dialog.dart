// "Add user": an admin creates someone's login (username, email, password, role), then copies
// the details to send them. Used by Settings → Users (company admins) and the depotOS Console.
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../crm/crm_ui.dart';
import 'account.dart';

/// Shows the form and creates the account. Returns true if one was created.
Future<bool> showAddUserDialog(
  BuildContext context, {
  required List<Role> roles,
  String? companyId,
  String? companyName,
}) async {
  final created = await showDialog<_Created>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _AddUserDialog(roles: roles, companyId: companyId, companyName: companyName),
  );
  if (created == null || !context.mounted) return false;
  await showDialog<void>(context: context, builder: (_) => _CredentialsDialog(created));
  return true;
}

class _Created {
  final String username, email, password, company;
  final Role role;
  const _Created(this.username, this.email, this.password, this.role, this.company);
}

class _AddUserDialog extends StatefulWidget {
  final List<Role> roles;
  final String? companyId;
  final String? companyName;
  const _AddUserDialog({required this.roles, this.companyId, this.companyName});

  @override
  State<_AddUserDialog> createState() => _AddUserDialogState();
}

class _AddUserDialogState extends State<_AddUserDialog> {
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController(text: _newPassword());
  late Role _role = widget.roles.first;
  bool _saving = false;
  bool _show = true;
  String? _error;

  // Easy to read out or type: no 0/O or 1/l/I.
  static String _newPassword() {
    const chars = 'abcdefghjkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final r = Random.secure();
    return List.generate(10, (_) => chars[r.nextInt(chars.length)]).join();
  }

  @override
  void dispose() {
    _username.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final username = _username.text.trim();
    final email = _email.text.trim();
    final password = _password.text;
    if (username.isEmpty) return setState(() => _error = 'Enter a username');
    if (!email.contains('@')) return setState(() => _error = 'Enter a valid email');
    if (password.length < 6) return setState(() => _error = 'The password must be at least 6 characters');
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await createAccount(username: username, email: email, password: password, role: _role, companyId: widget.companyId);
      if (!mounted) return;
      Navigator.pop(
        context,
        _Created(username, email.toLowerCase(), password, _role, widget.companyName ?? Account.company?.name ?? ''),
      );
    } catch (e) {
      debugPrint('Creating account failed: $e');
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e is AccountCreationError ? e.message : "Couldn't create the account. Check your connection and try again.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Add user${widget.companyName == null ? '' : ' to ${widget.companyName}'}', style: CrmTokens.display(size: 17)),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(
              controller: _username,
              autofocus: true,
              style: CrmTokens.body(),
              decoration: crmInput('Username', icon: Icons.person_outline, hint: 'Shown on invoices and reports'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              style: CrmTokens.body(),
              decoration: crmInput('Email (their login)', icon: Icons.mail_outline),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _password,
              obscureText: !_show,
              style: CrmTokens.body(),
              decoration: crmInput('Password', icon: Icons.lock_outline).copyWith(
                suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                    tooltip: _show ? 'Hide' : 'Show',
                    onPressed: () => setState(() => _show = !_show),
                    icon: Icon(_show ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18),
                  ),
                  IconButton(
                    tooltip: 'New random password',
                    onPressed: () => setState(() => _password.text = _newPassword()),
                    icon: const Icon(Icons.refresh, size: 18),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 10),
            if (widget.roles.length > 1)
              DropdownButtonFormField<Role>(
                initialValue: _role,
                decoration: crmInput('Role'),
                items: [for (final r in widget.roles) DropdownMenuItem(value: r, child: Text(roleLabel(r), style: CrmTokens.body()))],
                onChanged: (v) => setState(() => _role = v ?? _role),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(_error!, style: CrmTokens.body(color: CrmTokens.red)),
              ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: Text('Cancel', style: CrmTokens.body())),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: CrmTokens.amber, elevation: 0),
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Creating…' : 'Create account', style: CrmTokens.body(w: FontWeight.w700, color: CrmTokens.navyDark)),
        ),
      ],
    );
  }
}

/// After creating: the details to send the person, with a Copy button.
class _CredentialsDialog extends StatelessWidget {
  final _Created c;
  const _CredentialsDialog(this.c);

  String get _message => 'Your depotOS login${c.company.isEmpty ? '' : ' for ${c.company}'}:\n'
      'Username: ${c.username}\n'
      'Email: ${c.email}\n'
      'Password: ${c.password}\n'
      'Open the app and sign in with these details.';

  @override
  Widget build(BuildContext context) {
    Widget row(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            SizedBox(width: 90, child: Text(label, style: CrmTokens.body(color: CrmTokens.muted))),
            Expanded(child: SelectableText(value, style: CrmTokens.body(w: FontWeight.w600))),
          ]),
        );
    return AlertDialog(
      title: Text('Account created', style: CrmTokens.display(size: 17)),
      content: SizedBox(
        width: 400,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Send these details to ${c.username}. The password is not shown again.',
              style: CrmTokens.body(color: CrmTokens.muted)),
          const SizedBox(height: 12),
          row('Username', c.username),
          row('Email', c.email),
          row('Password', c.password),
          row('Role', roleLabel(c.role)),
        ]),
      ),
      actions: [
        TextButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: _message));
            if (context.mounted) crmSnack(context, 'Copied. Paste it into WhatsApp or SMS.');
          },
          icon: const Icon(Icons.copy, size: 18, color: CrmTokens.navy),
          label: Text('Copy details', style: CrmTokens.body(color: CrmTokens.navy, w: FontWeight.w600)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: CrmTokens.amber, elevation: 0),
          onPressed: () => Navigator.pop(context),
          child: Text('Done', style: CrmTokens.body(w: FontWeight.w700, color: CrmTokens.navyDark)),
        ),
      ],
    );
  }
}
