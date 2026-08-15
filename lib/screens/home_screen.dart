import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import '../services/web_speech_interface.dart';
import '../auth/auth_service.dart';
import '../auth/login_screen.dart';
import '../l10n/app_localizations.dart';
import '../screens/medical_screen.dart';
import '../screens/vehicle_screen.dart';
import '../screens/safety_screen.dart';
import '../screens/ai_first_aid_screen.dart';
import '../screens/profile_screen.dart';
import '../screens/profile_mode_screen.dart';
import '../screens/women_safety_screen.dart';
import '../screens/safe_route_screen.dart';
import '../screens/missing_person_screen.dart';
import '../screens/night_safety_screen.dart';
import '../screens/pothole_map_screen.dart'; // ← NEW: crowd-sourced pothole reporting
import '../screens/drowsiness_monitor_screen.dart'; // ← NEW: front-camera drowsiness alert
import '../screens/ambulance_routing_screen.dart'; // ← NEW: intelligent ambulance routing
import '../services/live_tracking_service.dart';
import '../services/crash_foreground_service.dart';
import '../services/sos_firestore_service.dart'; // ← NEW: writes to Firestore for admin dashboard
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers.dart';
import '../widgets/sos_section.dart';
import '../widgets/crash_banner.dart';
import '../widgets/night_safety_banner.dart';
import '../widgets/voice_button.dart';
import '../widgets/sos_dialog.dart';
import '../widgets/countdown_dialog.dart';

