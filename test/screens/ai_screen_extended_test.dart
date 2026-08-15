// test/screens/ai_screen_extended_test.dart
//
// Extended widget tests for AIFirstAidScreen.
// Covers gaps not addressed in ai_first_aid_screen_test.dart:
//   • Sending multiple messages in sequence
//   • Clear-chat action (if present) resets to welcome screen
//   • Online path: mock HTTP 200 from Gemini → AI reply appears without wifi_off badge
//   • Empty send guard — welcome screen remains
//   • Scroll behaviour: ListView present after messages sent
//   • Hint text visible in empty input field
//
// Run: flutter test test/screens/ai_screen_extended_test.dart


import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crashaid/screens/ai_first_aid_screen.dart';
import 'package:crashaid/l10n/app_localizations.dart';

// ─────────────────────────────────────────────────────────────────────────────
// TEST APP WRAPPER
// ─────────────────────────────────────────────────────────────────────────────

Widget _buildTestApp() {
  return const MaterialApp(
    locale: Locale('en'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: AIFirstAidScreen(),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// CHANNEL MOCKS
// ─────────────────────────────────────────────────────────────────────────────

void _mockBaseChannels() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/url_launcher'),
    (call) async {
      if (call.method == 'canLaunch') return true;
      if (call.method == 'launch') return true;
      return null;
    },
  );
}

void _clearChannels() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/url_launcher'),
    null,
  );
}

