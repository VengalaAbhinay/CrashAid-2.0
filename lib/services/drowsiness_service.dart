import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:flutter/foundation.dart';

/// DrowsinessService
///
/// Wraps ML Kit's on-device face detector to monitor, over time:
///  - Eye-open probability (blink / sustained eye closure)
///  - Mouth aspect ratio (yawn detection)
///  - Head pitch (head euler angle X) for "head dropping"
///  - Head yaw (head euler angle Y) for "distraction" — looking away
///    from the road
///
/// A single closed-eye frame is NOT drowsiness (that's just a blink), a
/// single wide-mouth frame is NOT a yawn (could be talking/laughing), and
/// a single turned-head frame is NOT distraction (could be checking a
/// mirror). Every signal only fires after it holds for a sustained
/// *duration*, not a fixed frame count — frames may arrive at very
/// different rates depending on the capture source (continuous stream
/// vs. periodic still capture used for Dashcam Mode), so time-based
/// thresholds stay correct either way.
class DrowsinessService {
  DrowsinessService({
    this.eyeOpenThreshold = 0.4,
    this.sustainedEyeClosureDuration = const Duration(milliseconds: 1500),
    this.mouthAspectRatioThreshold = 0.55,
    this.sustainedYawnDuration = const Duration(milliseconds: 1200),
    this.headDropPitchThreshold = -18.0,
    this.sustainedHeadDropDuration = const Duration(milliseconds: 1500),
    this.distractionYawThreshold = 28.0,
    this.sustainedDistractionDuration = const Duration(seconds: 2),
  }) : _faceDetector = FaceDetector(
          options: FaceDetectorOptions(
            enableClassification: true, // required for eye-open probability
            enableContours: true, // required for lip contour points (MAR)
            enableLandmarks: true, // required for mouth corner points (MAR)
            performanceMode: FaceDetectorMode.accurate, // also improves head-euler-angle accuracy
          ),
        );

  /// Below this probability (0.0–1.0), an eye is considered closed.
  final double eyeOpenThreshold;

  /// How long eyes must stay closed, continuously, before we call it
  /// drowsiness. ~1.5s filters out normal blinks.
  final Duration sustainedEyeClosureDuration;

  /// Mouth aspect ratio (vertical gap / mouth width) above which the
  /// mouth is considered "open wide" — i.e. mid-yawn rather than talking.
  final double mouthAspectRatioThreshold;

  /// How long the mouth must stay "wide open" before we call it a yawn.
  final Duration sustainedYawnDuration;

  /// Head pitch (headEulerAngleX, degrees) below this value means the
  /// chin has dropped toward the chest. Negative = tilted down.
  final double headDropPitchThreshold;

  /// How long the head must stay dropped before it counts as a
  /// drowsiness signal (same treatment as sustained eye closure).
  final Duration sustainedHeadDropDuration;

  /// Head yaw (headEulerAngleY, degrees) beyond which the driver's face
  /// is considered turned away from the road, in either direction.
  final double distractionYawThreshold;

  /// How long the head must stay turned away before it counts as
  /// distraction. Longer than the drowsiness windows on purpose — a
  /// quick shoulder-check or mirror glance is normal driving, not
  /// distraction.
  final Duration sustainedDistractionDuration;

  final FaceDetector _faceDetector;

  DateTime? _closedSince;
  bool _alertActive = false;

  DateTime? _yawnSince;
  bool _yawnActive = false;

  DateTime? _headDropSince;
  bool _headDropActive = false;

  DateTime? _distractedSince;
  bool _distractionActive = false;

  /// Total yawns counted this session (rising edges only).
  int yawnCount = 0;

  /// Called once when drowsiness is first detected (rising edge) — from
  /// sustained eye closure OR sustained head-dropping. Both are treated
  /// as the same "drowsy" state since either one means the driver isn't
  /// watching the road.
  void Function()? onDrowsinessDetected;

  /// Called once when the drowsy state clears (eyes reopen AND head is
  /// back up) — use this to dismiss the warning UI.
  void Function()? onAlertCleared;

