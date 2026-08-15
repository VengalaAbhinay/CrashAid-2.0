import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../auth/auth_service.dart';

class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({super.key});

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  bool _loading = false;
  bool _showEmailForm = false;
  bool _obscurePassword = true;
  String? _error;

  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _loginWithGoogle() async {
    setState(() { _loading = true; _error = null; });
    try {
      final user = await AuthService().signInWithGoogle();
      if (user == null && mounted) {
        setState(() => _error = 'Sign-in cancelled or failed. Please try again.');
      }
    } catch (e) {
      setState(() => _error = 'Sign-in error: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loginWithEmail() async {
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text;
    if (email.isEmpty || pass.isEmpty) {
      setState(() => _error = 'Please enter both email and password.');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email, password: pass);
      // AdminGuard will route to dashboard if email is in kAdminRoles
    } on FirebaseAuthException catch (e) {
      setState(() => _error = switch (e.code) {
        'user-not-found' => 'No admin account found for that email.',
        'wrong-password' => 'Incorrect password.',
        'invalid-email' => 'Invalid email address.',
        'too-many-requests' => 'Too many attempts. Please wait.',
        _ => 'Login failed: ${e.message}',
      });
    } catch (e) {
      setState(() => _error = 'Error: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: Center(
        child: SingleChildScrollView(
          child: Container(
            width: 420,
            margin: const EdgeInsets.all(24),
            padding: const EdgeInsets.all(36),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
              boxShadow: [
                BoxShadow(
                  color: Colors.redAccent.withValues(alpha: 0.08),
                  blurRadius: 60,
                  spreadRadius: 8,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Logo ──────────────────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.redAccent.withValues(alpha: 0.12),
                    border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
                  ),
                  child: const Icon(Icons.admin_panel_settings_rounded,
                      color: Colors.redAccent, size: 44),
                ),
                const SizedBox(height: 20),
                const Text('CrashAid Admin',
                    style: TextStyle(color: Colors.white, fontSize: 26,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                const Text('Emergency Response Dashboard',
                    style: TextStyle(color: Colors.grey, fontSize: 13)),
                const SizedBox(height: 32),

                if (!_showEmailForm) ...[
                  // ── Google Sign-In button ───────────────────────────
                  _GoogleButton(loading: _loading, onPressed: _loginWithGoogle),
                  const SizedBox(height: 16),
                  _OrDivider(),
                  const SizedBox(height: 16),
                  // Toggle to email form
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _loading ? null : () => setState(() => _showEmailForm = true),
                      icon: const Icon(Icons.email_outlined, size: 18),
                      label: const Text('Sign in with Email'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: const BorderSide(color: Colors.white24),
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ] else ...[
                  // ── Email / Password form ───────────────────────────
                  _LabeledField(
                    label: 'Email',
                    controller: _emailCtrl,
                    hint: 'admin@crashaid.com',
                    icon: Icons.email_outlined,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 12),
                  _LabeledField(
                    label: 'Password',
                    controller: _passCtrl,
                    hint: '••••••••',
                    icon: Icons.lock_outline,
                    obscureText: _obscurePassword,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _loginWithEmail(),
                    trailing: IconButton(
                      icon: Icon(
                        _obscurePassword ? Icons.visibility_off : Icons.visibility,
                        color: Colors.white38, size: 18,
                      ),
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _loading ? null : _loginWithEmail,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        disabledBackgroundColor: Colors.redAccent.withValues(alpha: 0.4),
                      ),
                      child: _loading
                          ? const SizedBox(
                              width: 20, height: 20,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2),
                            )
                          : const Text('Sign In',
                              style: TextStyle(fontSize: 15,
                                  fontWeight: FontWeight.w600, color: Colors.white)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: () => setState(() {
                      _showEmailForm = false;
                      _error = null;
                    }),
                    icon: const Icon(Icons.arrow_back, size: 14),
                    label: const Text('Back to Google Sign-In'),
                    style: TextButton.styleFrom(foregroundColor: Colors.grey),
                  ),
                ],

                // ── Error banner ──────────────────────────────────────
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline,
                            color: Colors.redAccent, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(_error!,
                              style: const TextStyle(
                                  color: Colors.redAccent, fontSize: 12)),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 24),
                const Divider(color: Colors.white12),
                const SizedBox(height: 12),
                const Text(
                  'Access is restricted to authorized admins only.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white24, fontSize: 11),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Subwidgets ────────────────────────────────────────────────────────────────

class _GoogleButton extends StatelessWidget {
  final bool loading;
  final VoidCallback onPressed;
  const _GoogleButton({required this.loading, required this.onPressed});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: loading ? null : onPressed,
          icon: loading
              ? const SizedBox(
                  width: 20, height: 20,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2),
                )
              : Image.network(
                  'https://www.gstatic.com/firebasejs/ui/2.0.0/images/auth/google.svg',
                  width: 20, height: 20,
                  errorBuilder: (_, __, ___) =>
                      const Icon(Icons.login, color: Colors.white, size: 20),
                ),
          label: Text(loading ? 'Signing in…' : 'Continue with Google',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600,
                  color: Colors.white)),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF4285F4),
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            disabledBackgroundColor: const Color(0xFF4285F4).withValues(alpha: 0.5),
          ),
        ),
      );
}

class _OrDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Row(children: const [
        Expanded(child: Divider(color: Colors.white12)),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: Text('OR', style: TextStyle(color: Colors.white24, fontSize: 12)),
        ),
        Expanded(child: Divider(color: Colors.white12)),
      ]);
}

class _LabeledField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final Widget? trailing;

  const _LabeledField({
    required this.label,
    required this.controller,
    required this.hint,
    required this.icon,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.onSubmitted,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          obscureText: obscureText,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          onSubmitted: onSubmitted,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Colors.white24),
            prefixIcon: Icon(icon, color: Colors.white38, size: 18),
            suffixIcon: trailing,
            filled: true,
            fillColor: const Color(0xFF111111),
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Colors.white12),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Colors.white12),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}
