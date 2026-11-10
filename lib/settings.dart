import 'package:flutter/material.dart';
import 'package:an_agency/ui/app_theme.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'AuthScreen.dart'; // <-- Replace with your actual login/auth screen import
import 'account/account.dart';
import 'account/users_screen.dart';

// Delete this block and import your shared _Tokens file if you already have one.
class _Tokens {
  static const navy = AppColors.navy;
  static const navyDark = AppColors.navyDark;
  static const amber = AppColors.amber;
  static const bg = AppColors.bg;
  static const border = AppColors.border;
  static const textDark = AppColors.text;
  static const muted = AppColors.muted;
  static const error = AppColors.red;
}

class AdminSettingsScreen extends StatefulWidget {
  const AdminSettingsScreen({super.key});

  @override
  State<AdminSettingsScreen> createState() => _AdminSettingsScreenState();
}

class _AdminSettingsScreenState extends State<AdminSettingsScreen> {
  bool _isDarkMode = false;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  Map<String, dynamic>? _adminData;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchAdminData();
  }

  Future<void> _fetchAdminData() async {
    try {
      final user = _auth.currentUser;
      if (user != null) {
        final doc =
        await companyCol('sessions').doc(user.uid).get();
        if (doc.exists) {
          setState(() {
            _adminData = doc.data();
            _loading = false;
          });
        } else {
          setState(() => _loading = false);
        }
      } else {
        setState(() => _loading = false);
      }
    } catch (e) {
      setState(() => _loading = false);
      debugPrint('Error fetching admin data: $e');
    }
  }

  Future<void> _logout(BuildContext context) async {
    try {
      Account.clear();
      await _auth.signOut();
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const AuthScreen()),
            (route) => false,
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Logout failed: $e', style: GoogleFonts.sora()),
          backgroundColor: _Tokens.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final surface = _isDarkMode ? const Color(0xFF1C2333) : Colors.white;
    final scaffoldBg = _isDarkMode ? const Color(0xFF10151F) : _Tokens.bg;
    final primaryText = _isDarkMode ? Colors.white : _Tokens.textDark;
    final secondaryText = _isDarkMode ? Colors.grey[400] : _Tokens.muted;

    return Scaffold(
      backgroundColor: scaffoldBg,
      appBar: AppBar(
        title: Text(
          'Settings',
          style: GoogleFonts.sora(fontWeight: FontWeight.w600, fontSize: 18, color: AppColors.text),
        ),
        elevation: 0,
        centerTitle: false,
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: _Tokens.navy))
          : SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildAdminProfileCard(surface, primaryText, secondaryText),
            const SizedBox(height: 16),
            _buildGeneralSettings(surface, primaryText, secondaryText),
            const SizedBox(height: 16),
            _buildLogoutSection(context, surface, primaryText),
          ],
        ),
      ),
    );
  }

  Widget _card({required Widget child, required Color surface}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _isDarkMode ? Colors.white.withOpacity(0.06) : _Tokens.border),
        boxShadow: _isDarkMode
            ? []
            : [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildAdminProfileCard(Color surface, Color primaryText, Color? secondaryText) {
    final username = _adminData?['username'] ?? Account.user?.display ?? 'Admin';
    final email = _adminData?['email'] ?? _auth.currentUser?.email ?? '';
    final role = Account.user == null ? '' : '${roleLabel(Account.user!.role)} · ${Account.company?.name ?? ''}';

    return _card(
      surface: surface,
      child: Row(
        children: [
          CircleAvatar(
            radius: 32,
            backgroundColor: _Tokens.amber,
            child: Icon(Icons.admin_panel_settings, color: _Tokens.navyDark, size: 32),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                username,
                style: GoogleFonts.sora(fontSize: 17, fontWeight: FontWeight.w700, color: primaryText),
              ),
              const SizedBox(height: 4),
              Text(
                email,
                style: GoogleFonts.sora(fontSize: 13.5, color: secondaryText),
              ),
              if (role.isNotEmpty)
                Text(role, style: GoogleFonts.sora(fontSize: 12.5, color: secondaryText)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGeneralSettings(Color surface, Color primaryText, Color? secondaryText) {
    return _card(
      surface: surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'General Settings',
            style: GoogleFonts.sora(fontSize: 15, fontWeight: FontWeight.w700, color: primaryText),
          ),
          Divider(height: 24, color: _isDarkMode ? Colors.white.withOpacity(0.08) : _Tokens.border),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _isDarkMode,
            activeColor: _Tokens.amber,
            title: Text('Dark Mode', style: GoogleFonts.sora(color: primaryText, fontSize: 14.5)),
            secondary: Icon(Icons.dark_mode_outlined, color: _Tokens.navy),
            onChanged: (value) {
              setState(() => _isDarkMode = value);
            },
          ),
          if (Account.isAdmin)
            _settingsRow(
              icon: Icons.manage_accounts_outlined,
              label: 'Users',
              primaryText: primaryText,
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const UsersScreen())),
            ),
          _settingsRow(
            icon: Icons.lock_outline,
            label: 'Change Password',
            primaryText: primaryText,
            onTap: () => _snack('Change Password coming soon!'),
          ),
          _settingsRow(
            icon: Icons.notifications_active_outlined,
            label: 'Notifications',
            primaryText: primaryText,
            onTap: () => _snack('Notification settings coming soon!'),
          ),
        ],
      ),
    );
  }

  Widget _settingsRow({
    required IconData icon,
    required String label,
    required Color primaryText,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: _Tokens.navy),
      title: Text(label, style: GoogleFonts.sora(color: primaryText, fontSize: 14.5)),
      trailing: Icon(Icons.arrow_forward_ios, size: 15, color: _Tokens.muted),
      onTap: onTap,
    );
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.sora()),
        backgroundColor: _Tokens.navy,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Widget _buildLogoutSection(BuildContext context, Color surface, Color primaryText) {
    return _card(
      surface: surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Account',
            style: GoogleFonts.sora(fontSize: 15, fontWeight: FontWeight.w700, color: primaryText),
          ),
          Divider(height: 24, color: _isDarkMode ? Colors.white.withOpacity(0.08) : _Tokens.border),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.logout, color: _Tokens.error),
            title: Text(
              'Logout',
              style: GoogleFonts.sora(fontSize: 15, fontWeight: FontWeight.w600, color: _Tokens.error),
            ),
            onTap: () {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: surface,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  title: Text(
                    'Confirm Logout',
                    style: GoogleFonts.sora(fontWeight: FontWeight.w700, color: primaryText),
                  ),
                  content: Text(
                    'Are you sure you want to log out of your admin account?',
                    style: GoogleFonts.sora(color: primaryText),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text('Cancel', style: GoogleFonts.sora(color: _Tokens.muted)),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _logout(context);
                      },
                      child: Text(
                        'Logout',
                        style: GoogleFonts.sora(color: _Tokens.error, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}