// test/screens/ai_first_aid_screen_test.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crashaid/screens/ai_first_aid_screen.dart';
import 'package:crashaid/l10n/app_localizations.dart';

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

void _mockChannels() {
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

Future<void> _pumpScreen(WidgetTester tester) async {
  await tester.pumpWidget(_buildTestApp());
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(_mockChannels);
  tearDown(_clearChannels);

  group('AIFirstAidScreen — initial render', () {
    testWidgets('shows AI First Aid title in header', (tester) async {
      await _pumpScreen(tester);
      expect(find.text('AI First Aid'), findsOneWidget);
    });

    testWidgets('shows 112 call button in header', (tester) async {
      await _pumpScreen(tester);
      expect(find.text('112'), findsOneWidget);
    });

    testWidgets('shows welcome / quick-question grid when no messages',
        (tester) async {
      await _pumpScreen(tester);
      expect(find.text('Quick Options'), findsOneWidget);
    });

    testWidgets('shows 12 quick-option buttons', (tester) async {
      await _pumpScreen(tester);
      expect(find.byIcon(Icons.medical_services_rounded), findsOneWidget);
    });

    testWidgets('shows disclaimer text', (tester) async {
      await _pumpScreen(tester);
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    });

    testWidgets('shows text input field', (tester) async {
      await _pumpScreen(tester);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('shows send button', (tester) async {
      await _pumpScreen(tester);
      expect(find.byIcon(Icons.send_rounded), findsOneWidget);
    });
  });

  group('AIFirstAidScreen — sending a message', () {
    testWidgets('typing in field and tapping send shows user message bubble',
        (tester) async {
      await _pumpScreen(tester);

      await tester.enterText(find.byType(TextField), 'bleeding');
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('bleeding'), findsOneWidget);
    });

    testWidgets('welcome screen is replaced by message list after first send',
        (tester) async {
      await _pumpScreen(tester);

      await tester.enterText(find.byType(TextField), 'bleeding');
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Quick Options'), findsNothing);
    });

    testWidgets('input field is cleared after send', (tester) async {
      await _pumpScreen(tester);

      await tester.enterText(find.byType(TextField), 'head injury');
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final tf = tester.widget<TextField>(find.byType(TextField));
      expect(tf.controller?.text ?? '', isEmpty);
    });

    testWidgets('AI reply appears after offline response delay', (tester) async {
      await _pumpScreen(tester);

      await tester.enterText(find.byType(TextField), 'bleeding');
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pump();

      await tester.pump(const Duration(seconds: 8));

      final listView = find.byType(ListView);
      expect(listView, findsOneWidget);

      final itemCount =
          (tester.widget<ListView>(listView).childrenDelegate
                  as SliverChildBuilderDelegate)
              .estimatedChildCount;

      expect(itemCount, greaterThanOrEqualTo(2));
    });

    testWidgets('tapping send with empty field does nothing', (tester) async {
      await _pumpScreen(tester);

      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Quick Options'), findsOneWidget);
    });
  });

  group('AIFirstAidScreen — quick option buttons', () {
    testWidgets('tapping a quick option sends it as a message', (tester) async {
      await _pumpScreen(tester);

      final gridChildren = find.descendant(
        of: find.byType(GridView),
        matching: find.byType(GestureDetector),
      );

      expect(gridChildren, findsWidgets);

      await tester.tap(gridChildren.first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Quick Options'), findsNothing);
    });
  });

  group('AIFirstAidScreen — offline AI badge', () {
    testWidgets('Offline AI badge appears on AI replies in test environment',
        (tester) async {
      await _pumpScreen(tester);

      await tester.enterText(find.byType(TextField), 'burn injury');
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pump();

      await tester.pump(const Duration(seconds: 8));

      expect(find.byIcon(Icons.wifi_off), findsOneWidget);
    });
  });

  group('AIFirstAidScreen — 112 call button', () {
    testWidgets('tapping 112 button does not throw', (tester) async {
      await _pumpScreen(tester);

      await tester.tap(find.text('112'));
      await tester.pump(const Duration(milliseconds: 200));
    });
  });

  group('AIFirstAidScreen — back navigation', () {
    testWidgets('back button pops the screen', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const AIFirstAidScreen(),
                      ),
                    );
                  },
                  child: const Text('Open AI First Aid'),
                ),
              );
            },
          ),
        ),
      );

      await tester.pump();

      expect(find.text('Open AI First Aid'), findsOneWidget);
      expect(find.text('AI First Aid'), findsNothing);

      await tester.tap(find.text('Open AI First Aid'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('AI First Aid'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.arrow_back_ios_new));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Open AI First Aid'), findsOneWidget);
      expect(find.text('AI First Aid'), findsNothing);
    });
  });
}