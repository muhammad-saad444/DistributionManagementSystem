import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'account/account_gate.dart';

// ---------------------------------------------------------------------------
// Design tokens — keep every color/type choice here so the look stays
// consistent if you reuse it elsewhere in the app.
// ---------------------------------------------------------------------------
class _Tokens {
  static const navyDark = Color(0xFF131C31); // brand panel background
  static const navySlate = Color(0xFF24345C); // secondary brand surface
  static const amber = Color(0xFFE8973A); // accent / primary action
  static const bg = Color(0xFFF5F6F8); // form panel background
  static const surface = Color(0xFFFFFFFF);
  static const textPrimary = Color(0xFF101828);
  static const textSecondary = Color(0xFF667085);
  static const border = Color(0xFFE4E7EC);
  static const error = Color(0xFFD92D20);

  static TextStyle display({double size = 28, Color? color, FontWeight w = FontWeight.w600}) =>
      GoogleFonts.sora(fontSize: size, fontWeight: w, color: color ?? textPrimary, height: 1.2);

  static TextStyle body({double size = 14, Color? color, FontWeight w = FontWeight.w400}) =>
      GoogleFonts.inter(fontSize: size, fontWeight: w, color: color ?? textPrimary);
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _auth = FirebaseAuth.instance;

  // How long a login lasts before the user is signed out (one full day).
  static const Duration _sessionDuration = Duration(hours: 24);
  static const String _appName = 'Distribution Management System';

  bool hidePassword = true;
  bool isLoading = false;
  String username = '';
  String email = '';
  String password = '';

  bool signingUp = false; // creating a new account (for someone who was invited by email)

  void _togglePasswordVisibility() {
    setState(() => hidePassword = !hidePassword);
  }

  void _toggleSignUp() {
    setState(() => signingUp = !signingUp);
  }

  Future<void> _submit() async {
    final isValid = _formKey.currentState!.validate();
    if (!isValid) return;
    _formKey.currentState!.save();

    setState(() => isLoading = true);

    try {
      if (signingUp) {
        await _auth.createUserWithEmailAndPassword(email: email, password: password);
      } else {
        await _auth.signInWithEmailAndPassword(email: email, password: password);
      }
      final user = _auth.currentUser!;
      final now = DateTime.now();
      final expiresAt = now.add(_sessionDuration);

      try {
        if (username.isNotEmpty && user.displayName != username) {
          await user.updateDisplayName(username);
          await user.reload();
        }
      } catch (_) {}

      final sessionRef =
      FirebaseFirestore.instance.collection('sessions').doc(user.uid);

      await sessionRef.set({
        'uid': user.uid,
        'email': user.email,
        'username': username,
        'startedAt': FieldValue.serverTimestamp(),
        'expiresAt': Timestamp.fromDate(expiresAt),
      }, SetOptions(merge: true));

      if (!mounted) return;

      // Admin or booker screens are decided by the user's role in their company.
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => AccountGate(expiresAt: expiresAt, name: username)),
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: _Tokens.navyDark,
          content: Text('Login successful', style: _Tokens.body(color: Colors.white)),
        ),
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      _showError(e.message ?? 'Authentication error');
    } catch (e) {
      if (!mounted) return;
      _showError('Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: _Tokens.error,
        content: Text(message, style: _Tokens.body(color: Colors.white)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _Tokens.bg,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 860;
          if (isWide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 5, child: _BrandPanel(appName: _appName)),
                Expanded(
                  flex: 6,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 400),
                      child: _LoginForm(state: this),
                    ),
                  ),
                ),
              ],
            );
          }
          return SingleChildScrollView(
            child: Column(
              children: [
                _BrandPanel(appName: _appName, compact: true),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
                  child: _LoginForm(state: this),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Left brand panel — dark navy, with a small route/network motif fitting a
// distribution system. Collapses to a compact banner on narrow screens.
// ---------------------------------------------------------------------------
class _BrandPanel extends StatelessWidget {
  final String appName;
  final bool compact;

  const _BrandPanel({required this.appName, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: compact ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: _Tokens.amber,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.route_outlined, color: _Tokens.navyDark, size: 24),
        ),
        SizedBox(height: compact ? 16 : 28),
        Text(
          appName,
          textAlign: compact ? TextAlign.center : TextAlign.start,
          style: _Tokens.display(
            size: compact ? 20 : 30,
            color: Colors.white,
          ),
        ),
        if (!compact) ...[
          const SizedBox(height: 12),
          Text(
            'Track shipments, manage inventory, and coordinate\nyour network from one dashboard.',
            style: _Tokens.body(size: 14, color: Colors.white.withOpacity(0.65)),
          ),
          const SizedBox(height: 40),
          const _RouteMotif(),
        ],
      ],
    );

    if (compact) {
      return Container(
        width: double.infinity,
        color: _Tokens.navyDark,
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
        child: content,
      );
    }

    return Container(
      color: _Tokens.navyDark,
      padding: const EdgeInsets.fromLTRB(56, 64, 40, 64),
      child: content,
    );
  }
}

