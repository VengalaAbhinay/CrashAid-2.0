import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../services/drowsiness_service.dart';
import '../services/dashcam_service.dart';

/// Drive Mode: SafeDrive AI.
///
/// Runs three features off one front-camera session:
///  1. Dashcam Recording — rolling short video clips (DashcamService),
///     auto-preserved + uploaded if a crash is detected mid-drive.
///  2. Drowsiness Detection — sustained eye closure / head drop.
///  3. Distraction Detection — head turned away from the road too long.
///
/// A single camera session can't run a continuous image stream at the
/// same time as active video recording, so while Dashcam Mode is
/// recording, analysis frames are pulled periodically via
/// DashcamService.captureAnalysisFrame() (a still capture) instead of
/// controller.startImageStream(). This trades a lower, irregular
/// analysis frame rate for having both features run together — which is
/// why DrowsinessService's thresholds are duration-based rather than
/// frame-count based.
class DrowsinessMonitorScreen extends StatefulWidget {
  const DrowsinessMonitorScreen({super.key});

  @override
  State<DrowsinessMonitorScreen> createState() => _DrowsinessMonitorScreenState();
}

class _DrowsinessMonitorScreenState extends State<DrowsinessMonitorScreen> {
  CameraController? _cameraController;
  late final DrowsinessService _drowsinessService;
  late final DashcamService _dashcamService;
  late final FlutterTts _tts;

  bool _isInitializing = true;
  String? _errorMessage;

  bool _isAlerting = false;
  bool _isDistracted = false;
  double? _lastEyeOpenProb;
  double? _lastMouthAspectRatio;
  double? _lastHeadPitch;
  double? _lastHeadYaw;
  bool _faceFound = false;

  bool _isYawning = false;
  int _yawnCount = 0;

  Timer? _alarmTimer;
  Timer? _analysisTimer;
  bool _analysisInFlight = false;

  /// How often we pull a still frame for face analysis while Dashcam
  /// Mode is recording. Lower than a live stream's frame rate on
  /// purpose — see class doc for why.
  static const Duration _analysisInterval = Duration(milliseconds: 600);

  @override
  void initState() {
    super.initState();

    _tts = FlutterTts();
    _tts.setSpeechRate(0.45);
    _tts.setVolume(1.0);
    _tts.setPitch(1.0);

    _dashcamService = DashcamService();

    _drowsinessService = DrowsinessService();
    _drowsinessService.onDrowsinessDetected = () {
      if (mounted) setState(() => _isAlerting = true);
      _startAlarm('Please stay alert. You appear to be drowsy.');
    };
    _drowsinessService.onAlertCleared = () {
      if (mounted) setState(() => _isAlerting = false);
      _stopAlarm();
    };
    _drowsinessService.onYawnDetected = () {
      if (mounted) {
        setState(() {
          _isYawning = true;
          _yawnCount = _drowsinessService.yawnCount;
        });
      }
      // A yawn alone isn't a full alert overlay, but it IS a fatigue
      // signal — give a lighter one-shot spoken nudge rather than the
      // full repeating alarm used for sustained eye closure/head drop.
      _tts.speak('You seem tired. Consider taking a break.');
      HapticFeedback.mediumImpact();
    };
    _drowsinessService.onYawnCleared = () {
      if (mounted) setState(() => _isYawning = false);
    };
    _drowsinessService.onDistractionDetected = () {
      if (mounted) setState(() => _isDistracted = true);
      HapticFeedback.mediumImpact();
      _tts.speak('Eyes on the road, please.');
    };
    _drowsinessService.onDistractionCleared = () {
      if (mounted) setState(() => _isDistracted = false);
    };
    _drowsinessService.onFrameProcessed = (avgOpen, faceFound, mar, pitch, yaw) {
      if (mounted) {
        setState(() {
          _lastEyeOpenProb = avgOpen;
          _faceFound = faceFound;
          _lastMouthAspectRatio = mar;
          _lastHeadPitch = pitch;
          _lastHeadYaw = yaw;
        });
      }
    };

    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      final frontCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        frontCamera,
        ResolutionPreset.medium, // low res can miss close-up faces; medium is more reliable
        enableAudio: false,
      );

      await controller.initialize();

      if (!mounted) return;

      setState(() {
        _cameraController = controller;
        _isInitializing = false;
      });

      _dashcamService.attachController(controller);
      await _dashcamService.start();

