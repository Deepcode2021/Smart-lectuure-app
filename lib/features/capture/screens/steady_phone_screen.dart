import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:test123/core/providers/app_providers.dart';
import 'package:test123/core/services/camera_engine_service.dart';
import 'package:test123/features/capture/screens/corner_tap_screen.dart';

/// Step 2a: Shows camera preview and asks user to hold the phone steady for 3s.
/// Works for both AUTO and MANUAL modes.
/// - AUTO  → advances to CornerTapScreen (4-corner selection)
/// - MANUAL → advances to CornerTapScreen too (but uses drag-box mode)
class SteadyPhoneScreen extends ConsumerStatefulWidget {
  final ScanMode mode;
  const SteadyPhoneScreen({super.key, required this.mode});

  @override
  ConsumerState<SteadyPhoneScreen> createState() => _SteadyPhoneScreenState();
}

class _SteadyPhoneScreenState extends ConsumerState<SteadyPhoneScreen>
    with TickerProviderStateMixin {
  final _engine = CameraEngineService.instance;

  bool _isStable = false;
  bool _navigated = false;
  double _steadyProgress = 0.0;
  Timer? _progressTimer;
  StreamSubscription<StabilityEvent>? _stabSub;

  late final AnimationController _ringCtrl;
  late final AnimationController _pulseCtrl;
  late final Animation<double> _ringAnim;
  late final Animation<double> _pulseAnim;

  static const Duration _steadyDuration = Duration(seconds: 3);

  @override
  void initState() {
    super.initState();

    _ringCtrl = AnimationController(
      vsync: this,
      duration: _steadyDuration,
    );
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);

    _ringAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _ringCtrl, curve: Curves.linear),
    );
    _pulseAnim = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    _startStabilityWatch();
  }

  void _startStabilityWatch() {
    _engine.steadyRequiredDuration = _steadyDuration;
    _engine.steadyThreshold = 0.8;
    _engine.startStabilityWatch();

    _stabSub = _engine.stabilityEvents.listen((event) {
      if (!mounted) return;
      if (event.isStable && !_navigated) {
        _onPhoneStable();
      } else if (!event.isStable) {
        _onPhoneMoving();
      }
    });
  }

  void _onPhoneStable() {
    setState(() {
      _isStable = true;
      _steadyProgress = 0;
    });
    _ringCtrl.forward(from: 0);

    // Animate progress
    _progressTimer?.cancel();
    const tickInterval = Duration(milliseconds: 50);
    _progressTimer = Timer.periodic(tickInterval, (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        _steadyProgress =
            math.min(1.0, _steadyProgress + (50 / _steadyDuration.inMilliseconds));
      });
      if (_steadyProgress >= 1.0) {
        t.cancel();
        _advance();
      }
    });
  }

  void _onPhoneMoving() {
    if (_navigated) return;
    _progressTimer?.cancel();
    _ringCtrl.stop();
    _ringCtrl.reset();
    setState(() {
      _isStable = false;
      _steadyProgress = 0;
    });
  }

  void _advance() {
    if (_navigated) return;
    _navigated = true;
    _engine.stopStabilityWatch();
    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => CornerTapScreen(mode: widget.mode),
      ),
    );
  }

  void _skipSteady() {
    _progressTimer?.cancel();
    _engine.stopStabilityWatch();
    _advance();
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _stabSub?.cancel();
    _ringCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Camera preview background
          if (_engine.controller != null &&
              _engine.controller!.value.isInitialized)
            CameraPreview(_engine.controller!)
          else
            const Center(
              child: CircularProgressIndicator(color: Colors.white38),
            ),

          // Dimmed overlay
          Container(color: Colors.black.withValues(alpha: 0.55)),

          // Center content
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Pulsing ring indicator
                AnimatedBuilder(
                  animation: Listenable.merge([_ringAnim, _pulseAnim]),
                  builder: (context, _) {
                    return SizedBox(
                      width: 160,
                      height: 160,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Outer pulse ring (idle)
                          if (!_isStable)
                            ScaleTransition(
                              scale: _pulseAnim,
                              child: Container(
                                width: 140,
                                height: 140,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white24,
                                    width: 2,
                                  ),
                                ),
                              ),
                            ),

                          // Progress arc (when stable)
                          if (_isStable)
                            CustomPaint(
                              size: const Size(140, 140),
                              painter: _ArcPainter(
                                progress: _steadyProgress,
                                color: const Color(0xFF00BCD4),
                              ),
                            ),

                          // Inner circle
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 400),
                            width: 100,
                            height: 100,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _isStable
                                  ? const Color(0xFF00BCD4).withValues(alpha: 0.2)
                                  : Colors.white.withValues(alpha: 0.08),
                              border: Border.all(
                                color: _isStable
                                    ? const Color(0xFF00BCD4)
                                    : Colors.white38,
                                width: 2,
                              ),
                            ),
                            child: Icon(
                              _isStable
                                  ? Icons.check_rounded
                                  : Icons.smartphone_rounded,
                              color: _isStable
                                  ? const Color(0xFF00BCD4)
                                  : Colors.white54,
                              size: 40,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),

                const SizedBox(height: 32),

                // Title
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 400),
                  child: Text(
                    _isStable ? 'Hold steady…' : 'Hold your phone still',
                    key: ValueKey(_isStable),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),

                const SizedBox(height: 12),

                // Subtitle
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Text(
                    _isStable
                        ? 'Keep it steady for 3 seconds…'
                        : 'Place your phone on a stable surface\nor hold it firmly against a wall',
                    key: ValueKey('sub$_isStable'),
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 14,
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),

                const SizedBox(height: 40),

                // Mode indicator badge
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        widget.mode == ScanMode.auto
                            ? Icons.sensors_rounded
                            : Icons.touch_app_rounded,
                        color: const Color(0xFF00BCD4),
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        widget.mode == ScanMode.auto
                            ? 'Auto Scan Mode'
                            : 'Manual Scan Mode',
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Top bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back_ios_new_rounded,
                          color: Colors.white70),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: _skipSteady,
                      child: const Text(
                        'Skip',
                        style: TextStyle(color: Colors.white54),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Bottom step indicator
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: _StepIndicator(
                  step: 1,
                  total: 3,
                  label: 'Stabilize Phone',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Arc Progress Painter ──────────────────────────────────────────────────────

class _ArcPainter extends CustomPainter {
  final double progress;
  final Color color;
  const _ArcPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;

    // Background track
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = Colors.white12
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4,
    );

    // Progress arc
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_ArcPainter old) => old.progress != progress;
}

// ── Step Indicator ────────────────────────────────────────────────────────────

class _StepIndicator extends StatelessWidget {
  final int step;
  final int total;
  final String label;

  const _StepIndicator({
    required this.step,
    required this.total,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Step $step of $total — $label',
          style: const TextStyle(color: Colors.white38, fontSize: 12),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(total, (i) {
            return AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: i + 1 == step ? 24 : 8,
              height: 4,
              decoration: BoxDecoration(
                color: i + 1 <= step
                    ? const Color(0xFF00BCD4)
                    : Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            );
          }),
        ),
      ],
    );
  }
}
