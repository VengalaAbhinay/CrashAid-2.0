import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth/splash_screen.dart';
import 'l10n/app_localizations.dart';
import 'services/crash_foreground_service.dart';
import 'screens/live_tracking_map_screen.dart';
import 'providers.dart';
import 'admin/admin_guard.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  CrashForegroundService.init();

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF0A0A0F),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  runApp(const ProviderScope(child: CrashAidApp()));
}

class CrashAidApp extends ConsumerStatefulWidget {
  const CrashAidApp({super.key});

  static void setLocale(WidgetRef ref, String languageCode) {
    ref.read(localeProvider.notifier).setLocale(languageCode);
  }

  @override
  ConsumerState<CrashAidApp> createState() => _CrashAidAppState();
}

class _CrashAidAppState extends ConsumerState<CrashAidApp> {
  @override
  void initState() {
    super.initState();
    ref.read(localeProvider.notifier).load();
  }

  @override
  Widget build(BuildContext context) {
    final languageCode = ref.watch(localeProvider);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: Locale(languageCode),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) {
        final mediaQuery = MediaQuery.of(context);

        return MediaQuery(
          data: mediaQuery.copyWith(
            textScaler: const TextScaler.linear(1.0),
          ),
          child: child ?? const SizedBox(),
        );
      },
      home: _getHome(),
      onGenerateRoute: (settings) {
        if (kIsWeb &&
            settings.name != null &&
            settings.name!.startsWith('/admin')) {
          return MaterialPageRoute(
            builder: (_) => const AdminGuard(),
          );
        }

        if (settings.name != null && settings.name!.startsWith('/track')) {
          final uri = Uri.parse(settings.name!);
          final sessionId = uri.queryParameters['id'] ?? '';

          if (sessionId.isNotEmpty) {
            return MaterialPageRoute(
              builder: (_) => LiveTrackingMapScreen(sessionId: sessionId),
            );
          }
        }

        return null;
      },
    );
  }

  Widget _getHome() {
    if (kIsWeb) {
      final path = Uri.base.fragment;
      final pathDirect = Uri.base.path;
      final fullPath = path.isNotEmpty ? path : pathDirect;

      if (fullPath.startsWith('/admin') || pathDirect.startsWith('/admin')) {
        return const AdminGuard();
      }

      if (fullPath.startsWith('/track') || pathDirect.startsWith('/track')) {
        final uri = Uri.base;
        final sessionId = uri.queryParameters['id'] ?? '';

        if (sessionId.isNotEmpty) {
          return LiveTrackingMapScreen(sessionId: sessionId);
        }

        final fragmentUri = Uri.tryParse(path.replaceFirst('/', ''));
        final fragmentId = fragmentUri?.queryParameters['id'] ?? '';

        if (fragmentId.isNotEmpty) {
          return LiveTrackingMapScreen(sessionId: fragmentId);
        }
      }
    }

    return const SplashScreen();
  }
}