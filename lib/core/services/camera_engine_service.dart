import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:test123/core/services/document_scanner_service.dart';

// ── Data Types ────────────────────────────────────────────────────────────────

/// Result of a single frame analysis pass.
class FrameAnalysisResult {
  final bool slideChanged;
  final double delta;
  const FrameAnalysisResult({required this.slideChanged, required this.delta});
}

/// Emitted when phone is steady (motion below threshold for [steadyDuration]).
class StabilityEvent {
  final bool isStable;
  const StabilityEvent(this.isStable);
}

/// Scan modes.
enum ScanMode { manual, auto }

/// Region of interest (normalized 0–1) for frame-diff comparison.
class RoiRect {
  final double left;
  final double top;
  final double right;
  final double bottom;

  const RoiRect({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  /// Full frame
  static const full = RoiRect(left: 0, top: 0, right: 1, bottom: 1);

  bool get isValid =>
      right > left && bottom > top && left >= 0 && top >= 0 && right <= 1 && bottom <= 1;
}

// ── Background isolate payload ────────────────────────────────────────────────

class _FrameDiffPayload {
  final Uint8List currentY;
  final Uint8List referenceY;
  final int frameWidth;
  final int frameHeight;
  final double threshold;
  final double roiLeft;
  final double roiTop;
  final double roiRight;
  final double roiBottom;

  const _FrameDiffPayload({
    required this.currentY,
    required this.referenceY,
    required this.frameWidth,
    required this.frameHeight,
    required this.threshold,
    required this.roiLeft,
    required this.roiTop,
    required this.roiRight,
    required this.roiBottom,
  });
}

FrameAnalysisResult _computeFrameDiff(_FrameDiffPayload p) {
  final int startX = (p.roiLeft * p.frameWidth).toInt().clamp(0, p.frameWidth - 1);
  final int startY = (p.roiTop * p.frameHeight).toInt().clamp(0, p.frameHeight - 1);
  final int endX = (p.roiRight * p.frameWidth).toInt().clamp(startX + 1, p.frameWidth);
  final int endY = (p.roiBottom * p.frameHeight).toInt().clamp(startY + 1, p.frameHeight);

  if (p.currentY.length != p.referenceY.length) {
    return const FrameAnalysisResult(slideChanged: false, delta: 0);
  }

  double totalDiff = 0;
  int samples = 0;

  // Subsample every 8th pixel within ROI for speed
  for (int y = startY; y < endY; y += 4) {
    for (int x = startX; x < endX; x += 4) {
      final idx = y * p.frameWidth + x;
      if (idx >= p.currentY.length) continue;
      totalDiff += (p.currentY[idx] - p.referenceY[idx]).abs();
      samples++;
    }
  }

  final double delta = samples > 0 ? (totalDiff / samples) / 255.0 : 0;
  return FrameAnalysisResult(
    slideChanged: delta > p.threshold,
    delta: delta,
  );
}

// ── Camera Engine ─────────────────────────────────────────────────────────────

class CameraEngineService {
  CameraEngineService._();
  static final CameraEngineService instance = CameraEngineService._();

  CameraController? _controller;
  bool _isStreaming = false;
  bool _isProcessing = false;
  bool _flashEnabled = false;

  Uint8List? _referenceYPlane;
  DateTime? _changeDetectedAt;

  // Tunable parameters
  double threshold = 0.18;
  Duration stabilityWindow = const Duration(milliseconds: 1200);

  // ROI for frame diff (only analyze this region)
  RoiRect _roi = RoiRect.full;

  // Corner points for perspective crop (null = rectangular crop from ROI)
  List<CornerPoint>? _perspectiveCorners;

  // Stream controllers
  final _capturedFramesController = StreamController<String>.broadcast();
  final _analysisResultController =
      StreamController<FrameAnalysisResult>.broadcast();
  final _stabilityController = StreamController<StabilityEvent>.broadcast();
  final _thumbnailController = StreamController<String>.broadcast();

  // Gyroscope stability tracking
  StreamSubscription<AccelerometerEvent>? _accelSub;
  DateTime? _steadyStartTime;
  bool _currentlyStable = false;
  Duration steadyRequiredDuration = const Duration(seconds: 3);
  double steadyThreshold = 0.8; // m/s²

  /// Emits file path when a slide is auto-captured.
  Stream<String> get capturedFrames => _capturedFramesController.stream;

  /// Emits live delta values for viewfinder overlay.
  Stream<FrameAnalysisResult> get analysisResults =>
      _analysisResultController.stream;

  /// Emits stability events (phone steady / not steady).
  Stream<StabilityEvent> get stabilityEvents => _stabilityController.stream;

  /// Emits thumbnail path for each captured slide (for badge animation).
  Stream<String> get thumbnailStream => _thumbnailController.stream;

  bool get isStreaming => _isStreaming;
  CameraController? get controller => _controller;
  bool get flashEnabled => _flashEnabled;

  // ── Initialization ──────────────────────────────────────────────────────

  Future<void> initialize(List<CameraDescription> cameras) async {
    if (cameras.isEmpty) return;

    // Dispose old controller if exists
    await _controller?.dispose();
    _controller = null;

    _controller = CameraController(
      cameras.first,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    await _controller!.initialize();
  }

  // ── ROI & Corner Config ──────────────────────────────────────────────────

  void setRoi(RoiRect roi) {
    _roi = roi;
    _referenceYPlane = null; // reset reference on ROI change
  }

  void setPerspectiveCorners(List<CornerPoint>? corners) {
    _perspectiveCorners = corners;
  }

  // ── Streaming ────────────────────────────────────────────────────────────

  void startStream({double? threshold, Duration? stabilityWindow}) {
    if (_controller == null || _isStreaming) return;
    if (threshold != null) this.threshold = threshold;
    if (stabilityWindow != null) this.stabilityWindow = stabilityWindow;

    _isStreaming = true;
    _referenceYPlane = null;
    _changeDetectedAt = null;

    _controller!.startImageStream(_onFrameArrived);
  }

  void stopStream() {
    if (!_isStreaming) return;
    _isStreaming = false;
    try {
      _controller?.stopImageStream();
    } catch (_) {}
  }

  // ── Flash ────────────────────────────────────────────────────────────────

  Future<void> toggleFlash() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    _flashEnabled = !_flashEnabled;
    await _controller!.setFlashMode(
      _flashEnabled ? FlashMode.torch : FlashMode.off,
    );
  }

  // ── Stability Detection ──────────────────────────────────────────────────

  /// Start listening to accelerometer to detect phone steadiness.
  void startStabilityWatch() {
    _steadyStartTime = null;
    _currentlyStable = false;
    _accelSub?.cancel();
    _accelSub = accelerometerEventStream(
      samplingPeriod: const Duration(milliseconds: 100),
    ).listen(_onAccelEvent);
  }

  void stopStabilityWatch() {
    _accelSub?.cancel();
    _accelSub = null;
    _steadyStartTime = null;
    _currentlyStable = false;
  }

  void _onAccelEvent(AccelerometerEvent event) {
    // Gravity-adjusted magnitude — subtract gravity component (9.8 on one axis)
    // Simple approach: magnitude of acceleration vector
    final magnitude = math.sqrt(
      event.x * event.x + event.y * event.y + event.z * event.z,
    );
    // Net motion = deviation from gravity (9.8 m/s²)
    final motion = (magnitude - 9.8).abs();

    final now = DateTime.now();

    if (motion < steadyThreshold) {
      // Phone is steady
      _steadyStartTime ??= now;
      final elapsed = now.difference(_steadyStartTime!);

      if (!_currentlyStable && elapsed >= steadyRequiredDuration) {
        _currentlyStable = true;
        _stabilityController.add(const StabilityEvent(true));
      }
    } else {
      // Phone is moving
      if (_currentlyStable) {
        _currentlyStable = false;
        _stabilityController.add(const StabilityEvent(false));
      }
      _steadyStartTime = null;
    }
  }

  // ── Frame Analysis ───────────────────────────────────────────────────────

  void _onFrameArrived(CameraImage image) {
    if (_isProcessing) return;
    _isProcessing = true;
    _analyzeFrame(image).whenComplete(() => _isProcessing = false);
  }

  Future<void> _analyzeFrame(CameraImage image) async {
    final Uint8List currentY = image.planes[0].bytes;
    final int width = image.width;
    final int height = image.height;

    if (_referenceYPlane == null) {
      _referenceYPlane = Uint8List.fromList(currentY);
      return;
    }

    final result = await compute<_FrameDiffPayload, FrameAnalysisResult>(
      _computeFrameDiff,
      _FrameDiffPayload(
        currentY: currentY,
        referenceY: _referenceYPlane!,
        frameWidth: width,
        frameHeight: height,
        threshold: threshold,
        roiLeft: _roi.left,
        roiTop: _roi.top,
        roiRight: _roi.right,
        roiBottom: _roi.bottom,
      ),
    );

    if (!_analysisResultController.isClosed) {
      _analysisResultController.add(result);
    }

    if (result.slideChanged) {
      final now = DateTime.now();
      _changeDetectedAt ??= now;

      if (now.difference(_changeDetectedAt!) >= stabilityWindow) {
        await _captureHighResFrame();
        _referenceYPlane = Uint8List.fromList(currentY);
        _changeDetectedAt = null;
      }
    } else {
      _changeDetectedAt = null;
    }
  }

  // ── High-res Capture ─────────────────────────────────────────────────────

  Future<void> _captureHighResFrame() async {
    if (_controller == null || !_controller!.value.isInitialized) return;

    try {
      final wasStreaming = _isStreaming;
      if (wasStreaming) stopStream();

      final xFile = await _controller!.takePicture();
      HapticFeedback.mediumImpact();

      final sessionDir = await _getSessionDir();
      final dest = p.join(
        sessionDir.path,
        'slide_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );

      // Apply perspective crop if corners are set, else rectangular ROI crop
      final String finalPath;
      if (_perspectiveCorners != null && _perspectiveCorners!.length == 4) {
        finalPath = await DocumentScannerService.instance.perspectiveCrop(
          xFile.path,
          corners: _perspectiveCorners!,
        );
      } else if (_roi != RoiRect.full) {
        finalPath = await DocumentScannerService.instance.cropToRoi(
          xFile.path,
          left: _roi.left,
          top: _roi.top,
          right: _roi.right,
          bottom: _roi.bottom,
        );
      } else {
        finalPath = xFile.path;
      }

      // Copy to session directory
      await File(finalPath).copy(dest);

      if (!_capturedFramesController.isClosed) {
        _capturedFramesController.add(dest);
      }
      if (!_thumbnailController.isClosed) {
        _thumbnailController.add(dest);
      }

      if (wasStreaming && _isStreaming == false) {
        // Restart stream after capture
        _isStreaming = true;
        _controller?.startImageStream(_onFrameArrived);
      }
    } catch (e) {
      debugPrint('CameraEngine: capture error: $e');
    }
  }

  /// Manual capture (from shutter button tap).
  Future<void> manualCapture() async {
    await _captureHighResFrame();
  }

  Future<Directory> _getSessionDir() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final sessionDir = Directory(
      p.join(docsDir.path, 'SmartLectureScanner', 'session'),
    );
    if (!await sessionDir.exists()) {
      await sessionDir.create(recursive: true);
    }
    return sessionDir;
  }

  // ── Cleanup ──────────────────────────────────────────────────────────────

  Future<void> dispose() async {
    stopStream();
    stopStabilityWatch();
    await _controller?.dispose();
    _controller = null;

    if (!_capturedFramesController.isClosed) {
      await _capturedFramesController.close();
    }
    if (!_analysisResultController.isClosed) {
      await _analysisResultController.close();
    }
    if (!_stabilityController.isClosed) {
      await _stabilityController.close();
    }
    if (!_thumbnailController.isClosed) {
      await _thumbnailController.close();
    }
  }

  /// Reset engine state for a new session (without disposing camera).
  void resetSession() {
    stopStream();
    stopStabilityWatch();
    _referenceYPlane = null;
    _changeDetectedAt = null;
    _roi = RoiRect.full;
    _perspectiveCorners = null;
  }
}

// Top-level helper to get cameras without importing camera package in screens.
Future<List<CameraDescription>> getAvailableCamerasHelper() =>
    availableCameras();
