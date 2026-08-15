import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'admin_login_screen.dart';
import 'roles_service.dart';
import 'screens/admin_dashboard_screen.dart';

class AdminGuard extends StatelessWidget {
  const AdminGuard({super.key});

  @override
  Widget build(BuildContext context) {
    // Block access on mobile app (admin portal is web-only)
    if (!kIsWeb) {
      return const Scaffold(
        backgroundColor: Color(0xFF0A0A0A),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.computer, color: Colors.white38, size: 48),
              SizedBox(height: 16),
              Text('Admin portal is web-only.',
                  style: TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      );
    }

    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Color(0xFF0A0A0A),
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Colors.redAccent),
                  SizedBox(height: 16),
                  Text('Verifying admin access…',
                      style: TextStyle(color: Colors.grey, fontSize: 13)),
                ],
              ),
            ),
          );
        }

        final user = snapshot.data;

        // Not logged in → show login
        if (user == null) return const AdminLoginScreen();

        // Look up this user's admin role from Firestore.
        return FutureBuilder<String?>(
          future: RolesService().getCurrentUserRole(),
          builder: (context, roleSnap) {
            if (roleSnap.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                backgroundColor: Color(0xFF0A0A0A),
                body: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: Colors.redAccent),
                      SizedBox(height: 16),
                      Text('Verifying admin access…',
                          style: TextStyle(color: Colors.grey, fontSize: 13)),
                    ],
                  ),
                ),
              );
            }

            final role = roleSnap.data;

            // Logged in but not an admin → show access denied
            if (role == null) {
              return _accessDenied(user.email);
            }

            // ✅ Admin verified → show dashboard scoped to their role
            return AdminDashboardScreen(userRole: role);
          },
        );
      },
    );
  }

  Widget _accessDenied(String? email) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: Center(
        child: Container(
          padding: const EdgeInsets.all(36),
          constraints: const BoxConstraints(maxWidth: 400),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.block, color: Colors.redAccent, size: 64),
              const SizedBox(height: 16),
              const Text('Access Denied',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(
                '${email ?? 'This account'} is not authorized as an admin.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () => FirebaseAuth.instance.signOut(),
                icon: const Icon(Icons.logout),
                label: const Text('Sign Out'),
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
