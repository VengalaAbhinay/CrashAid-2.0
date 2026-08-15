import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'crash_foreground_service.dart';

/// DashcamService
///
/// Records rolling short video clips (default 20s each) from the phone
/// camera while Drive Mode is active, keeping only the most recent
/// [maxRollingClips] clips on disk — older clips are deleted
/// automatically as new ones are recorded, so the app never accumulates
/// hours of footage.
///
/// When a crash is detected (via [CrashForegroundService]), every clip
/// currently in the rolling buffer — which spans the moments
/// immediately before and during the impact — is moved out of the
/// rolling buffer into permanent local storage and best-effort uploaded
/// to Firebase Storage, tagged with the crash timestamp.
///
/// Engineering note: a single camera session cannot run a continuous
/// `startImageStream` (used for real-time face analysis) at the same
/// time as `startVideoRecording`. While Dashcam Mode is recording,
/// [captureAnalysisFrame] should be used instead of an image stream to
/// pull still frames for drowsiness/distraction analysis — see
/// DrowsinessMonitorScreen for how the two are combined.
class DashcamService {
  DashcamService({
    this.clipDuration = const Duration(seconds: 20),
    this.maxRollingClips = 3,
  });

  final Duration clipDuration;
  final int maxRollingClips;

  CameraController? _controller;
  Timer? _segmentTimer;
  final List<File> _rollingClips = [];
  bool _isRecording = false;
  bool _isRotating = false;

  // Kept so `stop()` can unregister exactly this listener. A new
  // DashcamService is created every time Drive Mode is opened (see
  // DrowsinessMonitorScreen.initState), so without removing it on
  // stop(), each Drive Mode session would leave behind a stale listener
  // still attached to CrashForegroundService — and after a few
  // open/close cycles, a single crash would fire preservation multiple
  // times against disposed camera sessions.
  CrashEventListener? _crashListener;

  bool get isRecording => _isRecording;

  /// Attach an already-initialized [CameraController]. The controller
  /// must not already be running an image stream.
  void attachController(CameraController controller) {
    _controller = controller;
  }

  Future<void> start() async {
    final controller = _controller;
    if (controller == null || _isRecording) return;

    _isRecording = true;
    await _startSegment();
    _segmentTimer = Timer.periodic(clipDuration, (_) => _rotateSegment());

    if (_crashListener == null) {
      // Multiple parts of the app can listen for crash events —
      // CrashForegroundService fans the event out to every registered
      // listener, so this doesn't disturb the app's main SOS listener.
      _crashListener = (numbers, location, type) {
        if (type == 'crash_detected') {
          preserveClipsForCrash(location: location);
        }
      };
      CrashForegroundService.listenForCrash(_crashListener!);
    }
  }

  Future<void> _startSegment() async {
    final controller = _controller;
    if (controller == null) return;
    if (controller.value.isRecordingVideo) return;
    try {
      await controller.startVideoRecording();
    } catch (e) {
      debugPrint('🔴 DashcamService: startVideoRecording failed — $e');
    }
  }

  Future<void> _rotateSegment() async {
    final controller = _controller;
    if (controller == null || _isRotating || !controller.value.isRecordingVideo) {
      return;
    }
    _isRotating = true;
    try {
      final raw = await controller.stopVideoRecording();
      final savedFile = await _persistToRollingBuffer(File(raw.path));
      _rollingClips.add(savedFile);
      while (_rollingClips.length > maxRollingClips) {
        final oldest = _rollingClips.removeAt(0);
        if (await oldest.exists()) await oldest.delete();
      }
      if (_isRecording) await _startSegment();
    } catch (e) {
      debugPrint('🔴 DashcamService: segment rotation failed — $e');
    } finally {
      _isRotating = false;
    }
  }

