import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

class AuthService {
  final _auth = FirebaseAuth.instance;

  // ── Writes / updates user doc in Firestore so admin dashboard shows it ──
  static Future<void> _saveUserToFirestore(User user) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final name = prefs.getString('name') ??
          user.displayName ??
          user.email?.split('@').first ??
          'CrashAid User';
      final phone =
          prefs.getString('phone') ?? user.phoneNumber ?? '';

      final ref = FirebaseFirestore.instance.collection('users').doc(user.uid);
      final snap = await ref.get();

      if (!snap.exists) {
        // New user — create document
        await ref.set({
          'uid': user.uid,
          'name': name,
          'phone': phone,
          'email': user.email ?? '',
          'createdAt': FieldValue.serverTimestamp(),
          'lastLoginAt': FieldValue.serverTimestamp(),
        });
        debugPrint('✅ AuthService: new user saved to Firestore — ${user.uid}');
      } else {
        // Existing user — just update last login
        await ref.update({
          'lastLoginAt': FieldValue.serverTimestamp(),
          // Refresh name/phone in case profile was updated
          if (name.isNotEmpty && name != 'CrashAid User') 'name': name,
          if (phone.isNotEmpty) 'phone': phone,
        });
        debugPrint('✅ AuthService: user login updated — ${user.uid}');
      }
    } catch (e) {
      debugPrint('🔴 AuthService: _saveUserToFirestore failed — $e');
    }
  }

  // ── Email sign up ──
  Future<User?> signUpWithEmail(String email, String password) async {
    final result = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    if (result.user != null) {
      await _saveUserToFirestore(result.user!);
    }
    return result.user;
  }

  // ── Email sign in ──
  Future<User?> signInWithEmail(String email, String password) async {
    final result = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    if (result.user != null) {
      await _saveUserToFirestore(result.user!);
    }
    return result.user;
  }

  // ── Google sign in ──
  Future<User?> signInWithGoogle() async {
    try {
      final googleUser = await GoogleSignIn(
        scopes: ['email', 'profile'],
      ).signIn();

      if (googleUser == null) {
        // User cancelled the sign-in flow
        return null;
      }

      final googleAuth = await googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final result = await _auth.signInWithCredential(credential);
      if (result.user != null) {
        await _saveUserToFirestore(result.user!);
      }
      return result.user;
    } catch (e) {
      debugPrint('🔴 AuthService: Google sign-in failed — $e');
      return null;
    }
  }

  // ── Phone number verification ──
  Future<void> verifyPhoneNumber({
    required String phoneNumber,
    required Function(String verificationId) codeSent,
    Function(FirebaseAuthException e)? onError,
  }) async {
    await _auth.verifyPhoneNumber(
      phoneNumber: phoneNumber,

      verificationCompleted: (PhoneAuthCredential credential) async {
        final result = await _auth.signInWithCredential(credential);
        if (result.user != null) {
          await _saveUserToFirestore(result.user!);
        }
      },

      verificationFailed: (FirebaseAuthException e) {
        if (onError != null) onError(e);
      },

      codeSent: (String verificationId, int? resendToken) {
        codeSent(verificationId);
      },

      codeAutoRetrievalTimeout: (String verificationId) {},
    );
  }

  // ── Sign out ──
  Future<void> signOut() async {
    await GoogleSignIn().signOut();
    await _auth.signOut();
  }
}