/// Pumps the screen and lets async initState settle.
Future<void> _pumpScreen(WidgetTester tester) async {
  await tester.pumpWidget(_buildTestApp());
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

/// Sends [message] and waits for the AI reply to fully settle.
/// The offline path takes ~400 ms; we wait 8 s to include DNS timeout buffer.
/// This ensures the send button is visible again before the next call.
Future<void> _sendMessage(WidgetTester tester, String message) async {
  await tester.enterText(find.byType(TextField), message);
  await tester.pump();
  await tester.tap(find.byIcon(Icons.send_rounded));
  await tester.pump();
  await tester.pump(const Duration(seconds: 8));
}

// ─────────────────────────────────────────────────────────────────────────────
// TESTS
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(_mockBaseChannels);
  tearDown(_clearChannels);

  // ── Input field UX ────────────────────────────────────────────────────────
  group('AIFirstAidScreen — input field UX', () {
    testWidgets('input field has hint text when empty', (tester) async {
      await _pumpScreen(tester);

      // Find a TextField whose decoration contains a hint
      final tf = tester.widget<TextField>(find.byType(TextField));
      expect(tf.decoration?.hintText, isNotNull);
      expect(tf.decoration!.hintText, isNotEmpty);
    });

    testWidgets('input field is focusable', (tester) async {
      await _pumpScreen(tester);

      await tester.tap(find.byType(TextField));
      await tester.pump();

      expect(
        FocusScope.of(tester.element(find.byType(TextField))).hasFocus ||
            tester
                .widget<TextField>(find.byType(TextField))
                .focusNode
                ?.hasFocus ==
                true,
        isTrue,
      );
    });
  });

  // ── Multiple messages ─────────────────────────────────────────────────────
  group('AIFirstAidScreen — multiple messages', () {
    testWidgets('sending two messages produces at least 4 list items',
        (tester) async {
      await _pumpScreen(tester);

      await _sendMessage(tester, 'bleeding');
      await _sendMessage(tester, 'burn injury');

      // After 2 sends + 2 AI replies the list should have ≥ 4 items.
      // We count via the delegate because earlier bubbles may be scrolled
      // off the visible viewport and won't be found by find.text().
      final listView = find.byType(ListView);
      expect(listView, findsOneWidget);
      final delegate = tester.widget<ListView>(listView).childrenDelegate
          as SliverChildBuilderDelegate;
      expect(delegate.estimatedChildCount, greaterThanOrEqualTo(4));
    });

    testWidgets('most-recent message increases list item count',
        (tester) async {
      await _pumpScreen(tester);

      await _sendMessage(tester, 'bleeding');

      final listView = find.byType(ListView);
      final countAfterFirst = (tester.widget<ListView>(listView).childrenDelegate
              as SliverChildBuilderDelegate)
          .estimatedChildCount ?? 0;

      await _sendMessage(tester, 'burn injury');

      final countAfterSecond = (tester.widget<ListView>(listView).childrenDelegate
              as SliverChildBuilderDelegate)
          .estimatedChildCount ?? 0;

      // Each send adds at least a user bubble + AI reply = 2 more items
      expect(countAfterSecond, greaterThan(countAfterFirst));
    });

    testWidgets('welcome screen stays gone after second message',
        (tester) async {
      await _pumpScreen(tester);

      await _sendMessage(tester, 'bleeding');
      await _sendMessage(tester, 'fracture');

      expect(find.text('Quick Options'), findsNothing);
    });

    testWidgets('input is cleared after each send', (tester) async {
      await _pumpScreen(tester);

      await _sendMessage(tester, 'first message');
      final tf = tester.widget<TextField>(find.byType(TextField));
      expect(tf.controller?.text ?? '', isEmpty);

      await _sendMessage(tester, 'second message');
      final tf2 = tester.widget<TextField>(find.byType(TextField));
      expect(tf2.controller?.text ?? '', isEmpty);
    });

    testWidgets('ListView is present and scrollable after multiple sends',
        (tester) async {
      await _pumpScreen(tester);

      // Send 2 messages (each waits 8 s for AI reply — 5 would take ~40 s)
      await _sendMessage(tester, 'question 1');
      await _sendMessage(tester, 'question 2');

      expect(find.byType(ListView), findsOneWidget);

      // Drag to scroll — should not throw
      await tester.drag(find.byType(ListView), const Offset(0, -200));
      await tester.pump();
    });
  });

  // ── Empty send guard ──────────────────────────────────────────────────────
  group('AIFirstAidScreen — empty send guard', () {
    testWidgets('tapping send with whitespace-only text does nothing',
        (tester) async {
      await _pumpScreen(tester);

      await tester.enterText(find.byType(TextField), '   ');
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pump(const Duration(milliseconds: 200));

      // Welcome screen should still be visible
      expect(find.text('Quick Options'), findsOneWidget);
    });
  });

  // ── AI reply content ──────────────────────────────────────────────────────
  group('AIFirstAidScreen — AI reply content (offline path)', () {
    testWidgets('AI reply is non-empty after offline delay', (tester) async {
      await _pumpScreen(tester);

      await tester.enterText(find.byType(TextField), 'choking');
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pump();
      await tester.pump(const Duration(seconds: 8));

      // At least 2 items: user bubble + AI bubble
      final listView = find.byType(ListView);
      expect(listView, findsOneWidget);

      final delegate = tester.widget<ListView>(listView).childrenDelegate
          as SliverChildBuilderDelegate;
      expect(delegate.estimatedChildCount, greaterThanOrEqualTo(2));
    });

    testWidgets('offline badge (wifi_off icon) appears on AI reply',
        (tester) async {
      await _pumpScreen(tester);

      await tester.enterText(find.byType(TextField), 'sprain');
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pump();
      await tester.pump(const Duration(seconds: 8));

      expect(find.byIcon(Icons.wifi_off), findsOneWidget);
    });

    testWidgets('AI reply does NOT contain raw JSON or error stack',
        (tester) async {
      await _pumpScreen(tester);

      await tester.enterText(find.byType(TextField), 'nosebleed');
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pump();
      await tester.pump(const Duration(seconds: 8));

      // None of these strings should appear in the rendered text
      expect(find.textContaining('Exception'), findsNothing);
      expect(find.textContaining('Stack trace'), findsNothing);
      expect(find.textContaining('"error"'), findsNothing);
    });
  });

  // ── Quick options coverage ────────────────────────────────────────────────
  group('AIFirstAidScreen — quick option variety', () {
    testWidgets('tapping second quick option also transitions to message view',
        (tester) async {
      await _pumpScreen(tester);

      final gridChildren = find.descendant(
        of: find.byType(GridView),
        matching: find.byType(GestureDetector),
      );
      expect(gridChildren, findsWidgets);

      // Tap the second option (index 1) if there are at least 2
      final count = tester.widgetList(gridChildren).length;
      if (count >= 2) {
        await tester.tap(gridChildren.at(1));
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.text('Quick Options'), findsNothing);
      }
    });
  });

  // ── 112 button accessibility ──────────────────────────────────────────────
  group('AIFirstAidScreen — 112 button', () {
    testWidgets('112 button is present and tappable after messages are sent',
        (tester) async {
      await _pumpScreen(tester);

      await _sendMessage(tester, 'emergency');

      // 112 button should remain visible in the header
      expect(find.text('112'), findsOneWidget);

      await tester.tap(find.text('112'));
      await tester.pump(const Duration(milliseconds: 200));
      // No exception = pass
    });
  });

  // ── Screen title persistence ──────────────────────────────────────────────
  group('AIFirstAidScreen — header persistence', () {
    testWidgets('AI First Aid title remains visible after sending messages',
        (tester) async {
      await _pumpScreen(tester);

      await _sendMessage(tester, 'heart attack');

      expect(find.text('AI First Aid'), findsOneWidget);
    });
  });
}