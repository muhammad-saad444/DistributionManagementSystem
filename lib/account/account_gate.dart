// After sign-in: checks the user's company and role, then opens admin or booker screens
// (or explains why not: waiting for approval, disabled, company suspended).
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../Admin/admin_home.dart';
import '../AuthScreen.dart';
import '../SessionWatcher.dart';
import '../crm/crm_ui.dart';
import '../home.dart';
import '../ui/app_splash.dart';
import 'account.dart';
import 'company_setup_screen.dart';
import 'console_screen.dart';

class AccountGate extends StatefulWidget {
  final DateTime expiresAt;
  final String name; // the username typed at login, if any
  const AccountGate({super.key, required this.expiresAt, this.name = ''});

  @override
  State<AccountGate> createState() => _AccountGateState();
}

class _AccountGateState extends State<AccountGate> {
  AccountState? _state;
  Object? _error;
  bool _skippedSetup = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    setState(() {
      _state = null;
      _error = null;
    });
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return _toLogin();

    // Open straight away from what this device saved last time...
    final saved = await loadAccountFromCache(user);
    if (saved != null && mounted) setState(() => _state = saved);
    final openedAs = _shape();

    // ...then confirm with the server, and only rebuild if something actually changed
    // (switched off, role changed, company suspended).
    try {
      final state = await loadAccount(user, name: widget.name, keep: saved != null).timeout(const Duration(seconds: 30));
      if (!mounted) return;
      if (saved == null || state != saved || _shape() != openedAs) setState(() => _state = state);
    } catch (e) {
      debugPrint('Account check failed: $e');
      // Already open from the saved copy: keep working (offline is fine). Otherwise say so.
      if (saved == null && mounted) setState(() => _error = e);
    }
  }

  /// What decides which screen opens, besides the state.
  String _shape() => '${Account.isAdmin}|${Account.companyId}|${Account.company?.suspended}';

  Future<void> _toLogin() async {
    Account.clear();
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const AuthScreen()), (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    if (_error != null) {
      return _Message(
        icon: Icons.cloud_off,
        title: "Couldn't check your account",
        text: 'Check your internet connection and try again.',
        onRetry: _check,
        onSignOut: _toLogin,
      );
    }
    if (state == null) return const AppSplash();

    final Widget screen = switch (state) {
      AccountState.superAdmin => ConsoleScreen(onSignOut: _toLogin),
      AccountState.superAdminSetup => _Message(
          icon: Icons.admin_panel_settings_outlined,
          title: 'One step to become super admin',
          text: 'For safety, only the Firebase console can make an account super admin. In Firebase → Firestore, '
              'create a document in the collection "platform_admins" with this document ID:\n\n'
              '${FirebaseAuth.instance.currentUser?.uid ?? ''}\n\n'
              'Give it one field: email = $superAdminEmail. Then tap Check again.',
          onRetry: _check,
          retryLabel: 'Check again',
          onSignOut: _toLogin,
          selectable: true,
        ),
      AccountState.ready => Account.isAdmin ? AdminHome() : HomeScreen(),
      AccountState.legacyBooker => HomeScreen(),
      AccountState.needsSetup => _skippedSetup
          ? AdminHome()
          : CompanySetupScreen(
              ownerName: widget.name,
              onDone: _check,
              onSkip: () => setState(() => _skippedSetup = true),
            ),
      AccountState.pending => _Message(
          icon: Icons.hourglass_top,
          title: 'No company for this login',
          text: '${FirebaseAuth.instance.currentUser?.email ?? 'This login'} is not part of any company. '
              'Accounts are created by your company admin; sign in with the details they gave you.',
          onRetry: _check,
          retryLabel: 'Check again',
          onSignOut: _toLogin,
        ),
      AccountState.disabled => _Message(
          icon: Icons.block,
          title: 'Account switched off',
          text: 'Your company admin has switched off this account. Contact them if this is a mistake.',
          onSignOut: _toLogin,
        ),
      AccountState.suspended => _Message(
          icon: Icons.pause_circle_outline,
          title: '${Account.company?.name ?? 'Your company'} is suspended',
          text: 'Access for this company is paused. Contact depotOS support.',
          onSignOut: _toLogin,
        ),
    };
    return SessionWatcher(expiresAt: widget.expiresAt, child: screen);
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;
  final VoidCallback? onRetry;
  final String retryLabel;
  final VoidCallback onSignOut;
  final bool selectable; // lets the reader copy the text (e.g. an id to paste elsewhere)
  const _Message({
    required this.icon,
    required this.title,
    required this.text,
    this.onRetry,
    this.retryLabel = 'Try again',
    required this.onSignOut,
    this.selectable = false,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CrmTokens.bg,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 48, color: CrmTokens.navy),
              const SizedBox(height: 16),
              Text(title, textAlign: TextAlign.center, style: CrmTokens.display(size: 20)),
              const SizedBox(height: 10),
              selectable
                  ? SelectableText(text, textAlign: TextAlign.center, style: CrmTokens.body(size: 14, color: CrmTokens.muted))
                  : Text(text, textAlign: TextAlign.center, style: CrmTokens.body(size: 14, color: CrmTokens.muted)),
              const SizedBox(height: 24),
              Wrap(spacing: 10, runSpacing: 10, alignment: WrapAlignment.center, children: [
                if (onRetry != null)
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: CrmTokens.amber, elevation: 0),
                    onPressed: onRetry,
                    child: Text(retryLabel, style: CrmTokens.body(w: FontWeight.w700, color: CrmTokens.navyDark)),
                  ),
                OutlinedButton(
                  onPressed: onSignOut,
                  child: Text('Sign out', style: CrmTokens.body(color: CrmTokens.navy, w: FontWeight.w600)),
                ),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}