      _analysisTimer = Timer.periodic(_analysisInterval, (_) => _captureAndAnalyze());
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Could not start camera: $e';
          _isInitializing = false;
        });
      }
    }
  }

  Future<void> _captureAndAnalyze() async {
    if (_analysisInFlight) return;
    _analysisInFlight = true;
    try {
      final still = await _dashcamService.captureAnalysisFrame();
      if (still == null) return;

      final inputImage = InputImage.fromFilePath(still.path);
      await _drowsinessService.processFrame(inputImage);

      // The still is only needed for this one analysis pass — the
      // actual footage lives in the dashcam's rolling video clips, so
      // clean this temp file up immediately rather than letting it
      // accumulate on disk.
      unawaited(File(still.path).delete().catchError((_) => File(still.path)));
    } catch (e) {
      debugPrint('🔴 DriveMode: analysis frame failed — $e');
    } finally {
      _analysisInFlight = false;
    }
  }

  /// Starts a repeating spoken alarm + vibration while drowsiness is
  /// active. Uses flutter_tts instead of SystemSound — SystemSound.play
  /// is meant for tiny UI feedback blips and is inaudible/suppressed on
  /// many Android OEM skins, so it's not reliable as an actual alarm.
  /// TTS is guaranteed audible and needs no bundled audio asset.
  void _startAlarm(String message) {
    _alarmTimer?.cancel();
    _speakAlarm(message); // fire immediately, then repeat
    _alarmTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _speakAlarm(message);
    });
  }

  Future<void> _speakAlarm(String message) async {
    HapticFeedback.heavyImpact();
    await _tts.speak(message);
  }

  void _stopAlarm() {
    _alarmTimer?.cancel();
    _alarmTimer = null;
    _tts.stop();
  }

  Future<void> _stopCamera() async {
    _analysisTimer?.cancel();
    _analysisTimer = null;
    await _dashcamService.stop();
    await _cameraController?.dispose();
  }

  @override
  void dispose() {
    _stopAlarm();
    _stopCamera();
    _tts.stop();
    _drowsinessService.dispose();
    super.dispose();
  }

  void _dismissAlert() {
    _drowsinessService.reset();
    _stopAlarm();
    setState(() {
      _isAlerting = false;
      _isYawning = false;
      _isDistracted = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D0D),
        title: const Text('Drive Mode'),
      ),
      body: _isInitializing
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _errorMessage!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.grey, fontSize: 14),
                    ),
                  ),
                )
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    if (_cameraController != null)
                      CameraPreview(_cameraController!),

                    // Dashcam REC indicator (top-left)
                    Positioned(
                      top: 16,
                      left: 16,
                      child: _buildRecIndicator(),
                    ),

                    // Status pill (top-center)
                    Positioned(
                      top: 16,
                      left: 90,
                      right: 90,
                      child: _buildStatusPill(),
                    ),

                    // Yawn counter (top-right, small)
                    Positioned(
                      top: 16,
                      right: 16,
                      child: _buildYawnCounter(),
                    ),

                    // Distraction banner (just under the status pill)
                    if (_isDistracted && !_isAlerting)
                      Positioned(
                        top: 64,
                        left: 16,
                        right: 16,
                        child: _buildDistractionBanner(),
                      ),

                    // Full-screen drowsy alert overlay
                    if (_isAlerting) _buildAlertOverlay(),
                  ],
                ),
    );
  }

  Widget _buildRecIndicator() {
    final recording = _dashcamService.isRecording;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.fiber_manual_record,
              color: recording ? Colors.redAccent : Colors.grey, size: 14),
          const SizedBox(width: 6),
          Text(
            recording ? 'REC' : 'OFF',
            style: TextStyle(
              color: recording ? Colors.redAccent : Colors.grey,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusPill() {
    String label;
    Color color;

    if (!_faceFound) {
      label = 'No face detected';
      color = Colors.grey;
    } else if (_isDistracted) {
      label = 'Eyes off road';
      color = Colors.deepOrange;
    } else if (_isYawning) {
      label = 'Yawning';
      color = Colors.amber;
    } else if (_lastEyeOpenProb == null) {
      label = 'Analyzing...';
      color = Colors.grey;
    } else if (_lastEyeOpenProb! < 0.4) {
      label = 'Eyes closing';
      color = Colors.orange;
    } else {
      label = 'Alert';
      color = Colors.green;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color, width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _isDistracted
                ? Icons.visibility_off
                : _isYawning
                    ? Icons.sentiment_very_dissatisfied
                    : Icons.remove_red_eye,
            color: color,
            size: 18,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              style: TextStyle(color: color, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildYawnCounter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🥱', style: TextStyle(fontSize: 14)),
          const SizedBox(width: 6),
          Text(
            '$_yawnCount',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildDistractionBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.deepOrange.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.white, size: 18),
          SizedBox(width: 8),
          Text(
            'Eyes on the road — you looked away too long',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildAlertOverlay() {
    return Container(
      color: Colors.red.withValues(alpha: 0.85),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 72),
            const SizedBox(height: 16),
            const Text(
              'Please stay alert.\nYou appear to be drowsy.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _dismissAlert,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.red,
              ),
              child: const Text("I'm awake"),
            ),
          ],
        ),
      ),
    );
  }
}