  /// Called once when a sustained yawn is first detected (rising edge).
  void Function()? onYawnDetected;

  /// Called once when the mouth closes again after a detected yawn.
  void Function()? onYawnCleared;

  /// Called once when the driver's head has been turned away from the
  /// road (left/right) for longer than [sustainedDistractionDuration].
  void Function()? onDistractionDetected;

  /// Called once when the driver's head returns to facing the road.
  void Function()? onDistractionCleared;

  /// Called every processed frame with the latest readings — useful for
  /// driving live status indicators in the UI. `headPitch`/`headYaw` are
  /// null if no face was found this frame.
  void Function(
    double? avgEyeOpenProb,
    bool faceFound,
    double? mouthAspectRatio,
    double? headPitch,
    double? headYaw,
  )? onFrameProcessed;

  bool _isBusy = false;

  /// Feed one camera frame (already converted to InputImage) into the
  /// detector. Safe to call rapidly — frames are dropped while a
  /// previous frame is still being processed, so this never backs up
  /// the camera feed.
  Future<void> processFrame(InputImage inputImage) async {
    if (_isBusy) return;
    _isBusy = true;

    try {
      final faces = await _faceDetector.processImage(inputImage);
      debugPrint('🟢 DROWSINESS_DEBUG: faces found = ${faces.length}');

      if (faces.isEmpty) {
        // No face visible — don't guess. Reset every timer rather than
        // treating "no face" as "eyes closed"/"yawning"/"distracted",
        // since that would false-trigger if the driver's face is
        // briefly out of frame (e.g. a bump in the road).
        _closedSince = null;
        _yawnSince = null;
        _headDropSince = null;
        _distractedSince = null;
        onFrameProcessed?.call(null, false, null, null, null);
        return;
      }

      final face = faces.first;
      final leftOpen = face.leftEyeOpenProbability;
      final rightOpen = face.rightEyeOpenProbability;

      double? avgOpen;
      if (leftOpen != null && rightOpen != null) {
        avgOpen = (leftOpen + rightOpen) / 2;
      }

      final mar = _computeMouthAspectRatio(face);
      final pitch = face.headEulerAngleX; // up/down tilt
      final yaw = face.headEulerAngleY; // left/right turn
      final now = DateTime.now();

      onFrameProcessed?.call(avgOpen, true, mar, pitch, yaw);

      debugPrint(
        '🔵 DROWSINESS_DEBUG: avgOpen=$avgOpen mar=$mar pitch=$pitch yaw=$yaw',
      );

      // --- Eye closure tracking ---
      bool eyesClosed = false;
      if (avgOpen != null) {
        eyesClosed = avgOpen < eyeOpenThreshold;
      }

      // --- Head-drop tracking (folded into the same drowsy state) ---
      bool headDropped = false;
      if (pitch != null) {
        headDropped = pitch < headDropPitchThreshold;
      }
      _updateHeadDrop(headDropped, now);

      // Drowsy = sustained eye closure OR sustained head drop.
      _updateDrowsyState(eyesClosed, now);

      // --- Yawn tracking ---
      if (mar != null) {
        _updateYawn(mar > mouthAspectRatioThreshold, now);
      } else {
        debugPrint('⚪ DROWSINESS_DEBUG: mar is null — lip contours/landmarks unavailable this frame');
      }

      // --- Distraction tracking (head turned away from the road) ---
      bool turnedAway = false;
      if (yaw != null) {
        turnedAway = yaw.abs() > distractionYawThreshold;
      }
      _updateDistraction(turnedAway, now);
    } catch (e) {
      debugPrint('🔴 DrowsinessService: processFrame failed — $e');
    } finally {
      _isBusy = false;
    }
  }

  void _updateDrowsyState(bool eyesClosed, DateTime now) {
    if (eyesClosed) {
      _closedSince ??= now;
    } else {
      _closedSince = null;
    }

    final eyeSustained = _closedSince != null &&
        now.difference(_closedSince!) >= sustainedEyeClosureDuration;
    final headSustained = _headDropActive; // already duration-checked below

    final shouldBeActive = eyeSustained || headSustained;

    if (shouldBeActive && !_alertActive) {
      _alertActive = true;
      debugPrint('🚨 DROWSINESS_DEBUG: onDrowsinessDetected firing');
      onDrowsinessDetected?.call();
    } else if (!shouldBeActive && _alertActive) {
      _alertActive = false;
      onAlertCleared?.call();
    }
  }

