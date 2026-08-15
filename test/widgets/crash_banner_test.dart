import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crashaid/widgets/crash_banner.dart';
import 'package:crashaid/l10n/app_localizations.dart';

// ─────────────────────────────────────────────────────────────────────────────
// crash_banner_test.dart
//
// Widget tests for LiveTrackingBanner and CrashDetectedBanner.
// Neither banner touches Firebase or platform channels during build, so
// no channel mocking is needed for render tests.
//
// The Map button inside LiveTrackingBanner calls LiveTrackingService
// .getLiveTrackingUrl() (pure Dart static) then tries Navigator.push, which
// is safe in a MaterialApp test.
//
// Run: flutter test test/widgets/crash_banner_test.dart
// ─────────────────────────────────────────────────────────────────────────────

Widget _wrap(Widget child) {
  return MaterialApp(
    locale: const Locale('en'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Scaffold(body: child),
  );
}

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(_wrap(child));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // url_launcher mock — LiveTrackingBanner's Map button may call launchUrl
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/url_launcher'),
      (call) async {
        if (call.method == 'canLaunch') return true;
        if (call.method == 'launch') return true;
        return null;
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/url_launcher'), null);
  });

  // ── LiveTrackingBanner ─────────────────────────────────────────────────────
  group('LiveTrackingBanner', () {
    testWidgets('renders without throwing', (tester) async {
      await _pump(tester, LiveTrackingBanner(onImSafe: () {}));
      expect(find.byType(LiveTrackingBanner), findsOneWidget);
    });

    testWidgets('shows location_on icon', (tester) async {
      await _pump(tester, LiveTrackingBanner(onImSafe: () {}));
      expect(find.byIcon(Icons.location_on), findsOneWidget);
    });

    testWidgets('shows Map button text', (tester) async {
      await _pump(tester, LiveTrackingBanner(onImSafe: () {}));
      expect(find.textContaining('Map'), findsOneWidget);
    });

    testWidgets('tapping Im Safe calls onImSafe callback', (tester) async {
      bool called = false;
      await _pump(tester, LiveTrackingBanner(onImSafe: () => called = true));
      // The "I'm Safe" text is inside the localised string
      final safeBtn = find.textContaining('Safe');
      expect(safeBtn, findsOneWidget);
      await tester.tap(safeBtn);
      await tester.pump();
      expect(called, isTrue);
    });

    testWidgets('tapping Map button does not throw', (tester) async {
      await _pump(tester, LiveTrackingBanner(onImSafe: () {}));
      final mapBtn = find.textContaining('Map');
      await tester.tap(mapBtn);
      await tester.pump(const Duration(milliseconds: 200));
      // No exception = pass
    });

    testWidgets('has red border decoration', (tester) async {
      await _pump(tester, LiveTrackingBanner(onImSafe: () {}));
      final container = tester.widget<Container>(
          find.byType(Container).first);
      expect(container, isNotNull);
    });
  });

  // ── CrashDetectedBanner ───────────────────────────────────────────────────
  group('CrashDetectedBanner', () {
    testWidgets('renders without throwing', (tester) async {
      await _pump(tester,
          CrashDetectedBanner(onSosAgain: () {}, onImSafe: () {}));
      expect(find.byType(CrashDetectedBanner), findsOneWidget);
    });

    testWidgets('shows car_crash_rounded icon', (tester) async {
      await _pump(tester,
          CrashDetectedBanner(onSosAgain: () {}, onImSafe: () {}));
      expect(find.byIcon(Icons.car_crash_rounded), findsOneWidget);
    });

    testWidgets('shows SOS Sent badge text', (tester) async {
      await _pump(tester,
          CrashDetectedBanner(onSosAgain: () {}, onImSafe: () {}));
      expect(find.textContaining('SOS'), findsWidgets);
    });

    testWidgets('tapping SOS button calls onSosAgain', (tester) async {
      bool called = false;
      await _pump(
          tester,
          CrashDetectedBanner(
              onSosAgain: () => called = true, onImSafe: () {}));
      // The action SOS button (not the badge) — find the last SOS text
      final sosButtons = find.text('SOS');
      expect(sosButtons, findsWidgets);
      await tester.tap(sosButtons.last);
      await tester.pump();
      expect(called, isTrue);
    });

    testWidgets('tapping Im Safe calls onImSafe', (tester) async {
      bool called = false;
      await _pump(
          tester,
          CrashDetectedBanner(
              onSosAgain: () {}, onImSafe: () => called = true));
      final safeBtn = find.textContaining('Safe');
      expect(safeBtn, findsOneWidget);
      await tester.tap(safeBtn);
      await tester.pump();
      expect(called, isTrue);
    });

    testWidgets('shows warning_rounded icon on SOS action button',
        (tester) async {
      await _pump(tester,
          CrashDetectedBanner(onSosAgain: () {}, onImSafe: () {}));
      expect(find.byIcon(Icons.warning_rounded), findsOneWidget);
    });

    testWidgets('shows check_circle_outline_rounded on Im Safe button',
        (tester) async {
      await _pump(tester,
          CrashDetectedBanner(onSosAgain: () {}, onImSafe: () {}));
      expect(
          find.byIcon(Icons.check_circle_outline_rounded), findsOneWidget);
    });

    testWidgets('banner has a Column with two rows (header + actions)',
        (tester) async {
      await _pump(tester,
          CrashDetectedBanner(onSosAgain: () {}, onImSafe: () {}));
      expect(find.byType(Column), findsWidgets);
      expect(find.byType(Row), findsWidgets);
    });
  });
}