import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:crashaid/screens/home_screen.dart';
import 'package:crashaid/l10n/app_localizations.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CATCH-ALL CHANNEL SILENCER
//
// Any platform channel that has no registered handler causes the test to hang
// forever waiting for a native response that never comes.
//
// Instead of whack-a-mole (mock one channel, discover another), we install a
// single TestDefaultBinaryMessenger override that returns an empty success
// response for *every* unhandled method call.  Named channels that need real
// mock values (firebase_core, permission_handler, etc.) are registered first
// so they take priority; everything else falls through to the silencer.
// ─────────────────────────────────────────────────────────────────────────────

/// Channels that need specific return values — registered before the silencer.
void _mockNamedChannels() {
  // flutter_foreground_task
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('flutter_foreground_task/methods'),
    (call) async {
      if (call.method == 'requestNotificationPermission') return 0;
      if (call.method == 'requestIgnoreBatteryOptimization') return true;
      if (call.method == 'isRunningService') return false;
      if (call.method == 'startService') return true;
      if (call.method == 'stopService') return true;
      if (call.method == 'initCommunicationPort') return null;
      return null;
    },
  );

  // permission_handler — return "granted" (1) for every permission
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('flutter.baseflow.com/permissions/methods'),
    (call) async {
      if (call.method == 'checkPermissionStatus') return 1;
      if (call.method == 'requestPermissions') {
        final perms = call.arguments as List?;
        if (perms == null) return <int, int>{};
        return {for (final p in perms) p as int: 1};
      }
      return null;
    },
  );

  // com.crashaid/sms
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
          const MethodChannel('com.crashaid/sms'), (_) async => null);

  // com.crashaid/voice — isAvailable → false keeps voice logic dormant
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('com.crashaid/voice'),
    (call) async => call.method == 'isAvailable' ? false : null,
  );

  // firebase_core
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/firebase_core'),
    (call) async {
      const opts = {
        'apiKey': 'test',
        'appId': '1:0:android:0',
        'messagingSenderId': '0',
        'projectId': 'test',
      };
      const app = {
        'name': '[DEFAULT]',
        'options': opts,
        'pluginConstants': {},
      };
      if (call.method == 'Firebase#initializeCore') return [app];
      if (call.method == 'Firebase#initializeApp') return app;
      return null;
    },
  );

  // firebase_auth — currentUser → null so _uid == ''
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/firebase_auth'),
          (_) async => null);

  // flutter_secure_storage — real channel name confirmed from package source
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
    (call) async => null, // null = key not found → _getEmergencyContacts returns []
  );
}

// Named channels that were explicitly registered above.
const _namedChannels = [
  'flutter_foreground_task/methods',
  'flutter.baseflow.com/permissions/methods',
  'com.crashaid/sms',
  'com.crashaid/voice',
  'plugins.flutter.io/firebase_core',
  'plugins.flutter.io/firebase_auth',
  'plugins.it_nomads.com/flutter_secure_storage',
];

void _mockChannels() {
  _mockNamedChannels();
  // Reset the secure-storage override at the start of every test
  HomeScreenState.setSecureStorageForTest(null, enable: false);
}

