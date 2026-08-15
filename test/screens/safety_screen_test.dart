import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crashaid/l10n/app_localizations.dart';
import 'package:crashaid/screens/safety_screen.dart';

Widget buildTestApp() {
  return const MaterialApp(
    locale: Locale('en'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: SafetyScreen(),
  );
}

void main() {
  testWidgets('renders SafetyScreen', (tester) async {
    await tester.pumpWidget(buildTestApp());
    await tester.pump();

    expect(find.byType(SafetyScreen), findsOneWidget);
    expect(find.byType(AppBar), findsOneWidget);
  });

  testWidgets('shows safety icons', (tester) async {
    await tester.pumpWidget(buildTestApp());
    await tester.pump();

    expect(find.byIcon(Icons.shield_rounded), findsWidgets);
  });

  testWidgets('shows safety cards', (tester) async {
    await tester.pumpWidget(buildTestApp());
    await tester.pump();

    expect(find.byType(GestureDetector), findsAtLeastNWidgets(4));
  });

  testWidgets('shows navigation arrows', (tester) async {
    await tester.pumpWidget(buildTestApp());
    await tester.pump();

    expect(find.byIcon(Icons.arrow_forward_ios), findsAtLeastNWidgets(4));
  });

  testWidgets('opens helpline dialog', (tester) async {
    await tester.pumpWidget(buildTestApp());
    await tester.pump();

    await tester.tap(find.byIcon(Icons.phone_in_talk_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('100'), findsOneWidget);
    expect(find.text('108'), findsOneWidget);
    expect(find.text('112'), findsOneWidget);
  });
}