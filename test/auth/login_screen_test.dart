import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crashaid/auth/login_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CHANNEL MOCKS
// LoginScreen touches Firebase + Google Sign-In channels on auth actions.
// We mock them so taps don't hang or throw.
// ─────────────────────────────────────────────────────────────────────────────

void _mockChannels() {
  // firebase_core
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/firebase_core'),
    (call) async {
      if (call.method == 'Firebase#initializeCore') {
        return [
          {
            'name': '[DEFAULT]',
            'options': {
              'apiKey': 'test',
              'appId': '1:0:android:0',
              'messagingSenderId': '0',
              'projectId': 'test',
            },
            'pluginConstants': {},
          }
        ];
      }
      if (call.method == 'Firebase#initializeApp') {
        return {
          'name': '[DEFAULT]',
          'options': {
            'apiKey': 'test',
            'appId': '1:0:android:0',
            'messagingSenderId': '0',
            'projectId': 'test',
          },
          'pluginConstants': {},
        };
      }
      return null;
    },
  );

  // firebase_auth — return null so sign-in attempts gracefully fail
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/firebase_auth'),
    (call) async => null,
  );

  // google_sign_in — return null (user cancelled)
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.googleapis.com/google_sign_in'),
    (call) async => null,
  );
}

void _clearChannels() {
  for (final name in [
    'plugins.flutter.io/firebase_core',
    'plugins.flutter.io/firebase_auth',
    'plugins.googleapis.com/google_sign_in',
  ]) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(MethodChannel(name), null);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HELPERS
// ─────────────────────────────────────────────────────────────────────────────

Widget _buildTestApp() {
  return const MaterialApp(home: LoginScreen());
}

Future<void> _pump(WidgetTester tester) async {
  await tester.pumpWidget(_buildTestApp());
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

// ─────────────────────────────────────────────────────────────────────────────
// TESTS
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(_mockChannels);
  tearDown(_clearChannels);

  // ── Render ──────────────────────────────────────────────────────────────────
  group('LoginScreen renders', () {
    testWidgets('shows app title', (tester) async {
      await _pump(tester);
      expect(find.text('Welcome to CrashAid'), findsOneWidget);
    });

    testWidgets('shows email and password fields', (tester) async {
      await _pump(tester);
      // Two TextFields: email and password
      expect(find.byType(TextField), findsNWidgets(2));
    });

    testWidgets('shows Login tab active by default', (tester) async {
      await _pump(tester);
      // 'Login' appears in both the tab and the button — at least one is fine
      expect(find.text('Login'), findsWidgets);
      expect(find.text('Sign Up'), findsOneWidget);
    });

    testWidgets('shows Google and Guest buttons', (tester) async {
      await _pump(tester);
      expect(find.text('Continue with Google'), findsOneWidget);
      expect(find.text('Continue as Guest'), findsOneWidget);
    });

    testWidgets('shows terms disclaimer text', (tester) async {
      await _pump(tester);
      expect(
        find.textContaining('Terms'),
        findsOneWidget,
      );
    });
  });

  // ── Tab toggle ──────────────────────────────────────────────────────────────
  group('Login / Sign Up tab toggle', () {
    testWidgets('tapping Sign Up tab switches button label to Create Account',
        (tester) async {
      await _pump(tester);

      await tester.tap(find.text('Sign Up'));
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.text('Create Account'), findsOneWidget);
    });

    testWidgets('tapping Login tab after Sign Up restores Login button label',
        (tester) async {
      await _pump(tester);

      await tester.tap(find.text('Sign Up'));
      await tester.pump(const Duration(milliseconds: 250));
      await tester.tap(find.text('Login'));
      await tester.pump(const Duration(milliseconds: 250));

      // ElevatedButton should say 'Login', not 'Create Account'
      final loginButtons = find.ancestor(
        of: find.text('Login'),
        matching: find.byType(ElevatedButton),
      );
      expect(loginButtons, findsOneWidget);
    });
  });

  // ── Validation ──────────────────────────────────────────────────────────────
  group('Email auth validation', () {
    testWidgets('shows snack when email is empty', (tester) async {
      await _pump(tester);

      await tester.tap(find.byType(ElevatedButton).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.text('Please enter email and password'),
        findsOneWidget,
      );
    });

    testWidgets('shows snack when password is empty', (tester) async {
      await _pump(tester);

      // Enter only email
      await tester.enterText(find.byType(TextField).first, 'test@test.com');
      await tester.tap(find.byType(ElevatedButton).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.text('Please enter email and password'),
        findsOneWidget,
      );
    });
  });

  // ── Password visibility ──────────────────────────────────────────────────────
  group('Password field', () {
    testWidgets('password is obscured by default', (tester) async {
      await _pump(tester);

      final passwordField = tester.widget<TextField>(
        find.byType(TextField).last,
      );
      expect(passwordField.obscureText, isTrue);
    });

    testWidgets('tapping visibility icon toggles obscure off', (tester) async {
      await _pump(tester);

      await tester.tap(find.byIcon(Icons.visibility_off));
      await tester.pump();

      final passwordField = tester.widget<TextField>(
        find.byType(TextField).last,
      );
      expect(passwordField.obscureText, isFalse);
    });

    testWidgets('tapping visibility icon again toggles obscure back on',
        (tester) async {
      await _pump(tester);

      await tester.tap(find.byIcon(Icons.visibility_off));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.visibility));
      await tester.pump();

      final passwordField = tester.widget<TextField>(
        find.byType(TextField).last,
      );
      expect(passwordField.obscureText, isTrue);
    });
  });



  // ── _friendlyError mapping ──────────────────────────────────────────────────
  // These are pure-logic tests that exercise the error message mapping
  // without needing Firebase. We call them via a test subclass.
  group('_friendlyError message mapping', () {
    // We access _friendlyError indirectly by triggering a failed auth with
    // a mock that throws a recognisable exception string.
    //
    // Since _friendlyError is private we test it by injecting recognisable
    // Firebase error strings through the mock channel.

    testWidgets('unknown error returns generic fallback message',
        (tester) async {
      // Only throw on the actual sign-in call.
      // If we throw on every call the Firebase init fails and the UI never
      // builds, so the SnackBar never appears.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/firebase_auth'),
        (call) async {
          if (call.method == 'Auth#signInWithEmailAndPassword') {
            throw PlatformException(
              code: 'unknown',
              message: 'something-went-wrong',
            );
          }
          return null;
        },
      );

      await _pump(tester);
      await tester.enterText(find.byType(TextField).first, 'a@b.com');
      // Must pass _isValidPassword: 8+ chars, letter + number + special char.
      // 'password' alone is rejected client-side before Firebase is ever called.
      await tester.enterText(find.byType(TextField).last, 'Passw0rd!');
      await tester.tap(find.byType(ElevatedButton).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.textContaining('Something went wrong'), findsOneWidget);
    });
  });
}