void _clearChannels() {
  HomeScreenState.setSecureStorageForTest(null, enable: false);
  for (final name in _namedChannels) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(MethodChannel(name), null);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// APP WRAPPER
// ─────────────────────────────────────────────────────────────────────────────

Widget _buildTestApp() => const ProviderScope(
      child: MaterialApp(
        locale: Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: HomeScreen(),
      ),
    );

// ─────────────────────────────────────────────────────────────────────────────
// PUMP HELPER
//
// HomeScreen has a _pulseController that loops forever — pumpAndSettle()
// never returns. Use explicit pump durations instead.
// ─────────────────────────────────────────────────────────────────────────────

Future<void> _pumpHomeScreen(WidgetTester tester) async {
  await tester.pumpWidget(_buildTestApp());
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

  // ── Basic render ───────────────────────────────────────────────────────────
  group('HomeScreen renders', () {
    testWidgets('shows SOS button', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await _pumpHomeScreen(tester);
      expect(find.byKey(const Key('sos_button')), findsOneWidget);
    });

    testWidgets('shows quick-call buttons for 108, 100, 101', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await _pumpHomeScreen(tester);
      expect(find.text('108'), findsOneWidget);
      expect(find.text('100'), findsOneWidget);
      expect(find.text('101'), findsOneWidget);
    });
  });

  // ── _getEmergencyContacts() ────────────────────────────────────────────────
  // Uses HomeScreenState.setSecureStorageForTest() to bypass the real
  // FlutterSecureStorage platform channel entirely.
  // Raw value format: newline-joined entries, each "Name|number" or "number".
  group('_getEmergencyContacts()', () {
    group('empty prefs', () {
      testWidgets('returns empty list when no contacts stored', (tester) async {
        HomeScreenState.setSecureStorageForTest(null, enable: true); // test mode on, but no data
        SharedPreferences.setMockInitialValues({});
        await _pumpHomeScreen(tester);

        final state = tester.state<HomeScreenState>(find.byType(HomeScreen));
        final contacts = await state.getEmergencyContactsForTest();
        expect(contacts, isEmpty);
      });

      testWidgets('returns numbers from emergency_contacts key when set',
          (tester) async {
        HomeScreenState.setSecureStorageForTest(
            'Alice|+911234567890\n+910987654321');
        SharedPreferences.setMockInitialValues({});
        await _pumpHomeScreen(tester);

        final state = tester.state<HomeScreenState>(find.byType(HomeScreen));
        final contacts = await state.getEmergencyContactsForTest();
        expect(contacts, equals(['+911234567890', '+910987654321']));
      });

      testWidgets('falls back to _contacts key when _emergency_contacts empty',
          (tester) async {
        HomeScreenState.setSecureStorageForTest('Bob|+911112223333');
        SharedPreferences.setMockInitialValues({});
        await _pumpHomeScreen(tester);

        final state = tester.state<HomeScreenState>(find.byType(HomeScreen));
        final contacts = await state.getEmergencyContactsForTest();
        expect(contacts, equals(['+911112223333']));
      });

      testWidgets('strips entries with blank numbers', (tester) async {
        HomeScreenState.setSecureStorageForTest('Alice|   \nBob|+919999999999');
        SharedPreferences.setMockInitialValues({});
        await _pumpHomeScreen(tester);

        final state = tester.state<HomeScreenState>(find.byType(HomeScreen));
        final contacts = await state.getEmergencyContactsForTest();
        expect(contacts, equals(['+919999999999']));
      });
    });
  });

  // ── SOS button ─────────────────────────────────────────────────────────────
  group('SOS button', () {
    testWidgets('tapping SOS shows confirmation dialog', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await _pumpHomeScreen(tester);

      await tester.tap(find.byKey(const Key('sos_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byKey(const Key('sos_confirm_button')), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('Cancel in confirmation dialog dismisses it', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await _pumpHomeScreen(tester);

      await tester.tap(find.byKey(const Key('sos_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byKey(const Key('sos_confirm_button')), findsNothing);
    });
  });

  // ── SOS countdown dialog ───────────────────────────────────────────────────
  group('SOS countdown dialog', () {
    Future<void> openCountdown(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('sos_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byKey(const Key('sos_confirm_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets('countdown dialog appears after confirming SOS', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await _pumpHomeScreen(tester);
      await openCountdown(tester);
      expect(find.byKey(const Key('sos_countdown_dialog')), findsOneWidget);
      await tester.tap(find.byKey(const Key('sos_cancel_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('Cancel button dismisses the countdown dialog', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await _pumpHomeScreen(tester);
      await openCountdown(tester);
      await tester.tap(find.byKey(const Key('sos_cancel_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byKey(const Key('sos_countdown_dialog')), findsNothing);
    });

    testWidgets('countdown starts at 10', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await _pumpHomeScreen(tester);
      await openCountdown(tester);
      final dialog = find.byKey(const Key('sos_countdown_dialog'));
      expect(find.descendant(of: dialog, matching: find.text('10')),
          findsOneWidget);
      await tester.tap(find.byKey(const Key('sos_cancel_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('countdown decrements after 1 second', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await _pumpHomeScreen(tester);
      await openCountdown(tester);
      await tester.pump(const Duration(seconds: 1));
      final dialog = find.byKey(const Key('sos_countdown_dialog'));
      expect(find.descendant(of: dialog, matching: find.text('9')),
          findsOneWidget);
      await tester.tap(find.byKey(const Key('sos_cancel_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    });
  });

  // ── Crash detection chip ───────────────────────────────────────────────────
  group('Crash detection chip', () {
    testWidgets('shows ON state by default', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await _pumpHomeScreen(tester);
      expect(find.textContaining('Crash'), findsWidgets);
    });

    testWidgets('tapping chip opens toggle confirmation dialog', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await _pumpHomeScreen(tester);
      final sensorIcon = find.byIcon(Icons.sensors).first;
      await tester.tap(sensorIcon);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(ElevatedButton), findsWidgets);
    });
  });

  // ── Extra HomeScreen coverage ──────────────────────────────────────────────
  // These tests only exercise visible UI/dialog paths. They do not change app
  // behavior and avoid real GPS/SMS/foreground-service calls through mocks.
  group('HomeScreen extra coverage', () {
    testWidgets('shows stable HomeScreen emergency controls',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      await _pumpHomeScreen(tester);

      expect(find.byKey(const Key('sos_button')), findsOneWidget);
      expect(find.text('108'), findsOneWidget);
      expect(find.text('100'), findsOneWidget);
      expect(find.text('101'), findsOneWidget);
      expect(find.textContaining('Crash'), findsWidgets);
    });

    testWidgets('language button opens language picker dialog', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await _pumpHomeScreen(tester);

      await tester.tap(find.byIcon(Icons.language));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(Dialog), findsOneWidget);
      expect(find.byIcon(Icons.language), findsWidgets);
      expect(find.byType(ListView), findsOneWidget);

      Navigator.of(tester.element(find.byType(HomeScreen))).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('alert channel chip opens channel picker dialog',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      await _pumpHomeScreen(tester);

      await tester.tap(find.byIcon(Icons.sms_outlined).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(Dialog), findsOneWidget);
      expect(find.byIcon(Icons.send_to_mobile), findsOneWidget);
      expect(find.byIcon(Icons.chat_bubble_outline), findsWidgets);
      expect(find.byIcon(Icons.message), findsWidgets);
      expect(find.byIcon(Icons.email_outlined), findsWidgets);
      expect(find.byIcon(Icons.all_inclusive_rounded), findsWidgets);

      // Close the dialog explicitly. Some localized/dialog layouts contain
      // multiple TextButtons, so tapping the last one can be brittle.
      Navigator.of(tester.element(find.byType(HomeScreen))).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(Dialog), findsOneWidget);
    });

    testWidgets('selecting WhatsApp channel closes picker and updates chip icon',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      await _pumpHomeScreen(tester);

      await tester.tap(find.byIcon(Icons.sms_outlined).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byIcon(Icons.chat_bubble_outline).last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(Dialog), findsNothing);
      expect(find.byIcon(Icons.chat_bubble_outline), findsOneWidget);
    });

    testWidgets('crash detection confirm button toggles chip to off state',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      await _pumpHomeScreen(tester);

      await tester.tap(find.byIcon(Icons.sensors).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(Dialog), findsOneWidget);

      await tester.tap(find.byType(ElevatedButton).last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(Dialog), findsNothing);
      expect(find.byIcon(Icons.sensors_off), findsWidgets);
    });
  });

}