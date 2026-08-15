import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:crashaid/screens/home_screen.dart';
import 'package:crashaid/l10n/app_localizations.dart';


void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('debug - log all channel calls during pumpWidget', (tester) async {
    SharedPreferences.setMockInitialValues({});
    HomeScreenState.setSecureStorageForTest(null);

    // Install logging messenger so every channel call is printed
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('flutter_foreground_task/methods'),
      (call) async {
        debugPrint('  ↳ foreground_task: ${call.method}');
        if (call.method == 'requestNotificationPermission') return 0;
        if (call.method == 'requestIgnoreBatteryOptimization') return true;
        if (call.method == 'isRunningService') return false;
        if (call.method == 'startService') return true;
        if (call.method == 'stopService') return true;
        if (call.method == 'initCommunicationPort') return null;
        return null;
      },
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('flutter.baseflow.com/permissions/methods'),
      (call) async {
        debugPrint('  ↳ permissions: ${call.method} args=${call.arguments}');
        if (call.method == 'checkPermissionStatus') return 1;
        if (call.method == 'requestPermissions') {
          final perms = call.arguments as List?;
          if (perms == null) return <int, int>{};
          return {for (final p in perms) p as int: 1};
        }
        return null;
      },
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('com.crashaid/sms'), (call) async {
          debugPrint('  ↳ sms: ${call.method}');
          return null;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('com.crashaid/voice'), (call) async {
          debugPrint('  ↳ voice: ${call.method}');
          if (call.method == 'isAvailable') return false;
          return null;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/firebase_core'),
      (call) async {
        debugPrint('  ↳ firebase_core: ${call.method}');
        const opts = {'apiKey':'test','appId':'1:0:android:0','messagingSenderId':'0','projectId':'test'};
        const app = {'name':'[DEFAULT]','options':opts,'pluginConstants':{}};
        if (call.method == 'Firebase#initializeCore') return [app];
        if (call.method == 'Firebase#initializeApp') return app;
        return null;
      },
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/firebase_auth'), (call) async {
          debugPrint('  ↳ firebase_auth: ${call.method}');
          return null;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'), (call) async {
          debugPrint('  ↳ secure_storage: ${call.method}');
          return null;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('flutter.baseflow.com/geolocator'), (call) async {
          debugPrint('  ↳ geolocator: ${call.method}');
          return null;
        });

    debugPrint('⏱ pumpWidget starting...');
    await tester.pumpWidget(const ProviderScope(
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
    ));
    debugPrint('⏱ first pump...');
    await tester.pump();
    debugPrint('⏱ 300ms pump starting...');
    await tester.pump(const Duration(milliseconds: 300));
    debugPrint('⏱ pump done!');
  });
}