import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:test123/core/providers/app_providers.dart';
import 'package:test123/core/services/camera_engine_service.dart';
import 'package:test123/features/capture/screens/scan_review_screen.dart';

class LiveCaptureScreen extends ConsumerStatefulWidget {
  const LiveCaptureScreen({super.key});

  @override
  ConsumerState<LiveCaptureScreen> createState() => _LiveCaptureScreenState();
}

class _LiveCaptureScreenState extends ConsumerState<LiveCaptureScreen>
    with TickerProviderStateMixin {
  final _engine = CameraEngineService.instance;

  bool _scanningStarted = false;
  double _currentDelta = 0.0;
  String _statusText = 'Ready — tap Start Scanning';

  StreamSubscription<String>? _frameSub;
  StreamSubscription<FrameAnalysisResult>? _analysisSub;
  StreamSubscription<String>? _thumbSub;

  // Thumbnail badge animation
  String? _lastThumbPath;
  bool _showThumb = false;
  late final AnimationController _thumbCtrl;
  late final Animation<Offset> _thumbSlide;
  late final Animation<double> _thumbFade;

  // Flash capture overlay
  late final AnimationController _flashCtrl;
  late final Animation<double> _flashAnim;
  bool _showFlash = false;

  // Pulse ring animation for auto scanning
  late final AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();

    // Thumbnail slide-in animation
    _thumbCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _thumbSlide = Tween<Offset>(
      begin: const Offset(1.5, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _thumbCtrl, curve: Curves.easeOutBack));
    _thumbFade = CurvedAnimation(parent: _thumbCtrl, curve: Curves.easeIn);

    // Flash capture overlay
    _flashCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _flashAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _flashCtrl, curve: Curves.easeOut),
    );

    // Pulse ring
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _listenToStreams();
  }

  void _listenToStreams() {
    _frameSub = _engine.capturedFrames.listen((path) {
      ref.read(capturedSlidesProvider.notifier).addSlide(path);
    });

    _analysisSub = _engine.analysisResults.listen((result) {
      if (mounted) {
        setState(() => _currentDelta = result.delta);
      }
    });

    _thumbSub = _engine.thumbnailStream.listen((path) {
      _triggerThumbnailBadge(path);
    });
  }

  Future<void> _triggerThumbnailBadge(String path) async {
    if (!mounted) return;
    setState(() {
      _lastThumbPath = path;
      _showThumb = true;
      _showFlash = true;
    });

    _flashCtrl.forward(from: 0);
    _thumbCtrl.forward(from: 0);

    await Future.delayed(const Duration(seconds: 2));
    if (mounted) {
      await _thumbCtrl.reverse();
      if (mounted) setState(() => _showThumb = false);
    }
  }

  void _startScanning() {
    final session = ref.read(scanSessionProvider);
    final isAuto = session.mode == ScanMode.auto;

    _engine.startStream(
      threshold: 0.18,
      stabilityWindow: const Duration(milliseconds: 1200),
    );
    ref.read(autoScanEnabledProvider.notifier).state = isAuto;
    ref.read(scanSessionProvider.notifier).setScanning(true);

    setState(() {
      _scanningStarted = true;
      _statusText = isAuto
          ? 'Auto-scanning… watching for slide changes'
          : 'Tap the shutter button to capture each slide';
    });
  }

  void _stopScanning() {
    _engine.stopStream();
    ref.read(autoScanEnabledProvider.notifier).state = false;
    ref.read(scanSessionProvider.notifier).setScanning(false);

    final slides = ref.read(capturedSlidesProvider);
    if (slides.isEmpty) {
      setState(() {
        _scanningStarted = false;
        _statusText = 'No slides captured. Tap Start Scanning.';
      });
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ScanReviewScreen()),
    );
  }

  Future<void> _manualCapture() async {
    await _engine.manualCapture();
  }

  Future<void> _toggleFlash() async {
    await _engine.toggleFlash();
    ref.read(flashEnabledProvider.notifier).state = _engine.flashEnabled;
  }

  @override
  void dispose() {
    _frameSub?.cancel();
    _analysisSub?.cancel();
    _thumbSub?.cancel();
    _engine.stopStream();
    _thumbCtrl.dispose();
    _flashCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(scanSessionProvider);
    final flashOn = ref.watch(flashEnabledProvider);
    final slides = ref.watch(capturedSlidesProvider);
    final isAuto = session.mode == ScanMode.auto;
    final roi = session.roi;
    final corners = session.corners;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Camera Preview ───────────────────────────────────────────────
          if (_engine.controller != null &&
              _engine.controller!.value.isInitialized)
            CameraPreview(_engine.controller!)
          else
            const Center(
              child: CircularProgressIndicator(color: Colors.white38),
            ),

          // ── ROI / Corner Overlay ─────────────────────────────────────────
          if (_engine.controller != null &&
              _engine.controller!.value.isInitialized)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _RoiOverlayPainter(
                    roi: roi,
                    corners: corners,
                    delta: _currentDelta,
                    isScanning: _scanningStarted,
                    isAuto: isAuto,
                  ),
                ),
              ),
            ),

          // ── Flash Overlay on capture ─────────────────────────────────────
          if (_showFlash)
            IgnorePointer(
              child: AnimatedBuilder(
                animation: _flashAnim,
                builder: (_, __) => Container(
                  color: Colors.white
                      .withValues(alpha: (1 - _flashAnim.value) * 0.45),
                ),
              ),
            ),

          // ── Top Bar ──────────────────────────────────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.8),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Row(
                  children: [
                    // Back
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new_rounded,
                          color: Colors.white70),
                      onPressed: () {
                        _engine.stopStream();
                        Navigator.pop(context);
                      },
                    ),
                    const Spacer(),
                    // Flash
                    IconButton(
                      icon: Icon(
                        flashOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                        color: flashOn ? Colors.amber : Colors.white70,
                      ),
                      onPressed: _toggleFlash,
                    ),
                    const SizedBox(width: 8),
                    // Mode badge
                    _ModeBadge(
                      isAuto: isAuto,
                      isScanning: _scanningStarted,
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Delta bar (auto scanning only) ───────────────────────────────
          if (isAuto && _scanningStarted)
            Positioned(
              top: kToolbarHeight + 60,
              left: 16,
              right: 16,
              child: _DeltaBar(delta: _currentDelta),
            ),

          // ── Thumbnail Badge (slide-in on capture) ────────────────────────
          if (_showThumb && _lastThumbPath != null)
            Positioned(
              bottom: 160,
              right: 16,
              child: SlideTransition(
                position: _thumbSlide,
                child: FadeTransition(
                  opacity: _thumbFade,
                  child: _ThumbnailBadge(
                    path: _lastThumbPath!,
                    count: slides.length,
                  ),
                ),
              ),
            ),

          // ── Status text (top center) ──────────────────────────────────────
          if (!_scanningStarted)
            Positioned(
              top: kToolbarHeight + 80,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    _statusText,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),

          // ── Bottom Controls ───────────────────────────────────────────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.9),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Slide counter
                        _SlideCounter(count: slides.length),

                        // Center: shutter (manual) or auto indicator
                        if (!_scanningStarted)
                          // Start scanning button
                          _StartScanButton(onTap: _startScanning)
                        else if (!isAuto)
                          // Manual shutter
                          _ShutterButton(onTap: _manualCapture)
                        else
                          // Auto scanning pulse indicator
                          _AutoScanIndicator(pulseCtrl: _pulseCtrl),

                        // Right: Stop or Review
                        if (_scanningStarted)
                          _StopButton(onTap: _stopScanning)
                        else
                          _ReviewButton(
                            enabled: slides.isNotEmpty,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const ScanReviewScreen()),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _ModeBadge extends StatelessWidget {
  final bool isAuto;
  final bool isScanning;
  const _ModeBadge({required this.isAuto, required this.isScanning});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: isScanning
            ? (isAuto
                ? const Color(0xFF00BCD4).withValues(alpha: 0.25)
                : const Color(0xFF69F0AE).withValues(alpha: 0.2))
            : Colors.white10,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isScanning
              ? (isAuto ? const Color(0xFF00BCD4) : const Color(0xFF69F0AE))
              : Colors.white24,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isAuto ? Icons.sensors_rounded : Icons.touch_app_rounded,
            color: isScanning
                ? (isAuto ? const Color(0xFF00BCD4) : const Color(0xFF69F0AE))
                : Colors.white54,
            size: 16,
          ),
          const SizedBox(width: 6),
          Text(
            isAuto ? 'Auto' : 'Manual',
            style: TextStyle(
              color: isScanning
                  ? (isAuto ? const Color(0xFF00BCD4) : const Color(0xFF69F0AE))
                  : Colors.white54,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _SlideCounter extends StatelessWidget {
  final int count;
  const _SlideCounter({required this.count});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          transitionBuilder: (child, anim) => ScaleTransition(
            scale: anim,
            child: child,
          ),
          child: Text(
            '$count',
            key: ValueKey(count),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const Text(
          'Slides',
          style: TextStyle(color: Colors.white54, fontSize: 11),
        ),
      ],
    );
  }
}

class _StartScanButton extends StatelessWidget {
  final VoidCallback onTap;
  const _StartScanButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            colors: [Color(0xFF3949AB), Color(0xFF1A237E)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF3949AB).withValues(alpha: 0.5),
              blurRadius: 16,
              spreadRadius: 2,
            ),
          ],
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.play_arrow_rounded, color: Colors.white, size: 28),
            Text(
              'START',
              style: TextStyle(
                color: Colors.white,
                fontSize: 9,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShutterButton extends StatelessWidget {
  final VoidCallback onTap;
  const _ShutterButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 76,
        height: 76,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
          color: Colors.white.withValues(alpha: 0.15),
        ),
        child: const Icon(Icons.camera_rounded, color: Colors.white, size: 32),
      ),
    );
  }
}