  void _updateHeadDrop(bool headDropped, DateTime now) {
    if (headDropped) {
      _headDropSince ??= now;
    } else {
      _headDropSince = null;
    }

    final sustained = _headDropSince != null &&
        now.difference(_headDropSince!) >= sustainedHeadDropDuration;

    if (sustained && !_headDropActive) {
      _headDropActive = true;
      debugPrint('🚨 DROWSINESS_DEBUG: head-drop sustained — feeding into drowsy state');
    } else if (!sustained && _headDropActive) {
      _headDropActive = false;
    }
  }

  void _updateYawn(bool mouthWideOpen, DateTime now) {
    if (mouthWideOpen) {
      _yawnSince ??= now;
    } else {
      _yawnSince = null;
      if (_yawnActive) {
        _yawnActive = false;
        onYawnCleared?.call();
      }
    }

    final sustained = _yawnSince != null &&
        now.difference(_yawnSince!) >= sustainedYawnDuration;

    if (sustained && !_yawnActive) {
      _yawnActive = true;
      yawnCount++;
      debugPrint('🥱 DROWSINESS_DEBUG: onYawnDetected firing');
      onYawnDetected?.call();
    }
  }

  void _updateDistraction(bool turnedAway, DateTime now) {
    if (turnedAway) {
      _distractedSince ??= now;
    } else {
      _distractedSince = null;
      if (_distractionActive) {
        _distractionActive = false;
        onDistractionCleared?.call();
      }
    }

    final sustained = _distractedSince != null &&
        now.difference(_distractedSince!) >= sustainedDistractionDuration;

    if (sustained && !_distractionActive) {
      _distractionActive = true;
      debugPrint('🚨 DROWSINESS_DEBUG: onDistractionDetected firing');
      onDistractionDetected?.call();
    }
  }

  /// Mouth aspect ratio (MAR): vertical mouth opening divided by mouth
  /// width — the same idea as eye-aspect-ratio blink detection, applied
  /// to the mouth.
  ///
  /// Uses the INNER lip contour (upperLipBottom / lowerLipTop) for the
  /// vertical gap rather than the outer lip, because the outer lip stays
  /// visually "tall" even with the mouth closed, which would make talking
  /// or smiling look like a yawn. Mouth corners (landmarks) give the width.
  double? _computeMouthAspectRatio(Face face) {
    final upperLipBottom = face.contours[FaceContourType.upperLipBottom]?.points;
    final lowerLipTop = face.contours[FaceContourType.lowerLipTop]?.points;
    final mouthLeft = face.landmarks[FaceLandmarkType.leftMouth]?.position;
    final mouthRight = face.landmarks[FaceLandmarkType.rightMouth]?.position;

    if (upperLipBottom == null ||
        upperLipBottom.isEmpty ||
        lowerLipTop == null ||
        lowerLipTop.isEmpty ||
        mouthLeft == null ||
        mouthRight == null) {
      return null;
    }

    double avgY(List<dynamic> points) =>
        points.map((p) => p.y as int).reduce((a, b) => a + b) / points.length;

    final verticalGap = (avgY(lowerLipTop) - avgY(upperLipBottom)).abs();
    final width = (mouthRight.x - mouthLeft.x).abs();

    if (width == 0) return null;
    return verticalGap / width;
  }

  /// Resets internal state — call when the monitoring screen is closed
  /// or when explicitly dismissing an alert.
  void reset() {
    _closedSince = null;
    _alertActive = false;
    _yawnSince = null;
    _yawnActive = false;
    _headDropSince = null;
    _headDropActive = false;
    _distractedSince = null;
    _distractionActive = false;
  }

  Future<void> dispose() async {
    await _faceDetector.close();
  }
}
