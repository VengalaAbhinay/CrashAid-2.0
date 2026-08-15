import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crashaid/l10n/app_localizations.dart';
import 'package:crashaid/screens/vehicle_screen.dart';

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
    home: VehicleScreen(),
  );
}

void main() {
  testWidgets('renders VehicleScreen', (tester) async {
    await tester.pumpWidget(buildTestApp());
    await tester.pump();

    expect(find.byType(VehicleScreen), findsOneWidget);
    expect(find.byType(AppBar), findsOneWidget);
  });

  testWidgets('shows vehicle rescue icons', (tester) async {
    await tester.pumpWidget(buildTestApp());
    await tester.pump();

    expect(find.byIcon(Icons.car_repair_rounded), findsWidgets);
  });

  testWidgets('shows rescue cards', (tester) async {
    await tester.pumpWidget(buildTestApp());
    await tester.pump();

    expect(find.byType(GestureDetector), findsAtLeastNWidgets(4));
  });

  testWidgets('shows navigation arrows', (tester) async {
    await tester.pumpWidget(buildTestApp());
    await tester.pump();

    expect(find.byIcon(Icons.arrow_forward_ios), findsAtLeastNWidgets(4));
  });
}