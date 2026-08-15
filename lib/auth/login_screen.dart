import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../screens/home_screen.dart';
import '../admin/screens/admin_dashboard_screen.dart';
import '../admin/roles_service.dart';
import 'auth_service.dart';


class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl           = TextEditingController();
  final _passwordCtrl        = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();

  bool _isLogin        = true;
  bool _loading        = false;
  bool _obscure        = true;
  bool _obscureConfirm = true;
  String? _emailError;

  // ── Validation helpers ──────────────────────────────────────────────────────

  // Email: must be lowercase + valid format
  bool _isValidEmail(String email) {
    final lower = email.toLowerCase();
    if (lower.contains('..')) return false;          // no double dots
    if (lower.startsWith('.') || lower.startsWith('@')) return false; // no leading dot/@
    if (lower.contains('@.')) return false;          // no dot right after @
    return RegExp(r'^[a-z0-9._%+\-]+@[a-z0-9.\-]+\.[a-z]{2,}$')
        .hasMatch(lower);
  }

  // Password: min 8 chars, at least 1 letter, 1 number, 1 special character
  bool _isValidPassword(String password) {
    if (password.length < 8) return false;
    final hasLetter  = RegExp(r'[a-zA-Z]').hasMatch(password);
    final hasDigit   = RegExp(r'[0-9]').hasMatch(password);
    final hasSpecial = RegExp(r'[!@#\$%^&*(),.?":{}|<>_\-\+=/\\]').hasMatch(password);
    return hasLetter && hasDigit && hasSpecial;
  }

  // ignore: unused_element
  void _toggleMode() => setState(() => _isLogin = !_isLogin);

  Future<void> _handleEmailAuth() async {
    // Force email to lowercase before any checks
    final email    = _emailCtrl.text.trim().toLowerCase();
    final password = _passwordCtrl.text.trim();

    // ── Field empty check ──
    if (email.isEmpty || password.isEmpty) {
      _showSnack("Please enter email and password", Colors.orange);
      return;
    }

    // ── Email format check ──
    if (!_isValidEmail(email)) {
      _showSnack("Enter a valid email address (e.g. you@gmail.com)", Colors.orange);
      return;
    }

    // ── Password structure check ──
    if (!_isValidPassword(password)) {
      _showSnack(
        "Password must be 8+ chars with a letter, number and special character (!@#\$...)",
        Colors.orange,
      );
      return;
    }

    // ── Sign-up: confirm password check ──
    if (!_isLogin) {
      final confirm = _confirmPasswordCtrl.text.trim();
      if (confirm.isEmpty) {
        _showSnack("Please confirm your password", Colors.orange);
        return;
      }
      if (password != confirm) {
        _showSnack("Passwords do not match", Colors.redAccent);
        return;
      }
    }

    setState(() => _loading = true);
    await Future<void>.delayed(Duration.zero);

    try {
      final user = _isLogin
          ? await AuthService().signInWithEmail(email, password)
          : await AuthService().signUpWithEmail(email, password);

      if (user != null && mounted) {
        _showSnack(
          "${_isLogin ? 'Login' : 'Account created'} successful ✅",
          Colors.green,
        );
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      }
    } catch (e) {
      _showSnack(_friendlyError(e.toString()), Colors.redAccent);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _friendlyError(String e) {
    if (e.contains('user-not-found'))       return "No account found for this email.";
    if (e.contains('wrong-password'))       return "Incorrect password.";
    if (e.contains('email-already-in-use')) return "Email already registered. Please login.";
    if (e.contains('weak-password'))        return "Password must be 8+ characters with a letter, number and special character.";
    if (e.contains('invalid-email'))        return "Please enter a valid email address.";
    return "Something went wrong. Please try again.";
  }

  void _showSnack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [

              const SizedBox(height: 48),

              // ── Icon ──
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFFF3B3B).withValues(alpha: 0.1),
                ),
                child: const Icon(
                  Icons.health_and_safety_rounded,
                  color: Color(0xFFFF3B3B),
                  size: 60,
                ),
              ),

              const SizedBox(height: 24),

              const Text(
                "Welcome to CrashAid",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 8),

              const Text(
                "Emergency support, AI guidance and safety tools in one app.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54, fontSize: 14, height: 1.5),
              ),

              const SizedBox(height: 36),

              // ── Login / Sign Up toggle tabs ──
              Container(
                decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    _tabBtn("Login",   _isLogin,  () => setState(() => _isLogin = true)),
                    _tabBtn("Sign Up", !_isLogin, () => setState(() => _isLogin = false)),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // ── Email field ──
              _inputField(
                controller: _emailCtrl,
                hint: "Email address (e.g. you@gmail.com)",
                icon: Icons.email_outlined,
                keyboardType: TextInputType.emailAddress,
                errorText: _emailError,
                onChanged: (val) {
                  if (val != val.toLowerCase()) {
                    setState(() => _emailError = "Email must be in lowercase letters only");
                  } else {
                    setState(() => _emailError = null);
                  }
                },
              ),

              const SizedBox(height: 14),

              // ── Password field ──
              _inputField(
                controller: _passwordCtrl,
                hint: "Password (8+ chars, letter + number + !@#\$...)",
                icon: Icons.lock_outline_rounded,
                obscure: _obscure,
                suffix: IconButton(
                  icon: Icon(
                    _obscure ? Icons.visibility_off : Icons.visibility,
                    color: Colors.white38,
                    size: 20,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),

              // ── Confirm Password (Sign Up only) ──
              if (!_isLogin) ...[
                const SizedBox(height: 14),
                _inputField(
                  controller: _confirmPasswordCtrl,
                  hint: "Confirm password",
                  icon: Icons.lock_outline_rounded,
                  obscure: _obscureConfirm,
                  suffix: IconButton(
                    icon: Icon(
                      _obscureConfirm ? Icons.visibility_off : Icons.visibility,
                      color: Colors.white38,
                      size: 20,
                    ),
                    onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                  ),
                ),
                const SizedBox(height: 8),
                // Password rules hint
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Password must have:",
                          style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold)),
                      SizedBox(height: 4),
                      Text("• At least 8 characters",
                          style: TextStyle(color: Colors.white38, fontSize: 11)),
                      Text("• At least 1 letter (a–z or A–Z)",
                          style: TextStyle(color: Colors.white38, fontSize: 11)),
                      Text("• At least 1 number (0–9)",
                          style: TextStyle(color: Colors.white38, fontSize: 11)),
                      Text("• At least 1 special character (!@#\$%^&*...)",
                          style: TextStyle(color: Colors.white38, fontSize: 11)),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 20),

              // ── Email auth button ──
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: _loading ? null : _handleEmailAuth,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF3B3B),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    elevation: 4,
                  ),
                  child: _loading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2.5),
                        )
                      : Text(
                          _isLogin ? "Login" : "Create Account",
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold),
                        ),
                ),
              ),

              const SizedBox(height: 20),

              // ── Divider ──
              const Row(
                children: [
                  Expanded(child: Divider(color: Colors.white12)),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text("or", style: TextStyle(color: Colors.white38)),
                  ),
                  Expanded(child: Divider(color: Colors.white12)),
                ],
              ),

              const SizedBox(height: 20),

              // ── Google sign-in ──
              _loginButton(
                title: "Continue with Google",
                icon: Icons.g_mobiledata_rounded,
                color: const Color(0xFF4285F4),
                onTap: () async { 
                  final user = await AuthService().signInWithGoogle();
                  if (user != null && context.mounted) {
                    _showSnack("Login Successful ✅", Colors.green);
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (_) => const HomeScreen()),
                    );
                  }
                },
              ),

              const SizedBox(height: 14),

              // ── Guest mode ──
              _loginButton(
                title: "Continue as Guest",
                icon: Icons.person_outline,
                color: Colors.white12,
                onTap: () {
                  _showSnack("Guest Mode Enabled 👋", Colors.orange);
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => const HomeScreen()),
                  );
                },
              ),

              // ── Admin login (web only) ──
              if (kIsWeb) ...[
                const SizedBox(height: 14),
                _loginButton(
                  title: "Login as Admin",
                  icon: Icons.admin_panel_settings_rounded,
                  color: const Color(0xFF1A1A1A),
                  onTap: () async {
                    final user = await AuthService().signInWithGoogle();

                    if (user == null || !context.mounted) return;

                    try {
                      final role = await RolesService().getCurrentUserRole();

                      if (role == null) {
                        await AuthService().signOut();

                        if (context.mounted) {
                          _showSnack(
                            "Access denied: No admin role assigned.",
                            Colors.redAccent,
                          );
                        }
                        return;
                      }

                      if (context.mounted) {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (_) => AdminDashboardScreen(
                              userRole: role,
                            ),
                          ),
                        );
                      }
                    } catch (e) {
                      await AuthService().signOut();

                      if (context.mounted) {
                        _showSnack(
                          "Admin login failed: $e",
                          Colors.redAccent,
                        );
                      }
                    }
                  },
                  borderColor: Colors.white24,
                ),
              ],

              const SizedBox(height: 28),

              const Text(
                "By continuing, you agree to our Terms & Privacy Policy.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white38, fontSize: 11),
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
          ),
        ),
      ),
    );
  }

  // ── Toggle tab button ──
  Widget _tabBtn(String label, bool active, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: active ? const Color(0xFFFF3B3B) : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: active ? Colors.white : Colors.white38,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }

  // ── Text input field ──
  Widget _inputField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    bool obscure = false,
    Widget? suffix,
    void Function(String)? onChanged,
    String? errorText,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      onChanged: onChanged,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
        prefixIcon: Icon(icon, color: Colors.white38, size: 20),
        suffixIcon: suffix,
        filled: true,
        fillColor: Colors.white10,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFFF3B3B), width: 1.5),
        ),
        errorText: errorText,
        errorStyle: const TextStyle(color: Colors.orangeAccent, fontSize: 12),
      ),
    );
  }

  // ── Full-width button (Google / Guest) ──
  Widget _loginButton({
    required String title,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    Color? borderColor,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 15),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
          border: borderColor != null ? Border.all(color: borderColor) : null,
          boxShadow: borderColor == null
              ? [BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 10)]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white),
            const SizedBox(width: 10),
            Text(
              title,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}