// ─────────────────────────────────────────────────────────────────────────────
// HOME SCREEN
// ─────────────────────────────────────────────────────────────────────────────
// Exposed for widget tests only — do not use in production code.
// ignore: library_private_types_in_public_api
typedef HomeScreenState = _HomeScreenState;

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> with TickerProviderStateMixin {
  // ── Riverpod state getters ─────────────────────────────────────────────────
  bool get _isSosActive => ref.watch(sosActiveProvider);
  bool get _crashDetectionEnabled => ref.watch(crashDetectionProvider);
  bool get _isCrashDetected => ref.watch(crashDetectedProvider);
  String get _alertChannel => ref.watch(alertChannelProvider);
  bool get _voiceDetectionOn => ref.watch(voiceDetectionOnProvider);
  bool get _speechAvailable => ref.watch(speechAvailableProvider);
  bool get _isListening => ref.watch(isListeningProvider);
  String get _lastWords => ref.watch(lastWordsProvider);

  // Cached so dispose() can check this without touching ref after unmount.
  bool _cachedVoiceDetectionOn = false;

  // Guards to prevent double-tap buffering on Safe / SOS buttons.
  bool _isSendingSafe = false;
  bool _isSendingSOS = false;

  int countdown = 10;
  Timer? timer;

  String get _uid {
    try {
      return FirebaseAuth.instance.currentUser?.uid ?? '';
    } catch (_) {
      return '';
    }
  }

  late AnimationController _pulseController;
  late AnimationController _fadeController;
  late Animation<double> _pulseAnim;
  late Animation<double> _fadeAnim;

  // ─── VOICE DETECTION ──────────────────────────────────────────────────────
  Timer? _restartTimer;             // re-listen loop timer

  // Words that trigger the SOS (used by native Kotlin layer via MethodChannel)
  // ignore: unused_field
  static const _triggerWords = ['help me', 'help', 'sos', 'emergency', 'bachao'];

  // Remembers the To: address used in the last email SOS — reused for safe message

  static const _smsChannel   = MethodChannel('com.crashaid/sms');
 static const _voiceChannel = MethodChannel('com.crashaid/voice');
  // Challenge 06 — panic button via volume key (Kotlin MethodChannel)
  static const _panicChannel = MethodChannel('com.crashaid/panic');


  @override
  void initState() {
    super.initState();
    _requestSmsPermission();
    _initForegroundService();
    _loadCrashDetectionPref();
    _initSpeech();
    _initPanicButton();
    ref.read(userModeProvider.notifier).load();
    ref.read(fallDetectionProvider.notifier).load();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _pulseAnim = Tween<double>(begin: 1.0, end: 1.06).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..forward();

    _fadeAnim = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
  }

  // ── Init speech engine ─────────────────────────────────────────────────────
 Future<void> _initSpeech() async {
   if (kIsWeb) {
     // Web: use browser's built-in SpeechRecognition API
     ref.read(speechAvailableProvider.notifier).state = true;
     return;
   }
   try {
     final available =
         await _voiceChannel.invokeMethod<bool>('isAvailable') ?? false;
     ref.read(speechAvailableProvider.notifier).state = available;
     _voiceChannel.setMethodCallHandler((call) async {
       if (call.method == 'onTrigger') {
         ref.read(lastWordsProvider.notifier).state = call.arguments as String? ?? '';
         _onVoiceTrigger();
       }
     });
   } catch (e) {
     debugPrint('🎤 _initSpeech error: $e');
     ref.read(speechAvailableProvider.notifier).state = false;
   }
   if (mounted) setState(() {});
 }

  // ── Init panic button (volume-key hold via Kotlin MethodChannel) ───────────
  Future<void> _initPanicButton() async {
    try {
      await _panicChannel.invokeMethod('startListening');
      _panicChannel.setMethodCallHandler((call) async {
        if (call.method == 'onPanicTrigger' && mounted) {
          debugPrint('🔴 Panic button triggered via volume key!');
          HapticFeedback.heavyImpact();
          // Show cancel countdown then fire SOS
          final cancelled = await _showCrashCancelCountdown();
          if (!cancelled) await _sendSOSSilent();
        }
      });
    } catch (e) {
      debugPrint('⚠️ Panic button init error: $e');
    }
  }


Future<void> _startListening() async {
  final langCode = ref.read(localeProvider);
  final bcp47 = switch (langCode) {
    'kn' => 'kn-IN',
    'hi' => 'hi-IN',
    'te' => 'te-IN',
    'ta' => 'ta-IN',
    'mr' => 'mr-IN',
    _    => 'en-IN',
  };
  try {
    if (kIsWeb) {
      startWebSpeech((String transcript) {
        ref.read(lastWordsProvider.notifier).state = transcript;
        _onVoiceTrigger();
      });
      if (mounted) ref.read(isListeningProvider.notifier).state = true;
      return;
    }
    await _voiceChannel.invokeMethod('startListening', {'locale': bcp47});
    if (mounted) ref.read(isListeningProvider.notifier).state = true;
  } catch (e) {
    debugPrint('🎤 _startListening error: $e');
  }
}

Future<void> _stopListening() async {
  _restartTimer?.cancel();
  try {
    if (kIsWeb) {
      stopWebSpeech();
      if (mounted) ref.read(isListeningProvider.notifier).state = false;
      return;
    }
    await _voiceChannel.invokeMethod('stopListening');
  } catch (e) {
    debugPrint('🎤 _stopListening error: $e');
  }
  if (mounted) ref.read(isListeningProvider.notifier).state = false;
}
Future<void> _toggleVoiceDetection() async {
    if (!_speechAvailable) {
      await _initSpeech();
      if (!_speechAvailable) {
        _snack('Speech recognition not available on this device', Colors.orange);
        return;
      }
    }
    _showVoiceToggleConfirm();
  }

  void _showVoiceToggleConfirm() {
    final isCurrentlyOn = _voiceDetectionOn;
    showDialog(
      context: context,
      builder: (dialogContext) {
        final loc = AppLocalizations.of(dialogContext);
        return Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A2E),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: isCurrentlyOn
                  ? Colors.white24
                  : const Color(0xFF00C851).withValues(alpha: 0.5),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: isCurrentlyOn
                    ? Colors.black45
                    : const Color(0xFF00C851).withValues(alpha: 0.2),
                blurRadius: 28,
                spreadRadius: 4,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Animated icon with ring
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isCurrentlyOn
                      ? Colors.white.withValues(alpha: 0.06)
                      : const Color(0xFF00C851).withValues(alpha: 0.12),
                  border: Border.all(
                    color: isCurrentlyOn
                        ? Colors.white24
                        : const Color(0xFF00C851).withValues(alpha: 0.4),
                  ),
                ),
                child: Icon(
                  isCurrentlyOn ? Icons.mic_off_rounded : Icons.mic_rounded,
                  color: isCurrentlyOn
                      ? Colors.white54
                      : const Color(0xFF00C851),
                  size: 36,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                isCurrentlyOn ? loc.turnOffVoiceDetection : loc.turnOnVoiceDetection,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Text(
                isCurrentlyOn ? loc.voiceOffDesc : loc.voiceOnDesc,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54, fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      style: TextButton.styleFrom(
                        backgroundColor: Colors.white10,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Text(
                        loc.cancel,
                        style: const TextStyle(color: Colors.white70, fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        Navigator.pop(dialogContext);
                        if (isCurrentlyOn) {
                          await _stopListening();
                          ref.read(voiceDetectionOnProvider.notifier).state = false;
                          _snack(loc.voiceDetectionOff, Colors.white54);
                        } else {
                          ref.read(voiceDetectionOnProvider.notifier).state = true;
                          await _startListening();
                          _snack(loc.voiceDetectionOn, const Color(0xFF00C851));
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isCurrentlyOn ? Colors.redAccent : const Color(0xFF00C851),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Text(
                        isCurrentlyOn ? loc.turnOff : loc.turnOn,
                        style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
      },
    );
  }

  // ── Trigger word detected → show confirmation first ───────────────────────
  void _onVoiceTrigger() {
    if (!mounted) return;
    HapticFeedback.heavyImpact();
    debugPrint('🚨 Voice trigger detected! Showing confirmation...');
    _showVoiceConfirmDialog();
  }

  // ── STEP 1: Confirmation dialog (10s) ─────────────────────────────────────
  // "Did you say SOS?" — if no response, proceeds to SOS countdown.
  void _showVoiceConfirmDialog() {
    if (!mounted) return;

    int confirmCount = 10;
    Timer? confirmTimer;
    bool proceeded = false;
    final notifier = ValueNotifier<int>(confirmCount);

    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.85),
      builder: (ctx) {
        confirmTimer = Timer.periodic(const Duration(seconds: 1), (t) {
          confirmCount--;
          notifier.value = confirmCount;
          if (confirmCount <= 0) {
            t.cancel();
            if (Navigator.canPop(ctx)) Navigator.pop(ctx);
            if (!proceeded) {
              proceeded = true;
              _showVoiceSOSCountdown(); // no response → go to SOS countdown
            }
          }
        });

        return ValueListenableBuilder<int>(
          valueListenable: notifier,
          builder: (_, count, __) => Dialog(
            backgroundColor: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A2E),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                    color: const Color(0xFFFF8C3B).withValues(alpha: 0.8), width: 2),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFF8C3B).withValues(alpha: 0.3),
                    blurRadius: 32,
                    spreadRadius: 6,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFFFF8C3B).withValues(alpha: 0.15),
                      border: Border.all(
                          color: const Color(0xFFFF8C3B).withValues(alpha: 0.5)),
                    ),
                    child: const Icon(Icons.mic_rounded,
                        color: Color(0xFFFF8C3B), size: 36),
                  ),
                  const SizedBox(height: 16),
                  Builder(builder: (context) => Text(
                    AppLocalizations.of(context).didYouSaySos,
                    style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                  )),
                  const SizedBox(height: 6),
                  Text(
                    'Heard: "$_lastWords"',
                    style:
                        const TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                  const SizedBox(height: 6),
                  Builder(builder: (context) => Text(
                    AppLocalizations.of(context).voiceNoResponseWarning,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white54, fontSize: 13, height: 1.4),
                  )),
                  const SizedBox(height: 20),
                  // Countdown ring
                  Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: const Color(0xFFFF8C3B), width: 3),
                      color: const Color(0xFFFF8C3B).withValues(alpha: 0.1),
                    ),
                    child: Center(
                      child: Text(
                        '$count',
                        style: const TextStyle(
                            fontSize: 44,
                            color: Color(0xFFFF8C3B),
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  // YES — send SOS now
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        confirmTimer?.cancel();
                        proceeded = true;
                        Navigator.pop(ctx);
                        _showVoiceSOSCountdown(); // user confirmed → go to SOS
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF3B3B),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Builder(builder: (context) => Text(
                        AppLocalizations.of(context).yesSendSos,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w600),
                      )),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // NO — false alarm
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: () {
                        confirmTimer?.cancel();
                        proceeded = true;
                        Navigator.pop(ctx);
                        // Resume listening — false alarm
                        if (_voiceDetectionOn) _startListening();
                      },
                      style: TextButton.styleFrom(
                        backgroundColor: Colors.white12,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Builder(builder: (context) => Text(
                        AppLocalizations.of(context).noImFine,
                        style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 15,
                            fontWeight: FontWeight.w600),
                      )),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Builder(builder: (context) => Text(
                    AppLocalizations.of(context).format('proceedingIn', {'count': '$count'}),
                    style: const TextStyle(color: Colors.white30, fontSize: 11),
                  )),
                ],
              ),
            ),
          ),
        );
      },
    ).then((_) => notifier.dispose());
  }

  // ── STEP 2: SOS Countdown dialog (10s) ────────────────────────────────────
  // User confirmed (or didn't respond to step 1) — last chance to cancel.
  void _showVoiceSOSCountdown() {
    if (!mounted) return;
    showVoiceSosCountdownDialog(
      context,
      onSend: _sendSOS,
      onCancelledResumeVoice: () {
        if (_voiceDetectionOn) _startListening();
      },
    );
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white)),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      duration: const Duration(seconds: 3),
    ));
  }

  Future<void> _requestSmsPermission() async {
    await Permission.sms.request();
    debugPrint('📱 SMS permission: ${await Permission.sms.status}');
  }

  Future<void> _initForegroundService() async {
    debugPrint('🔥 starting foreground service');
    FlutterForegroundTask.initCommunicationPort();
    await FlutterForegroundTask.requestIgnoreBatteryOptimization();

    // ── Request location permission BEFORE starting the foreground service ──
    // Android 14+ (targetSDK=35) requires location permission to be granted
    // at runtime before a foreground service with type=location can start.
    var locationStatus = await Permission.location.status;
    if (!locationStatus.isGranted) {
      locationStatus = await Permission.location.request();
    }
    if (!locationStatus.isGranted) {
      debugPrint('⚠️ Location permission denied — crash detection disabled');
      return; // Don't start the service without permission
    }

    CrashForegroundService.listenForCrash(
      (numbers, location, type) async {
        final isCrash = type == 'crash_detected';
        final isFall  = type == 'fall_detected';
        final isShake = type == 'shake_sos';

        // Preserve existing behavior: real crash events still respect the
        // user's crash-detection toggle.
        if (isCrash && !_crashDetectionEnabled) {
          debugPrint('🔕 Crash event ignored — detection is OFF');
          return;
        }

        // Fall detection only active when Senior mode is on AND enabled
        if (isFall) {
          final mode = ref.read(userModeProvider);
          final fallEnabled = ref.read(fallDetectionProvider);
          if (mode != UserMode.senior || !fallEnabled) return;
        }

        debugPrint('🚨 MAIN RECEIVED $type EVENT — numbers: $numbers');

        if (!mounted) return;

        // Show 10-second cancel window before SOS fires
        final cancelled = await _showCrashCancelCountdown();
        if (cancelled) {
          debugPrint('🚫 SOS cancelled by user');
          return;
        }

        await _sendSOSSilent(numbers: numbers, location: location);
        if (mounted) {
          if (isCrash) ref.read(crashDetectedProvider.notifier).state = true;
          ref.read(sosActiveProvider.notifier).state = true;

          final aiMsg = isFall
              ? 'I just fell and cannot get up. What should I do?'
              : isShake
                  ? 'I triggered an emergency SOS. What should I do right now?'
                  : 'I was just in a crash. What should I do right now?';

          _showAfterSOSOptions(isCrash: isCrash);
          // Auto-open AI First Aid screen after the event
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AIFirstAidScreen(initialMessage: aiMsg),
                ),
              );
            }
          });
        }
      },
    );
    await CrashForegroundService.start();
    debugPrint('🔥 foreground service started');
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _fadeController.dispose();
    _restartTimer?.cancel();
    // Use the cached value — ref is invalid after the widget is disposed.
    if (_cachedVoiceDetectionOn) _stopListening();
    LiveTrackingService.stopTracking();
    super.dispose();
  }

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  /// Test-only sentinel. When set to any value (including empty string),
  /// [_getEmergencyContacts] uses it directly and never touches the platform
  /// channel. Use [setSecureStorageForTest] to set/clear it.
  /// _testMode = false  → production path (real storage)
  /// _testMode = true   → use _testStorageValue (may be null → no contacts)
  static bool _testMode = false;
  static String? _testStorageValue;

  Future<List<String>> _getEmergencyContacts() async {
    // In tests, bypass the platform channel entirely.
    final raw = _testMode
        ? _testStorageValue
        : await _storage.read(key: '${_uid}_emergency_contacts');
    List<String> contacts = [];
    if (raw != null && raw.isNotEmpty) {
      contacts = raw.split('\n').where((e) => e.isNotEmpty).toList();
    }
    final numbers = contacts
        .map((c) => c.contains('|') ? c.split('|')[1] : c)
        .where((n) => n.trim().isNotEmpty)
        .toList();
    debugPrint('🚨 Emergency contacts (uid=$_uid): $numbers');
    return numbers;
  }

  @visibleForTesting
  Future<List<String>> getEmergencyContactsForTest() => _getEmergencyContacts();

  /// Call in tests to bypass FlutterSecureStorage entirely.
  /// Pass a raw newline-joined string to seed contacts, or null for empty.
  /// Call setSecureStorageForTest(null, enable: false) in tearDown to reset.
  // ignore: unused_element
  static void setSecureStorageForTest(String? rawValue, {bool enable = true}) {
    _testMode = enable;
    _testStorageValue = rawValue;
  }

  Future<Position> _getLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw Exception('Enable GPS');
    }
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      throw Exception('Location permission denied forever');
    }
    // FIX: always timeout so GPS never hangs forever
    return await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    ).timeout(
      const Duration(seconds: 10),
      onTimeout: () => throw Exception('GPS timeout — took too long'),
    );
  }

  void _showCrashToggleConfirm() {
    final isCurrentlyOn = _crashDetectionEnabled;
    showDialog(
      context: context,
      builder: (dialogContext) {
        final loc = AppLocalizations.of(dialogContext);
        return Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A2E),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isCurrentlyOn
                  ? Colors.white24
                  : const Color(0xFF00C851).withValues(alpha: 0.4),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isCurrentlyOn ? Icons.sensors_off : Icons.sensors,
                color: isCurrentlyOn ? Colors.white54 : const Color(0xFF00C851),
                size: 44,
              ),
              const SizedBox(height: 12),
              Text(
                isCurrentlyOn ? loc.turnOffCrashDetection : loc.turnOnCrashDetection,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                isCurrentlyOn ? loc.crashOffDesc : loc.crashOnDesc,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54, fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      style: TextButton.styleFrom(
                        backgroundColor: Colors.white10,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(
                        loc.cancel,
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(dialogContext);
                        _setCrashDetection(!isCurrentlyOn);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isCurrentlyOn
                            ? Colors.redAccent
                            : const Color(0xFF00C851),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(
                        isCurrentlyOn ? loc.turnOff : loc.turnOn,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
      },
    );
  }

  Future<bool> _sendNativeSMS(List<String> numbers, String message) async {
    try {
      final status = await Permission.sms.status;
      if (!status.isGranted) {
        final newStatus = await Permission.sms.request();
        if (!newStatus.isGranted) return false;
      }
      final result = await _smsChannel.invokeMethod('sendSMS', {
        'numbers': numbers,
        'message': message,
      });
      return result == 'sent';
    } on PlatformException catch (e) {
      debugPrint('🚨 Native SMS PlatformException: ${e.code} — ${e.message}');
      return false;
    } catch (e) {
      debugPrint('🚨 Native SMS error: $e');
      return false;
    }
  }

  Future<void> _sendSOSSilent({List<String>? numbers, String? location}) async {
    try {
      final contacts = (numbers != null && numbers.isNotEmpty)
          ? numbers
          : await _getEmergencyContacts();
      if (contacts.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('⚠️ SOS failed: No emergency contacts set. Please add contacts in Settings.'),
              backgroundColor: Colors.redAccent,
              duration: Duration(seconds: 6),
            ),
          );
        }
        return;
      }

      Position pos;
      String staticMap;
      String liveUrl;

      if (location != null && location != 'unavailable') {
        staticMap = location;
        try {
          pos = await Geolocator.getCurrentPosition(
                  desiredAccuracy: LocationAccuracy.high)
              .timeout(const Duration(seconds: 8));
          await LiveTrackingService.startTracking('CrashAid User',
              seedPosition: pos);
          liveUrl = LiveTrackingService.getTrackingUrlFromPosition(pos);
          // ── Write SOS to Firestore for admin dashboard ──────────
          unawaited(SosFirestoreService.createSession(
            lat: pos.latitude,
            lng: pos.longitude,
            address: 'https://maps.google.com/?q=\${pos.latitude},\${pos.longitude}',
          ));
        } catch (_) {
          liveUrl = staticMap;
          unawaited(SosFirestoreService.createSession(address: staticMap));
        }
      } else {
        pos = await _getLocation();
        await LiveTrackingService.startTracking('CrashAid User',
            seedPosition: pos);
        staticMap =
            'https://maps.google.com/?q=\${pos.latitude},\${pos.longitude}';
        liveUrl = LiveTrackingService.getTrackingUrlFromPosition(pos);
        // ── Write SOS to Firestore for admin dashboard ──────────────
        unawaited(SosFirestoreService.createSession(
          lat: pos.latitude,
          lng: pos.longitude,
          address: staticMap,
        ));
      }

      if (mounted) ref.read(sosActiveProvider.notifier).state = true;
      if (!mounted) return;

      final loc = AppLocalizations.of(context);
      final message = loc.crashSmsMessage
          .replaceAll('{staticMap}', staticMap)
          .replaceAll('{liveUrl}', liveUrl);

      await _sendAlert(contacts: contacts, message: message);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_alertChannel == 'whatsapp'
                ? AppLocalizations.of(context).snackWhatsapp
                : _alertChannel == 'both'
                    ? AppLocalizations.of(context).snackBoth
                    : _alertChannel == 'email'
                        ? AppLocalizations.of(context).snackEmail
                        : _alertChannel == 'all'
                            ? AppLocalizations.of(context).snackAll
                            : AppLocalizations.of(context).snackCrashSos),
            backgroundColor: Colors.redAccent,
            duration: const Duration(seconds: 6),
          ),
        );
      }
    } catch (e) {
      debugPrint('🚨 _sendSOSSilent ERROR: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('⚠️ SOS failed: ${e.toString().replaceAll('Exception: ', '')}'),
            backgroundColor: Colors.redAccent,
            duration: const Duration(seconds: 6),
          ),
        );
      }
    }
  }

  void startSOS() {
    showSosConfirmDialog(context, onConfirmed: _startSOSCountdown);
  }

  void _startSOSCountdown() {
    showSosCountdownDialog(
      context,
      getCountdown: () => countdown,
      setCountdown: (v) => countdown = v,
      getTimer: () => timer,
      setTimer: (t) => timer = t,
      onSend: _sendSOS,
      onCancelled: () {}, // user cancelled — nothing extra to do
    );
  }

  Future<void> _sendSOS() async {
    if (_isSendingSOS) return; // prevent double-tap buffering
    _isSendingSOS = true;
    try {
      List<String> contacts = await _getEmergencyContacts();
      if (contacts.isEmpty) {
        _showNoContactsDialog();
        return;
      }

      // FIX: wrap location in its own try/catch with timeout so a slow or
      // failed GPS never blocks _showAfterSOSOptions() from being called.
      String staticMap = 'Location unavailable';
      String liveUrl = 'Location unavailable';
      try {
        final pos = await _getLocation().timeout(
          const Duration(seconds: 10),
          onTimeout: () => throw Exception('GPS timeout'),
        );
        await LiveTrackingService.startTracking('CrashAid User', seedPosition: pos);
        liveUrl = LiveTrackingService.getTrackingUrlFromPosition(pos);
        staticMap = 'https://maps.google.com/?q=${pos.latitude},${pos.longitude}';
        unawaited(SosFirestoreService.createSession(
          lat: pos.latitude, lng: pos.longitude, address: staticMap));
      } catch (locErr) {
        debugPrint('⚠️ SOS location error (continuing anyway): $locErr');
        unawaited(SosFirestoreService.createSession());
      }

      ref.read(sosActiveProvider.notifier).state = true;
      if (!mounted) return;
      final loc = AppLocalizations.of(context);
      final message = loc.sosSmsMessage
          .replaceAll('{staticMap}', staticMap)
          .replaceAll('{liveUrl}', liveUrl);
      await _sendAlert(contacts: contacts, message: message);
    } catch (e) {
      debugPrint('SOS ERROR: $e');
    } finally {
      _isSendingSOS = false; // always reset
    }
    // FIX: always reached now — post-SOS dialog never gets stuck loading
    if (!mounted) return;
    _showAfterSOSOptions();
  }

  void _showNoContactsDialog() => showNoContactsDialog(context);

  /// Shows a 10-second cancel countdown after crash is detected.
  /// Returns true if the user cancelled (SOS should NOT fire),
  /// false if the countdown elapsed (SOS should fire).
  Future<bool> _showCrashCancelCountdown() async {
    if (!mounted) return false;
    return showCrashCancelCountdown(context);
  }

  void _showAfterSOSOptions({bool isCrash = false}) {
    final String aiMessage = isCrash
        ? 'I was just in a crash. What should I do right now?'
        : 'I just sent an SOS alert. What should I do right now?';
    showAfterSosOptionsDialog(
      context,
      onCallEmergency: () => _callNumber('112'),
      onFirstAid: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AIFirstAidScreen(initialMessage: aiMessage),
        ),
      ),
      onImSafe: () async {
        unawaited(SosFirestoreService.resolveSession()); // ← admin dashboard
        await Future.wait([
          LiveTrackingService.stopTracking(),
          _sendSafeMessage(),
        ]).timeout(const Duration(seconds: 10), onTimeout: () => []);
        if (!mounted) return;
        ref.read(sosActiveProvider.notifier).state = false;
        ref.read(crashDetectedProvider.notifier).state = false;
        _showSafeDialog();
      },
      onAmbulanceRouting: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const AmbulanceRoutingScreen()),
      ),
    );
  }

  void _showSafeDialog() => showSafeDialog(context);

  Future<void> _sendSafeMessage() async {
    if (_isSendingSafe) return; // prevent double-tap buffering
    _isSendingSafe = true;
    try {
      final contacts = await _getEmergencyContacts();
      if (contacts.isEmpty) return;
      if (!mounted) return;
      final loc = AppLocalizations.of(context);
      final message = loc.safeSmsMessage;
      await _sendAlert(contacts: contacts, message: message, isSafeMessage: true);
    } catch (e) {
      debugPrint('✅ _sendSafeMessage ERROR: $e');
    } finally {
      _isSendingSafe = false; // always reset
    }
  }

  Future<void> _callNumber(String number) async {
    final Uri uri = Uri(scheme: 'tel', path: number);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  void _showLanguagePicker() {
    final loc = AppLocalizations.of(context);
    final currentCode = Localizations.localeOf(context).languageCode;
    showDialog(
      context: context,
      builder: (dialogCtx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          constraints: const BoxConstraints(maxHeight: 520),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A2E),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
                color: const Color(0xFF3B6FFF).withValues(alpha: 0.3)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.language,
                      color: Color(0xFF3B6FFF), size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(loc.selectLanguage,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children:
                      AppLocalizations.supportedLocales.map((locale) {
                    final name =
                        AppLocalizations.languageNames[locale.languageCode] ??
                            locale.languageCode;
                    final isSelected = currentCode == locale.languageCode;
                    return GestureDetector(
                      onTap: () {
                        ref.read(localeProvider.notifier).setLocale(locale.languageCode);
                        Navigator.pop(dialogCtx);
                      },
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFF3B6FFF).withValues(alpha: 0.15)
                              : Colors.white.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected
                                ? const Color(0xFF3B6FFF).withValues(alpha: 0.5)
                                : Colors.white.withValues(alpha: 0.08),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(name,
                                  style: TextStyle(
                                    color: isSelected
                                        ? const Color(0xFF3B6FFF)
                                        : Colors.white,
                                    fontSize: 15,
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  )),
                            ),
                            if (isSelected)
                              const Icon(Icons.check_circle,
                                  color: Color(0xFF3B6FFF), size: 18),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showChannelPicker() {
    final screenHeight = MediaQuery.of(context).size.height;
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Container(
          constraints: BoxConstraints(maxHeight: screenHeight * 0.80),
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A2E),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.send_to_mobile, color: Colors.white70, size: 36),
              const SizedBox(height: 10),
              Builder(builder: (context) => Text(
                AppLocalizations.of(context).alertChannel,
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              )),
              const SizedBox(height: 4),
              Builder(builder: (context) => Text(
                AppLocalizations.of(context).alertChannelSubtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54, fontSize: 12, height: 1.4),
              )),
              const SizedBox(height: 14),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _channelOption(
                          icon: Icons.sms_outlined,
                          label: AppLocalizations.of(context).channelSms,
                          sublabel: AppLocalizations.of(context).channelSmsSub,
                          value: 'sms',
                          color: const Color(0xFF3B6FFF)),
                      const SizedBox(height: 8),
                      _channelOption(
                          icon: Icons.chat_bubble_outline,
                          label: AppLocalizations.of(context).channelWhatsapp,
                          sublabel: AppLocalizations.of(context).channelWhatsappSub,
                          value: 'whatsapp',
                          color: const Color(0xFF25D366)),
                      const SizedBox(height: 8),
                      _channelOption(
                          icon: Icons.message,
                          label: AppLocalizations.of(context).channelBoth,
                          sublabel: AppLocalizations.of(context).channelBothSub,
                          value: 'both',
                          color: const Color(0xFFFF9500)),
                      const SizedBox(height: 8),
                      _channelOption(
                          icon: Icons.email_outlined,
                          label: AppLocalizations.of(context).channelEmail,
                          sublabel: AppLocalizations.of(context).channelEmailSub,
                          value: 'email',
                          color: const Color(0xFFE94B3C)),
                      const SizedBox(height: 8),
                      _channelOption(
                          icon: Icons.all_inclusive_rounded,
                          label: AppLocalizations.of(context).channelAll,
                          sublabel: AppLocalizations.of(context).channelAllSub,
                          value: 'all',
                          color: const Color(0xFF9B59B6)),
                      const SizedBox(height: 4),
                    ],
                  ),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Builder(builder: (context) => Text(
                  AppLocalizations.of(context).done,
                  style: const TextStyle(color: Colors.white54, fontSize: 14),
                )),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _channelOption({
    required IconData icon,
    required String label,
    required String sublabel,
    required String value,
    required Color color,
  }) {
    final isSelected = _alertChannel == value;
    return GestureDetector(
      onTap: () {
        _setAlertChannel(value);
        Navigator.pop(context);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: 0.15)
              : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? color.withValues(alpha: 0.6) : Colors.white12,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon,
                color: isSelected ? color : Colors.white38, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          color: isSelected ? Colors.white : Colors.white60,
                          fontWeight: FontWeight.w600,
                          fontSize: 13)),
                  Text(sublabel,
                      style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 11,
                          height: 1.4)),
                ],
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle, color: color, size: 18),
          ],
        ),
      ),
    );
  }

  // ─── BUILD ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    // Keep a ref-free copy so dispose() can safely check it after unmount.
    _cachedVoiceDetectionOn = _voiceDetectionOn;
    final loc = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      body: SafeArea(
        top: true,
        child: FadeTransition(
          opacity: _fadeAnim,
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildTopBar(loc),
                NightSafetyBanner(onSosTap: startSOS),
                if (_isSosActive) _buildLiveTrackingBanner(loc),
                if (_isCrashDetected) _buildCrashDetectedBanner(loc),
                if (!_crashDetectionEnabled) _buildCrashDetectionOffBanner(),
                _buildSOSSection(loc),
                // ── Voice Detection button ─────────────────────
                _buildVoiceDetectionButton(),
                _buildQuickCallRow(loc),
                _buildSectionTitle(loc.emergencyServices),
                _buildServicesGrid(loc),
                const SizedBox(height: 30),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── VOICE DETECTION BUTTON ───────────────────────────────────────────────
  Widget _buildVoiceDetectionButton() {
    return VoiceButton(
      isOn: _voiceDetectionOn,
      isListening: _isListening,
      onTap: _toggleVoiceDetection,
    );
  }

  Widget _buildCrashDetectionOffBanner() {
    return GestureDetector(
      onTap: _showCrashToggleConfirm,
      child: Container(
        margin: const EdgeInsets.fromLTRB(20, 12, 20, 0),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          children: [
            const Icon(Icons.sensors_off, color: Colors.white30, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Builder(builder: (context) => Text(
                AppLocalizations.of(context).crashDetectionOffBanner,
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              )),
            ),
            const Icon(Icons.chevron_right, color: Colors.white24, size: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(AppLocalizations loc) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(loc.appName,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(loc.appTagline,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Color(0xFF666666), fontSize: 11)),
                  ],
                ),
              ),
              _topIconBtn(
                  tooltip: loc.language,
                  icon: Icons.language,
                  color: const Color(0xFF3B6FFF),
                  bgColor: const Color(0xFF3B6FFF),
                  onTap: _showLanguagePicker),
              const SizedBox(width: 6),
              _topIconBtn(
                  tooltip: AppLocalizations.of(context).profileTooltip,
                  icon: Icons.person_rounded,
                  color: Colors.white70,
                  bgColor: Colors.white,
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const ProfileScreen()))),
              const SizedBox(width: 6),
              _topIconBtn(
                tooltip: 'Safety Mode',
                icon: Icons.shield_moon_rounded,
                color: const Color(0xFFFF6B9D),
                bgColor: const Color(0xFFFF6B9D),
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const ProfileModeScreen())),
              ),
              const SizedBox(width: 6),
              _topIconBtn(
                  tooltip: AppLocalizations.of(context).logoutTooltip,
                  icon: Icons.logout_rounded,
                  color: Colors.white60,
                  bgColor: Colors.white,
                  onTap: () async {
                    final navigator = Navigator.of(context);
                    await AuthService().signOut();
                    navigator.pushAndRemoveUntil(
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                      (route) => false,
                    );
                  }),
            ],
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                GestureDetector(
                  onTap: _showChannelPicker,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white24, width: 1.2),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _alertChannel == 'whatsapp'
                              ? Icons.chat_bubble_outline
                              : _alertChannel == 'both'
                                  ? Icons.message
                                  : _alertChannel == 'email'
                                      ? Icons.email_outlined
                                      : _alertChannel == 'all'
                                          ? Icons.all_inclusive_rounded
                                          : Icons.sms_outlined,
                          color: Colors.white60,
                          size: 13,
                        ),
                        const SizedBox(width: 4),
                        Builder(builder: (context) {
                          final l = AppLocalizations.of(context);
                          return Text(
                            _alertChannel == 'whatsapp' ? l.waShort
                                : _alertChannel == 'both' ? l.smsPlusWaShort
                                : _alertChannel == 'email' ? l.emailShort
                                : _alertChannel == 'all' ? l.allShort
                                : l.channelSms,
                            style: const TextStyle(color: Colors.white60, fontSize: 10, fontWeight: FontWeight.w600),
                          );
                        }),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _showCrashToggleConfirm,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: _crashDetectionEnabled
                          ? const Color(0xFF00C851).withValues(alpha: 0.12)
                          : Colors.white.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: _crashDetectionEnabled
                            ? const Color(0xFF00C851).withValues(alpha: 0.5)
                            : Colors.white24,
                        width: 1.2,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _crashDetectionEnabled
                              ? Icons.sensors
                              : Icons.sensors_off,
                          color: _crashDetectionEnabled
                              ? const Color(0xFF00C851)
                              : Colors.white38,
                          size: 14,
                        ),
                        const SizedBox(width: 4),
                        Builder(builder: (context) => Text(
                          _crashDetectionEnabled ? AppLocalizations.of(context).crashOn : AppLocalizations.of(context).crashOff,
                          style: TextStyle(
                            color: _crashDetectionEnabled ? const Color(0xFF00C851) : Colors.white38,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        )),
                      ],
                    ),
                  ),
                ),
                if (_isSosActive) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF3B3B).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: const Color(0xFFFF3B3B).withValues(alpha: 0.4),
                          width: 1.2),
                    ),
                    child: const Text('🔴 SOS ACTIVE',
                        style: TextStyle(
                            color: Color(0xFFFF3B3B),
                            fontSize: 10,
                            fontWeight: FontWeight.w600)),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _topIconBtn({
    required String tooltip,
    required IconData icon,
    required Color color,
    required Color bgColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Tooltip(
        message: tooltip,
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: bgColor.withValues(alpha: 0.10),
            border: Border.all(color: bgColor.withValues(alpha: 0.30), width: 1.2),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
      ),
    );
  }

  Widget _buildLiveTrackingBanner(AppLocalizations loc) {
    return LiveTrackingBanner(
      onImSafe: () async {
        await LiveTrackingService.stopTracking();
        unawaited(SosFirestoreService.resolveSession()); // ← admin dashboard
        await _sendSafeMessage();
        if (!mounted) return;
        ref.read(sosActiveProvider.notifier).state = false;
        _showSafeDialog();
      },
    );
  }

  // ─── CRASH DETECTED BANNER ───────────────────────────────────────────────
  Widget _buildCrashDetectedBanner(AppLocalizations loc) {
    return CrashDetectedBanner(
      onSosAgain: () {
        ref.read(crashDetectedProvider.notifier).state = false;
        startSOS();
      },
      onImSafe: () async {
        ref.read(crashDetectedProvider.notifier).state = false;
        await LiveTrackingService.stopTracking();
        await _sendSafeMessage();
        if (!mounted) return;
        ref.read(sosActiveProvider.notifier).state = false;
        _showSafeDialog();
      },
    );
  }

  // Returns contacts as {name, number} maps — preserves names for the WA dialog.
  Future<List<Map<String, String>>> _getEmergencyContactsWithNames() async {
    final raw = await _storage.read(key: '${_uid}_emergency_contacts');
    List<String> entries = [];
    if (raw != null && raw.isNotEmpty) {
      entries = raw.split('\n').where((e) => e.isNotEmpty).toList();
    }
    return entries.map((c) {
      if (c.contains('|')) {
        final idx = c.indexOf('|');
        return {'name': c.substring(0, idx), 'number': c.substring(idx + 1)};
      }
      return {'name': c, 'number': c};
    }).where((m) => m['number']!.trim().isNotEmpty).toList();
  }

  // Converts a raw number to WhatsApp international format.
  String _toWaIntl(String number) {
    final cleaned = number.replaceAll(RegExp(r'[^\d+]'), '');
    if (cleaned.startsWith('+')) return cleaned.substring(1);
    if (cleaned.startsWith('0')) return '91${cleaned.substring(1)}';
    if (cleaned.length == 10) return '91$cleaned';
    return cleaned;
  }

  // Opens WhatsApp for a single number with the message pre-filled.
  Future<void> _openWhatsAppFor(String number, String message) async {
    final intl = _toWaIntl(number);
    final uri = Uri.parse('https://wa.me/$intl?text=${Uri.encodeComponent(message)}');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('⚠️ WhatsApp open error for $intl: $e');
    }
  }

  // Shows a bottom-sheet dispatch panel listing every contact.
  // User taps "Open WhatsApp" per contact → WhatsApp opens pre-filled →
  // user hits Send → presses Back → taps next contact.
  // Button turns green (✓ Sent) after tapping so user knows which are done.
  Future<void> _sendViaWhatsApp(List<String> numbers, String message) async {
    if (!mounted) return;

    // If only one contact, skip the dialog and open directly.
    if (numbers.length == 1) {
      await _openWhatsAppFor(numbers.first, message);
      return;
    }

    // For multiple contacts, fetch names to display in the dialog.
    final withNames = await _getEmergencyContactsWithNames();

    // Build a merged list: if names are available use them, else fall back to number.
    final List<Map<String, String>> contacts = numbers.map((number) {
      final match = withNames.firstWhere(
        (m) => m['number'] == number,
        orElse: () => {'name': number, 'number': number},
      );
      return match;
    }).toList();

    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _WhatsAppDispatchSheet(
        contacts: contacts,
        message: message,
        onOpen: _openWhatsAppFor,
      ),
    );
  }

  // ── SOS email persistence (survives app kills/restarts) ──────────────────
  // Stored in FlutterSecureStorage so safe message can still be sent even
  // if Android kills the app after the crash SOS fires.
  static const _kSosEmailKey = 'sos_email_address';

  Future<String> _getSosEmail() async {
    return await _storage.read(key: _kSosEmailKey) ?? '';
  }

  Future<void> _saveSosEmail(String email) async {
    await _storage.write(key: _kSosEmailKey, value: email);
  }

  Future<void> _clearSosEmail() async {
    await _storage.delete(key: _kSosEmailKey);
  }

  /// Called when SOS is triggered via email channel.
  /// Shows ONE popup to ask the email address, then saves to SecureStorage.
  /// Safe message reads from SecureStorage — survives app restarts.
  /// Clears the stored address after safe message is sent.
  Future<void> _sendViaEmail(List<String> contacts, String message,
      {bool isSafeMessage = false}) async {
    if (isSafeMessage) {
      // Safe message: read persisted address from SecureStorage
      final saved = await _getSosEmail();
      if (saved.isEmpty) return; // no address — nothing to send
      final subject = Uri.encodeComponent('\u2705 I\'m Safe \u2014 SOS False Alarm');
      final body = Uri.encodeComponent(message);
      final emailUri = Uri.parse('mailto:$saved?subject=$subject&body=$body');
      try {
        await launchUrl(emailUri, mode: LaunchMode.externalApplication);
      } catch (e) {
        debugPrint('\u26a0\ufe0f Email launch error: $e');
      }
      await _clearSosEmail(); // clear so next SOS asks again
      return;
    }

    // SOS: ask once for the email address
    if (!mounted) return;
    final entered = await _askEmailAddress();
    if (entered == null || entered.trim().isEmpty) return;
    await _saveSosEmail(entered.trim()); // persist to SecureStorage

    final subject = Uri.encodeComponent('\ud83d\udea8 EMERGENCY SOS ALERT');
    final body = Uri.encodeComponent(message);
    final emailUri = Uri.parse('mailto:${entered.trim()}?subject=$subject&body=$body');
    try {
      await launchUrl(emailUri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('\u26a0\ufe0f Email launch error: $e');
    }
  }

  /// Popup that asks for email address when SOS is triggered.
  Future<String?> _askEmailAddress() async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A2E),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
                color: const Color(0xFFFF3B3B).withValues(alpha: 0.4)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.email_outlined,
                  color: Color(0xFFFF3B3B), size: 36),
              const SizedBox(height: 12),
              const Text(
                'Enter Emergency Email',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'SOS and Safe message will both be sent to this address.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.white54, fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                keyboardType: TextInputType.emailAddress,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'example@gmail.com',
                  hintStyle: const TextStyle(color: Colors.white30),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.07),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context, null),
                      style: TextButton.styleFrom(
                        backgroundColor: Colors.white10,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Builder(builder: (context) => Text(
                        AppLocalizations.of(context).cancel,
                        style: const TextStyle(color: Colors.white54),
                      )),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context, controller.text),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF3B3B),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Builder(builder: (context) => Text(
                        AppLocalizations.of(context).yesSendSos,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      )),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
  /// Fallback: fires one sms: URI per contact with a small delay between each.
  /// Android does NOT support comma-separated numbers in the sms: scheme —
  /// only the first number is used. This helper loops to cover all contacts.
  Future<void> _sendViaSmsUri(List<String> contacts, String message) async {
    for (int i = 0; i < contacts.length; i++) {
      final cleaned = contacts[i].trim();
      if (cleaned.isEmpty) continue;
      final smsUri =
          Uri.parse('sms:$cleaned?body=${Uri.encodeComponent(message)}');
      try {
        await launchUrl(smsUri, mode: LaunchMode.externalApplication);
        debugPrint('📨 SMS URI launched for contact ${i + 1}/${contacts.length}: $cleaned');
      } catch (e) {
        debugPrint('⚠️ SMS URI launch failed for $cleaned: $e');
      }
      if (i < contacts.length - 1) {
        await Future.delayed(const Duration(milliseconds: 600));
      }
    }
  }

  Future<void> _sendAlert({
    required List<String> contacts,
    required String message,
    bool isSafeMessage = false,
  }) async {
    switch (_alertChannel) {
      case 'whatsapp':
        await _sendViaWhatsApp(contacts, message);
        break;
      case 'both':
        final smsSent = await _sendNativeSMS(contacts, message);
        if (!smsSent) {
          await _sendViaSmsUri(contacts, message);
        }
        await _sendViaWhatsApp(contacts, message);
        break;
      case 'email':
        await _sendViaEmail(contacts, message, isSafeMessage: isSafeMessage);
        break;
      case 'all':
        final smsSentAll = await _sendNativeSMS(contacts, message);
        if (!smsSentAll) {
          await _sendViaSmsUri(contacts, message);
        }
        await _sendViaWhatsApp(contacts, message);
        await _sendViaEmail(contacts, message, isSafeMessage: isSafeMessage);
        break;
      case 'sms':
      default:
        final sent = await _sendNativeSMS(contacts, message);
        if (!sent) {
          await _sendViaSmsUri(contacts, message);
        }
        break;
    }
  }

  Widget _buildSOSSection(AppLocalizations loc) {
    return SOSSection(
      pulseAnim: _pulseAnim,
      onSosTap: startSOS,
    );
  }

  Future<void> _loadCrashDetectionPref() async {
    if (mounted) {
      await ref.read(crashDetectionProvider.notifier).load();
      await ref.read(alertChannelProvider.notifier).load();
    }
  }

  Future<void> _setCrashDetection(bool value) async {
    await ref.read(crashDetectionProvider.notifier).toggle(value);
    if (value) {
      await CrashForegroundService.start();
    } else {
      await CrashForegroundService.stop();
    }
  }

  Future<void> _setAlertChannel(String channel) async {
    await ref.read(alertChannelProvider.notifier).setChannel(channel);
  }

  Widget _buildQuickCallRow(AppLocalizations loc) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        children: [
          _quickCallBtn(loc.ambulance, '108', const Color(0xFFFF3B3B)),
          const SizedBox(width: 10),
          _quickCallBtn(loc.police, '100', const Color(0xFF3B6FFF)),
          const SizedBox(width: 10),
          _quickCallBtn(loc.fire, '101', const Color(0xFFFF8C3B)),
        ],
      ),
    );
  }

  Widget _quickCallBtn(String label, String number, Color color) {
    final parts = label.split(' ');
    final emoji = parts[0];
    final name = parts.length > 1 ? parts.sublist(1).join(' ') : label;
    return Expanded(
      child: GestureDetector(
        onTap: () => _callNumber(number),
        child: Container(
          padding:
              const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Column(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 20)),
              const SizedBox(height: 4),
              Text(name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: FontWeight.w600)),
              Text(number,
                  style: TextStyle(
                      color: color,
                      fontSize: 13,
                      fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
      child: Text(title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildServicesGrid(AppLocalizations loc) {
    final services = [
      {
        'title': loc.medical,
        'subtitle': loc.medicalSubtitle,
        'icon': Icons.local_hospital_rounded,
        'color': const Color(0xFFFF3B3B),
        'bg': const Color(0xFF2D0F0F),
        'screen': const MedicalScreen(),
      },
      {
        'title': loc.vehicleRescue,
        'subtitle': loc.vehicleSubtitle,
        'icon': Icons.car_repair_rounded,
        'color': const Color(0xFFFF8C3B),
        'bg': const Color(0xFF2D1A0A),
        'screen': const VehicleScreen(),
      },
      {
        'title': loc.safety,
        'subtitle': loc.safetySubtitle,
        'icon': Icons.shield_rounded,
        'color': const Color(0xFF3B6FFF),
        'bg': const Color(0xFF0A0F2D),
        'screen': const SafetyScreen(),
      },
      {
        'title': loc.aiFirstAid,
        'subtitle': loc.aiFirstAidSubtitle,
        'icon': Icons.health_and_safety_rounded,
        'color': const Color(0xFF00C851),
        'bg': const Color(0xFF0A2D16),
        'screen': const AIFirstAidScreen(),
      },
      {
        'title': '👩 Women Safety',
        'subtitle': 'Panic, Safe Walk, Fake Call',
        'icon': Icons.woman_rounded,
        'color': const Color(0xFFFF6B9D),
        'bg': const Color(0xFF2D0A1A),
        'screen': WomenSafetyScreen(onSosTap: startSOS),
      },
      {
        'title': '👦 Child Safety',
        'subtitle': 'Safe route & monitoring',
        'icon': Icons.child_care_rounded,
        'color': const Color(0xFF3B6FFF),
        'bg': const Color(0xFF0A0F2D),
        'screen': SafeRouteScreen(onSosTap: startSOS),
      },
      {
        'title': '🔍 Missing Person',
        'subtitle': 'File a report to police',
        'icon': Icons.person_search_rounded,
        'color': const Color(0xFFFF9F0A),
        'bg': const Color(0xFF2D1F0A),
        'screen': const MissingPersonScreen(),
      },
      {
        'title': '🌙 Night Safety',
        'subtitle': 'Check-in timer & alerts',
        'icon': Icons.nightlight_round,
        'color': const Color(0xFF7B5CFA),
        'bg': const Color(0xFF0F0A2D),
        'screen': NightSafetyScreen(onSosTap: startSOS),
      },
      {
        'title': '🕳️ Pothole Map',
        'subtitle': 'Report & view road hazards',
        'icon': Icons.warning_rounded,
        'color': const Color(0xFFFFB300),
        'bg': const Color(0xFF2D2408),
        'screen': const PotholeMapScreen(),
      },
      {
        'title': '😴 Drowsiness Alert',
        'subtitle': 'Camera-based eye monitoring',
        'icon': Icons.remove_red_eye_rounded,
        'color': const Color(0xFF00E5FF),
        'bg': const Color(0xFF072B2D),
        'screen': const DrowsinessMonitorScreen(),
      },
      {
        'title': '🚑 Ambulance Routing',
        'subtitle': 'Best hospital, live route & ETA',
        'icon': Icons.local_hospital_rounded,
        'color': const Color(0xFF00C851),
        'bg': const Color(0xFF0A2D16),
        'screen': const AmbulanceRoutingScreen(),
      },
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth > 500;
          return GridView.count(
            crossAxisCount: isWide ? 4 : 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: isWide ? 0.9 : 0.75,
            children: services.map((s) {
          final color = s['color'] as Color;
          final bg = s['bg'] as Color;
          final icon = s['icon'] as IconData;
          final screen = s['screen'] as Widget;
          return GestureDetector(
            onTap: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => screen)),
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: color.withValues(alpha: 0.25)),
                boxShadow: [
                  BoxShadow(
                      color: color.withValues(alpha: 0.1),
                      blurRadius: 12,
                      spreadRadius: 1),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(icon, color: color, size: 26),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s['title'] as String,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              height: 1.2)),
                      const SizedBox(height: 3),
                      Text(s['subtitle'] as String,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.4),
                              fontSize: 11)),
                    ],
                  ),
                ],
              ),
            ),
          );
        }).toList(),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// WHATSAPP DISPATCH SHEET
