import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:crashaid/l10n/app_localizations.dart';
import 'package:crashaid/screens/profile_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CHANNEL MOCKS
// ─────────────────────────────────────────────────────────────────────────────

void _mockChannels() {
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
    (call) async => null,
  );
}

void _clearChannels() {
  for (final name in [
    'plugins.flutter.io/firebase_core',
    'plugins.flutter.io/firebase_auth',
  ]) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(MethodChannel(name), null);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HELPERS
// Pass email directly so ProfileScreen never calls FirebaseAuth in tests
// ─────────────────────────────────────────────────────────────────────────────

Widget buildTestApp({String? email}) {
  return MaterialApp(
    locale: const Locale('en'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: ProfileScreen(email: email),
  );
}

Future<void> pumpProfile(
  WidgetTester tester, {
  Map<String, Object> prefs = const {},
  String? email,
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  await tester.pumpWidget(buildTestApp(email: email));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

// ─────────────────────────────────────────────────────────────────────────────
// TESTS
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(_mockChannels);
  tearDown(_clearChannels);

  testWidgets('renders ProfileScreen after loading profile data', (tester) async {
    await pumpProfile(tester);

    expect(find.byType(ProfileScreen), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(TextField), findsWidgets);
  });

  testWidgets('loads saved profile values from SharedPreferences', (tester) async {
    await pumpProfile(
      tester,
      prefs: {
        'name': 'Abhinay',
        'age': '20',
        'phone': '9999999999',
        'blood': 'O+',
        'gender': 'Male',
        'allergy': 'None',
        'condition': 'None',
      },
    );

    expect(find.text('Abhinay'), findsWidgets);
    expect(find.textContaining('O+'), findsWidgets);
  });

  testWidgets('shows delete profile button in view mode', (tester) async {
    await pumpProfile(tester);

    expect(find.byIcon(Icons.delete_outline_rounded), findsWidgets);
  });

  testWidgets('delete profile button opens confirmation dialog', (tester) async {
    await pumpProfile(tester);

    await tester.tap(find.byIcon(Icons.delete_outline_rounded).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(AlertDialog), findsOneWidget);
  });

  testWidgets('shows logged-in email when provided', (tester) async {
    await pumpProfile(tester, email: 'test@example.com');

    expect(find.text('test@example.com'), findsOneWidget);
  });
}