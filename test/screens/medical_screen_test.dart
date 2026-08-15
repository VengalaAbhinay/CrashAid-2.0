import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crashaid/l10n/app_localizations.dart';
import 'package:crashaid/screens/medical_screen.dart';

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
    home: MedicalScreen(),
  );
}

void main() {
  testWidgets('renders MedicalScreen', (tester) async {
    await tester.pumpWidget(buildTestApp());
    await tester.pump();

    expect(find.byType(MedicalScreen), findsOneWidget);
    expect(find.byType(AppBar), findsOneWidget);
  });

  testWidgets('shows emergency icons', (tester) async {
    await tester.pumpWidget(buildTestApp());
    await tester.pump();

    expect(find.byIcon(Icons.emergency), findsWidgets);
  });

  testWidgets('shows multiple medical cards', (tester) async {
    await tester.pumpWidget(buildTestApp());
    await tester.pump();

    expect(find.byType(GestureDetector), findsAtLeastNWidgets(5));
  });

  testWidgets('contains navigation arrows', (tester) async {
    await tester.pumpWidget(buildTestApp());
    await tester.pump();

    expect(find.byIcon(Icons.arrow_forward_ios), findsAtLeastNWidgets(5));
  });
}