// Shows all emergency contacts with individual "Open WhatsApp" buttons.
// Stays on screen while the user taps each contact, goes to WhatsApp,
// sends the message, comes back, and taps the next one.
// ─────────────────────────────────────────────────────────────────────────────
// ─────────────────────────────────────────────────────────────────────────────
// HOW IT WORKS:
//  1. Sheet opens → immediately launches WhatsApp for contact 0 (pre-filled).
//  2. User taps Send in WhatsApp and presses Back → app resumes.
//  3. AppLifecycleState.resumed fires → marks contact 0 sent →
//     immediately launches WhatsApp for contact 1. No tapping needed.
//  4. Repeats until all contacts done → auto-closes the sheet.
// ─────────────────────────────────────────────────────────────────────────────
class _WhatsAppDispatchSheet extends StatefulWidget {
  final List<Map<String, String>> contacts;
  final String message;
  final Future<void> Function(String number, String message) onOpen;

  const _WhatsAppDispatchSheet({
    required this.contacts,
    required this.message,
    required this.onOpen,
  });

  @override
  State<_WhatsAppDispatchSheet> createState() => _WhatsAppDispatchSheetState();
}

class _WhatsAppDispatchSheetState extends State<_WhatsAppDispatchSheet>
    with WidgetsBindingObserver {
  late final List<bool> _sent;
  int _currentIndex = -1;   // contact currently open in WhatsApp
  bool _appInBackground = false;

  @override
  void initState() {
    super.initState();
    _sent = List.filled(widget.contacts.length, false);
    WidgetsBinding.instance.addObserver(this);
    // Auto-open first contact after the sheet finishes rendering
    WidgetsBinding.instance.addPostFrameCallback((_) => _launchNext());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _appInBackground = true;
    } else if (state == AppLifecycleState.resumed && _appInBackground) {
      _appInBackground = false;
      _onReturnFromWhatsApp();
    }
  }

  void _onReturnFromWhatsApp() {
    if (!mounted) return;
    // Mark current contact as sent
    if (_currentIndex >= 0 && _currentIndex < widget.contacts.length) {
      setState(() => _sent[_currentIndex] = true);
    }
    // Find next unsent
    final nextIndex = _sent.indexWhere((s) => !s);
    if (nextIndex == -1) {
      // All done — auto-close after a moment so user sees green state
      Future.delayed(const Duration(milliseconds: 900), () {
        if (mounted) Navigator.pop(context);
      });
    } else {
      // Auto-launch next contact
      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted) _launchContact(nextIndex);
      });
    }
  }

  Future<void> _launchContact(int index) async {
    if (!mounted) return;
    setState(() => _currentIndex = index);
    final number = widget.contacts[index]['number'] ?? '';
    await widget.onOpen(number, widget.message);
  }

  void _launchNext() {
    final nextIndex = _sent.indexWhere((s) => !s);
    if (nextIndex != -1) _launchContact(nextIndex);
  }

  @override
  Widget build(BuildContext context) {
    final allDone = _sent.every((s) => s);
    final total = widget.contacts.length;
    final doneCount = _sent.where((s) => s).length;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1A0A0A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),

          // Header row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF25D366).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.chat_bubble_rounded,
                    color: Color(0xFF25D366), size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Sending WhatsApp SOS',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold),
                    ),
                    Text(
                      allDone
                          ? 'All $total contacts notified ✓'
                          : 'Send in WhatsApp → press Back → auto continues',
                      style: const TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Progress badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: allDone
                      ? const Color(0xFF00C851).withValues(alpha: 0.2)
                      : Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$doneCount / $total',
                  style: TextStyle(
                    color: allDone ? const Color(0xFF00C851) : Colors.white70,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(color: Colors.white12),
          const SizedBox(height: 8),

          // Contact list
          ...List.generate(total, (i) {
            final contact = widget.contacts[i];
            final name = contact['name'] ?? '';
            final number = contact['number'] ?? '';
            final done = _sent[i];
            final isCurrent = _currentIndex == i && !done;

            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: done
                      ? const Color(0xFF00C851).withValues(alpha: 0.07)
                      : isCurrent
                          ? const Color(0xFF25D366).withValues(alpha: 0.10)
                          : Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: done
                        ? const Color(0xFF00C851).withValues(alpha: 0.3)
                        : isCurrent
                            ? const Color(0xFF25D366).withValues(alpha: 0.5)
                            : Colors.transparent,
                  ),
                ),
                child: Row(
                  children: [
                    // Status icon
                    Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: done
                            ? const Color(0xFF00C851).withValues(alpha: 0.15)
                            : isCurrent
                                ? const Color(0xFF25D366).withValues(alpha: 0.15)
                                : Colors.white.withValues(alpha: 0.06),
                      ),
                      child: Icon(
                        done
                            ? Icons.check_circle_rounded
                            : isCurrent
                                ? Icons.send_rounded
                                : Icons.person_rounded,
                        color: done
                            ? const Color(0xFF00C851)
                            : isCurrent
                                ? const Color(0xFF25D366)
                                : Colors.white38,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Name + number
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name.isNotEmpty ? name : number,
                            style: TextStyle(
                              color: done
                                  ? Colors.white38
                                  : isCurrent ? Colors.white : Colors.white60,
                              fontSize: 14,
                              fontWeight: isCurrent
                                  ? FontWeight.bold
                                  : FontWeight.w500,
                              decoration: done
                                  ? TextDecoration.lineThrough
                                  : TextDecoration.none,
                            ),
                          ),
                          if (name.isNotEmpty)
                            Text(number,
                                style: const TextStyle(
                                    color: Colors.white30, fontSize: 11)),
                        ],
                      ),
                    ),

                    // Status chip
                    if (done)
                      const Text('✓ Sent',
                          style: TextStyle(
                              color: Color(0xFF00C851),
                              fontWeight: FontWeight.bold,
                              fontSize: 12))
                    else if (isCurrent)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF25D366),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text('Opening…',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 11)),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text('Waiting',
                            style: TextStyle(
                                color: Colors.white30, fontSize: 11)),
                      ),
                  ],
                ),
              ),
            );
          }),

          const SizedBox(height: 12),

          // Re-open button (in case user closed WhatsApp without sending)
          if (!allDone)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _launchNext,
                icon: const Icon(Icons.refresh_rounded,
                    size: 16, color: Color(0xFF25D366)),
                label: const Text('Re-open WhatsApp',
                    style: TextStyle(color: Color(0xFF25D366), fontSize: 13)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFF25D366), width: 1),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),

          const SizedBox(height: 8),

          // Close button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: allDone
                    ? const Color(0xFF00C851)
                    : Colors.white.withValues(alpha: 0.08),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: Text(
                allDone ? '✓ All Sent — Close' : 'Close',
                style: TextStyle(
                  color: allDone ? Colors.white : Colors.white54,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}