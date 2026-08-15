import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── Locale ─────────────────────────────────────────────────────────────────

class LocaleNotifier extends Notifier<String> {
  @override
  String build() => 'en';

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('app_locale');
    if (saved != null) state = saved;
  }

  Future<void> setLocale(String languageCode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_locale', languageCode);
    state = languageCode;
  }
}

final localeProvider = NotifierProvider<LocaleNotifier, String>(
  LocaleNotifier.new,
);

// ── SOS active ─────────────────────────────────────────────────────────────

final sosActiveProvider = StateProvider<bool>((ref) => false);

// ── Crash detection enabled ────────────────────────────────────────────────

class CrashDetectionNotifier extends Notifier<bool> {
  @override
  bool build() => true;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool('crash_detection_enabled') ?? true;
  }

  Future<void> toggle(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('crash_detection_enabled', value);
    state = value;
  }
}

final crashDetectionProvider =
    NotifierProvider<CrashDetectionNotifier, bool>(CrashDetectionNotifier.new);

// ── Crash detected banner ──────────────────────────────────────────────────

final crashDetectedProvider = StateProvider<bool>((ref) => false);

// ── Alert channel (sms / whatsapp / email / all) ───────────────────────────

class AlertChannelNotifier extends Notifier<String> {
  @override
  String build() => 'sms';

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getString('alert_channel') ?? 'sms';
  }

  Future<void> setChannel(String channel) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('alert_channel', channel);
    state = channel;
  }
}

final alertChannelProvider =
    NotifierProvider<AlertChannelNotifier, String>(AlertChannelNotifier.new);

// ── Voice detection ────────────────────────────────────────────────────────

final voiceDetectionOnProvider = StateProvider<bool>((ref) => false);
final isListeningProvider      = StateProvider<bool>((ref) => false);
final lastWordsProvider        = StateProvider<String>((ref) => '');
final speechAvailableProvider  = StateProvider<bool>((ref) => false);

// ── User Mode (Challenge 06) ───────────────────────────────────────────────

enum UserMode { driver, women, senior, child }

class UserModeNotifier extends Notifier<UserMode> {
  @override
  UserMode build() => UserMode.driver;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('user_mode') ?? 'driver';
    state = UserMode.values.firstWhere(
      (m) => m.name == saved,
      orElse: () => UserMode.driver,
    );
  }

  Future<void> setMode(UserMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_mode', mode.name);
    state = mode;
  }
}

final userModeProvider =
    NotifierProvider<UserModeNotifier, UserMode>(UserModeNotifier.new);

// ── Fall Detection enabled ─────────────────────────────────────────────────

class FallDetectionNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool('fall_detection_enabled') ?? false;
  }

  Future<void> toggle(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('fall_detection_enabled', value);
    state = value;
  }
}

final fallDetectionProvider =
    NotifierProvider<FallDetectionNotifier, bool>(FallDetectionNotifier.new);

// ── Safe Walk active ───────────────────────────────────────────────────────

final safeWalkActiveProvider = StateProvider<bool>((ref) => false);
