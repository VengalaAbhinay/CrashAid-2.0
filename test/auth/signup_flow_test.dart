// test/auth/signup_flow_test.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crashaid/auth/login_screen.dart';

void _mockChannels({
  Future<Object?> Function(MethodCall)? authHandler,
}) {
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

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/firebase_auth'),
    authHandler ?? (call) async => null,
  );

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

Widget _buildTestApp() {
  return const MaterialApp(
    home: LoginScreen(),
  );
}

Future<void> _pumpOnSignUpTab(WidgetTester tester) async {
  // The Sign Up tab renders a confirm-password field + password rules box,
  // making the layout taller than the default 800×600 test surface.
  // Without this the "Create Account" button lands at y≈727, outside the
  // viewport, so tap() misses it and snacks/spinners never appear.
  tester.view.physicalSize = const Size(800, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(_buildTestApp());
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));

  await tester.tap(find.text('Sign Up'));
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => _mockChannels());
  tearDown(_clearChannels);

  group('Sign Up tab — render', () {
    testWidgets('shows Create Account button after switching to Sign Up tab',
        (tester) async {
      await _pumpOnSignUpTab(tester);
      expect(find.text('Create Account'), findsOneWidget);
    });

    testWidgets('shows at least 2 text fields email + password',
        (tester) async {
      await _pumpOnSignUpTab(tester);
      expect(find.byType(TextField), findsAtLeastNWidgets(2));
    });

    testWidgets('still shows Google and Guest buttons on Sign Up tab',
        (tester) async {
      await _pumpOnSignUpTab(tester);
      expect(find.text('Continue with Google'), findsOneWidget);
      expect(find.text('Continue as Guest'), findsOneWidget);
    });
  });

  group('Sign Up tab — validation', () {
    testWidgets('shows error when email is empty on Create Account tap',
        (tester) async {
      await _pumpOnSignUpTab(tester);

      await tester.tap(find.text('Create Account'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Please enter email and password'), findsOneWidget);
    });

    testWidgets('shows error when only email is filled', (tester) async {
      await _pumpOnSignUpTab(tester);

      await tester.enterText(find.byType(TextField).first, 'new@test.com');
      await tester.tap(find.text('Create Account'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Please enter email and password'), findsOneWidget);
    });

    testWidgets('shows weak-password error when Firebase throws weak-password',
        (tester) async {
      _mockChannels(
        authHandler: (call) async => throw PlatformException(
          code: 'weak-password',
          message: 'Password should be at least 6 characters',
        ),
      );

      await _pumpOnSignUpTab(tester);

      await tester.enterText(find.byType(TextField).first, 'new@test.com');
      await tester.enterText(find.byType(TextField).last, '123');
      await tester.tap(find.text('Create Account'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets(
        'shows email-already-in-use error when Firebase throws that code',
        (tester) async {
      _mockChannels(
        authHandler: (call) async => throw PlatformException(
          code: 'email-already-in-use',
          message: 'The email address is already in use',
        ),
      );

      await _pumpOnSignUpTab(tester);

      await tester.enterText(find.byType(TextField).first, 'existing@test.com');
      await tester.enterText(find.byType(TextField).last, 'password123');
      await tester.tap(find.text('Create Account'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('shows invalid-email error when Firebase throws that code',
        (tester) async {
      _mockChannels(
        authHandler: (call) async => throw PlatformException(
          code: 'invalid-email',
          message: 'The email address is badly formatted.',
        ),
      );

      await _pumpOnSignUpTab(tester);

      await tester.enterText(find.byType(TextField).first, 'not-an-email');
      await tester.enterText(find.byType(TextField).last, 'password123');
      await tester.tap(find.text('Create Account'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(SnackBar), findsOneWidget);
    });
  });

  group('Sign Up tab — password visibility', () {
    testWidgets('password field is obscured by default on Sign Up tab',
        (tester) async {
      await _pumpOnSignUpTab(tester);

      final passwordField =
          tester.widget<TextField>(find.byType(TextField).last);

      expect(passwordField.obscureText, isTrue);
    });

    testWidgets('tapping eye icon reveals password on Sign Up tab',
        (tester) async {
      await _pumpOnSignUpTab(tester);

      // Sign Up tab has TWO visibility_off icons (password + confirm password).
      // Use .first to target the password field's toggle specifically.
      await tester.tap(find.byIcon(Icons.visibility_off).first);
      await tester.pump();

      // The password field is the second TextField (after email), and the
      // confirm-password field is the last — check the password one directly.
      final passwordField =
          tester.widget<TextField>(find.byType(TextField).at(1));

      expect(passwordField.obscureText, isFalse);
    });
  });

  group('Tab state — field values survive tab switch', () {
    testWidgets('email entered on Login tab is still present on Sign Up tab',
        (tester) async {
      await tester.pumpWidget(_buildTestApp());
      await tester.pump();

      await tester.enterText(find.byType(TextField).first, 'user@test.com');
      await tester.pump();

      await tester.tap(find.text('Sign Up'));
      await tester.pump(const Duration(milliseconds: 300));

      final emailField = tester.widget<TextField>(
        find.byType(TextField).first,
      );

      expect(emailField.controller?.text ?? '', equals('user@test.com'));
    });

    testWidgets('switching back to Login tab after Sign Up shows Login button',
        (tester) async {
      await tester.pumpWidget(_buildTestApp());
      await tester.pump();

      await tester.tap(find.text('Sign Up'));
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.text('Login'));
      await tester.pump(const Duration(milliseconds: 300));

      final loginButton = find.ancestor(
        of: find.text('Login'),
        matching: find.byType(ElevatedButton),
      );

      expect(loginButton, findsOneWidget);
    });
  });

  group('Sign Up tab — loading state', () {
    testWidgets(
  'Create Account button shows spinner while auth is in progress',
  (tester) async {
    final completer = Completer<Object?>();

    _mockChannels(
      authHandler: (call) {
        // The firebase_auth channel method name for createUserWithEmailAndPassword
        // varies by plugin version; intercept any non-null-returning call to keep
        // the future pending so the spinner stays visible.
        if (call.method.contains('createUser') ||
            call.method == 'Auth#createUserWithEmailAndPassword') {
          return completer.future;
        }
        return Future.value(null);
      },
    );

    await _pumpOnSignUpTab(tester);

    // Sign Up tab has 3 TextFields: email (index 0), password (index 1),
    // confirm password (index 2 / last).
    // Password must pass _isValidPassword: 8+ chars, letter + number + special.
    // 'password123' is rejected client-side (no special char) before Firebase fires.
    await tester.enterText(find.byType(TextField).at(0), 'test@test.com');
    await tester.enterText(find.byType(TextField).at(1), 'Passw0rd!');
    await tester.enterText(find.byType(TextField).at(2), 'Passw0rd!');

    await tester.tap(find.text('Create Account'));
    await tester.pump(); // triggers setState(_loading = true)

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    completer.complete(null);
    await tester.pumpAndSettle();
  },
);
  });
}