// A small decorative motif — dots joined by lines, suggesting distribution
// routes/nodes. Purely visual, no interaction.
class _RouteMotif extends StatelessWidget {
  const _RouteMotif();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      height: 90,
      child: CustomPaint(
        painter: _RouteMotifPainter(),
      ),
    );
  }
}

class _RouteMotifPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = Colors.white.withOpacity(0.18)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final nodePaint = Paint()..color = _Tokens.amber;
    final nodeSmallPaint = Paint()..color = Colors.white.withOpacity(0.4);

    final points = [
      Offset(8, 70),
      Offset(70, 20),
      Offset(140, 55),
      Offset(212, 10),
    ];

    final path = Path()..moveTo(points[0].dx, points[0].dy);
    for (final p in points.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path, linePaint);

    for (var i = 0; i < points.length; i++) {
      canvas.drawCircle(points[i], i == points.length - 1 ? 5 : 3.5,
          i == points.length - 1 ? nodePaint : nodeSmallPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ---------------------------------------------------------------------------
// Right form panel
// ---------------------------------------------------------------------------
class _LoginForm extends StatelessWidget {
  final _AuthScreenState state;

  const _LoginForm({required this.state});

  InputDecoration _decoration({required String label, required IconData icon, Widget? suffix}) {
    return InputDecoration(
      labelText: label,
      labelStyle: _Tokens.body(color: _Tokens.textSecondary),
      prefixIcon: Icon(icon, color: _Tokens.textSecondary, size: 20),
      suffixIcon: suffix,
      filled: true,
      fillColor: _Tokens.bg,
      contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _Tokens.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _Tokens.amber, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _Tokens.error),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Form(
        key: state._formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(state.signingUp ? 'Create account' : 'Sign in', style: _Tokens.display(size: 24)),
            const SizedBox(height: 6),
            Text(
              state.signingUp
                  ? 'Use the email your company admin invited. You will join their company straight away.'
                  : 'Enter your details to access your dashboard.',
              style: _Tokens.body(color: _Tokens.textSecondary),
            ),
            const SizedBox(height: 28),
            TextFormField(
              style: _Tokens.body(),
              decoration: _decoration(label: 'Username', icon: Icons.person_outline),
              validator: (v) =>
              (v != null && v.trim().isNotEmpty) ? null : 'Enter your username',
              onSaved: (v) => state.username = v!.trim(),
            ),
            const SizedBox(height: 16),
            TextFormField(
              style: _Tokens.body(),
              decoration: _decoration(label: 'Email', icon: Icons.mail_outline),
              keyboardType: TextInputType.emailAddress,
              validator: (v) => (v != null && v.contains('@')) ? null : 'Enter a valid email',
              onSaved: (v) => state.email = v!.trim(),
            ),
            const SizedBox(height: 16),
            TextFormField(
              obscureText: state.hidePassword,
              style: _Tokens.body(),
              decoration: _decoration(
                label: 'Password',
                icon: Icons.lock_outline,
                suffix: IconButton(
                  icon: Icon(
                    state.hidePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                    color: _Tokens.textSecondary,
                    size: 20,
                  ),
                  onPressed: state._togglePasswordVisibility,
                ),
              ),
              validator: (v) => (v != null && v.length >= 6) ? null : 'Min 6 characters',
              onSaved: (v) => state.password = v!.trim(),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: state.isLoading ? null : state._submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _Tokens.amber,
                  disabledBackgroundColor: _Tokens.amber.withOpacity(0.6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
                child: state.isLoading
                    ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.4, color: _Tokens.navyDark),
                )
                    : Text(
                  state.signingUp ? 'Create account' : 'Login',
                  style: _Tokens.body(size: 15, w: FontWeight.w600, color: _Tokens.navyDark),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: TextButton(
                onPressed: state.isLoading ? null : state._toggleSignUp,
                child: Text(
                  state.signingUp ? 'Already have an account? Sign in' : 'Invited? Create an account',
                  style: _Tokens.body(color: _Tokens.navySlate, w: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}