class _AutoScanIndicator extends StatelessWidget {
  final AnimationController pulseCtrl;
  const _AutoScanIndicator({required this.pulseCtrl});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pulseCtrl,
      builder: (_, __) {
        return Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF00BCD4)
                .withValues(alpha: 0.1 + 0.1 * pulseCtrl.value),
            border: Border.all(
              color: const Color(0xFF00BCD4)
                  .withValues(alpha: 0.5 + 0.5 * pulseCtrl.value),
              width: 2,
            ),
          ),
          child: const Icon(Icons.sensors_rounded,
              color: Color(0xFF00BCD4), size: 30),
        );
      },
    );
  }
}

class _StopButton extends StatelessWidget {
  final VoidCallback onTap;
  const _StopButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.redAccent),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.stop_rounded, color: Colors.redAccent, size: 18),
            SizedBox(width: 4),
            Text(
              'Stop',
              style: TextStyle(
                color: Colors.redAccent,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewButton extends StatelessWidget {
  final bool enabled;
  final VoidCallback onTap;
  const _ReviewButton({required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1.0 : 0.35,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF3949AB).withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: enabled
                    ? const Color(0xFF3949AB)
                    : Colors.white12),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.done_all_rounded,
                  color: Color(0xFF3949AB), size: 18),
              SizedBox(width: 4),
              Text(
                'Review',
                style: TextStyle(
                  color: Color(0xFF3949AB),
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── ROI Overlay Painter ───────────────────────────────────────────────────────

class _RoiOverlayPainter extends CustomPainter {
  final RoiRect? roi;
  final List<CornerPoint>? corners;
  final double delta;
  final bool isScanning;
  final bool isAuto;

  const _RoiOverlayPainter({
    required this.roi,
    required this.corners,
    required this.delta,
    required this.isScanning,
    required this.isAuto,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (roi == null) return;

    final screenBox = Rect.fromLTRB(
      roi!.left * size.width,
      roi!.top * size.height,
      roi!.right * size.width,
      roi!.bottom * size.height,
    );

    // Dim outside ROI
    final dimPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRect(screenBox)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(
      dimPath,
      Paint()..color = Colors.black.withValues(alpha: 0.45),
    );

    // ROI border color based on delta
    final borderColor = isScanning && delta > 0.18
        ? const Color(0xFF00BCD4)
        : (isScanning ? Colors.white54 : Colors.white30);

    canvas.drawRect(
      screenBox,
      Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = isScanning && delta > 0.18 ? 3 : 2,
    );

    // Corner bracket marks
    _drawCornerBrackets(canvas, screenBox, borderColor);

    // Perspective corners (if in auto mode)
    if (corners != null && isAuto) {
      final pts = corners!
          .map((c) => Offset(c.x * size.width, c.y * size.height))
          .toList();

      final dotPaint = Paint()
        ..color = const Color(0xFF00BCD4).withValues(alpha: 0.7)
        ..style = PaintingStyle.fill;

      for (final pt in pts) {
        canvas.drawCircle(pt, 6, dotPaint);
      }
    }
  }

  void _drawCornerBrackets(Canvas canvas, Rect box, Color color) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    const len = 24.0;
    final corners = [
      [box.topLeft, Offset(box.left + len, box.top),
        box.topLeft, Offset(box.left, box.top + len)],
      [box.topRight, Offset(box.right - len, box.top),
        box.topRight, Offset(box.right, box.top + len)],
      [box.bottomLeft, Offset(box.left + len, box.bottom),
        box.bottomLeft, Offset(box.left, box.bottom - len)],
      [box.bottomRight, Offset(box.right - len, box.bottom),
        box.bottomRight, Offset(box.right, box.bottom - len)],
    ];

    for (final c in corners) {
      canvas.drawLine(c[0], c[1], paint);
      canvas.drawLine(c[2], c[3], paint);
    }
  }

  @override
  bool shouldRepaint(_RoiOverlayPainter old) =>
      old.roi != roi || old.delta != delta || old.isScanning != isScanning;
}

// ── Delta Bar ─────────────────────────────────────────────────────────────────

class _DeltaBar extends StatelessWidget {
  final double delta;
  const _DeltaBar({required this.delta});

  @override
  Widget build(BuildContext context) {
    final pct = (delta * 100).clamp(0, 100).toInt();
    final color = delta > 0.18 ? const Color(0xFF00BCD4) : Colors.white38;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Change Detection',
                  style: TextStyle(color: Colors.white54, fontSize: 11)),
              Text('$pct%',
                  style: TextStyle(color: color, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: delta.clamp(0, 1).toDouble(),
              backgroundColor: Colors.white12,
              valueColor: AlwaysStoppedAnimation<Color>(color),
              minHeight: 4,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Thumbnail Badge ───────────────────────────────────────────────────────────

class _ThumbnailBadge extends StatelessWidget {
  final String path;
  final int count;
  const _ThumbnailBadge({required this.path, required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF00BCD4), width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(
              File(path),
              width: 72,
              height: 56,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: 72,
                height: 56,
                color: Colors.white10,
                child: const Icon(Icons.image, color: Colors.white38),
              ),
            ),
          ),
          Positioned(
            top: -8,
            right: -8,
            child: Container(
              width: 22,
              height: 22,
              decoration: const BoxDecoration(
                color: Color(0xFF00BCD4),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  '$count',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