  Future<File> _persistToRollingBuffer(File tempFile) async {
    final dir = await _rollingDir();
    final name = 'clip_${DateTime.now().millisecondsSinceEpoch}.mp4';
    final dest = File('${dir.path}/$name');
    final saved = await tempFile.copy(dest.path);
    unawaited(tempFile.delete().catchError((_) => tempFile));
    return saved;
  }

  Future<Directory> _rollingDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/dashcam_rolling');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<Directory> _crashDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/crash_footage');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Moves every clip currently in the rolling buffer into permanent
  /// crash-footage storage (so the ring buffer's auto-delete can never
  /// touch them), then best-effort uploads each clip to Firebase
  /// Storage tagged with the crash timestamp and location. Safe to call
  /// even if Dashcam Mode isn't recording — it just does nothing.
  Future<void> preserveClipsForCrash({String? location}) async {
    if (_rollingClips.isEmpty) return;
    final crashId = DateTime.now().millisecondsSinceEpoch;
    final crashDir = await _crashDir();
    final clipsSnapshot = List<File>.from(_rollingClips);

    for (final clip in clipsSnapshot) {
      try {
        if (!await clip.exists()) continue;
        final fileName = clip.uri.pathSegments.last;
        final dest = File('${crashDir.path}/crash_${crashId}_$fileName');
        final preserved = await clip.copy(dest.path);
        _rollingClips.remove(clip);
        unawaited(_uploadClipInBackground(preserved, crashId));
      } catch (e) {
        debugPrint('🔴 DashcamService: failed to preserve clip — $e');
      }
    }
    debugPrint(
      '🎥 DashcamService: preserved ${clipsSnapshot.length} clip(s) for crash $crashId '
      '(location: ${location ?? "unavailable"})',
    );
  }

  Future<void> _uploadClipInBackground(File clip, int crashId) async {
    try {
      final fileName = clip.uri.pathSegments.last;
      final ref = FirebaseStorage.instance.ref('crash_footage/$crashId/$fileName');
      await ref.putFile(clip);
      debugPrint('☁️ DashcamService: uploaded ${clip.path}');
    } catch (e) {
      // Best-effort — the clip is already safe on-device either way.
      debugPrint('🟡 DashcamService: upload skipped/failed (kept locally) — $e');
    }
  }

  /// Captures a single still frame for drowsiness/distraction analysis
  /// without stopping the active video recording. Returns null (and
  /// logs) on the occasional failure — expected right at segment
  /// rotation boundaries — so callers should just skip that cycle.
  Future<XFile?> captureAnalysisFrame() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return null;
    try {
      return await controller.takePicture();
    } catch (e) {
      debugPrint('🟡 DashcamService: captureAnalysisFrame skipped — $e');
      return null;
    }
  }

  /// Stops recording and flushes the in-progress segment into the
  /// rolling buffer. Also unregisters this instance's crash listener —
  /// call this from the screen's dispose() so closed Drive Mode
  /// sessions never keep listening for crash events in the background.
  Future<void> stop() async {
    _isRecording = false;
    _segmentTimer?.cancel();
    _segmentTimer = null;

    if (_crashListener != null) {
      CrashForegroundService.removeCrashListener(_crashListener!);
      _crashListener = null;
    }

    final controller = _controller;
    if (controller != null && controller.value.isRecordingVideo) {
      try {
        final raw = await controller.stopVideoRecording();
        final saved = await _persistToRollingBuffer(File(raw.path));
        _rollingClips.add(saved);
        while (_rollingClips.length > maxRollingClips) {
          final oldest = _rollingClips.removeAt(0);
          if (await oldest.exists()) await oldest.delete();
        }
      } catch (_) {}
    }
  }

  /// Deletes every clip left in the rolling buffer (does not touch
  /// footage already preserved for a crash).
  Future<void> clearRollingBuffer() async {
    for (final clip in List<File>.from(_rollingClips)) {
      if (await clip.exists()) await clip.delete();
    }
    _rollingClips.clear();
  }
}
