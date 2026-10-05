import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:test123/core/providers/app_providers.dart';
import 'package:test123/core/services/camera_engine_service.dart';
import 'package:test123/features/capture/screens/live_capture_screen.dart';

/// Step 2: Area selection.
/// - AUTO mode: user taps 4 corners of the projector/screen area.
/// - MANUAL mode: user drags a resizable crop rectangle.
class CornerTapScreen extends ConsumerStatefulWidget {
  final ScanMode mode;
  const CornerTapScreen({super.key, required this.mode});

  @override
  ConsumerState<CornerTapScreen> createState() => _CornerTapScreenState();
}

class _CornerTapScreenState extends ConsumerState<CornerTapScreen>
    with SingleTickerProviderStateMixin {
  final _engine = CameraEngineService.instance;
  final List<Offset> _corners = []; // normalized 0–1

  // Manual mode: drag-box
  Rect _dragBox = const Rect.fromLTWH(0.1, 0.15, 0.8, 0.6);
  bool _isDragging = false;
  Offset? _dragStart;
  Rect? _dragBoxStart;
  _DragHandle? _activeHandle;

  Size _previewSize = Size.zero;

  late final AnimationController _confirmCtrl;
  bool _confirmed = false;

  @override
  void initState() {
    super.initState();
    _confirmCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
  }

  @override
  void dispose() {
    _confirmCtrl.dispose();
    super.dispose();
  }

  // ── AUTO mode: corner tapping ─────────────────────────────────────────────

  void _onTapDown(TapDownDetails details) {
    if (widget.mode != ScanMode.auto) return;
    if (_corners.length >= 4) return;
    if (_previewSize == Size.zero) return;

    final norm = Offset(
      (details.localPosition.dx / _previewSize.width).clamp(0.0, 1.0),
      (details.localPosition.dy / _previewSize.height).clamp(0.0, 1.0),
    );
    setState(() => _corners.add(norm));

    if (_corners.length == 4) {
      _confirmCtrl.forward();
    }
  }

  void _removeLast() {
    if (_corners.isEmpty) return;
    setState(() => _corners.removeLast());
    _confirmCtrl.reset();
    _confirmed = false;
  }

  // ── MANUAL mode: drag box ─────────────────────────────────────────────────

  _DragHandle? _hitTestHandle(Offset local) {
    if (_previewSize == Size.zero) return null;
    final box = _normalizedToScreen(_dragBox);
    const hitR = 24.0;

    if ((local - box.topLeft).distance < hitR) return _DragHandle.topLeft;
    if ((local - box.topRight).distance < hitR) return _DragHandle.topRight;
    if ((local - box.bottomLeft).distance < hitR) return _DragHandle.bottomLeft;
    if ((local - box.bottomRight).distance < hitR) return _DragHandle.bottomRight;
    if (box.contains(local)) return _DragHandle.center;
    return null;
  }

  Rect _normalizedToScreen(Rect norm) {
    return Rect.fromLTRB(
      norm.left * _previewSize.width,
      norm.top * _previewSize.height,
      norm.right * _previewSize.width,
      norm.bottom * _previewSize.height,
    );
  }

  Rect _screenToNormalized(Rect screen) {
    return Rect.fromLTRB(
      (screen.left / _previewSize.width).clamp(0.0, 0.99),
      (screen.top / _previewSize.height).clamp(0.0, 0.99),
      (screen.right / _previewSize.width).clamp(0.01, 1.0),
      (screen.bottom / _previewSize.height).clamp(0.01, 1.0),
    );
  }

  void _onPanStart(DragStartDetails d) {
    if (widget.mode != ScanMode.manual) return;
    final handle = _hitTestHandle(d.localPosition);
    setState(() {
      _isDragging = true;
      _activeHandle = handle;
      _dragStart = d.localPosition;
      _dragBoxStart = _dragBox;
    });
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (!_isDragging || _dragStart == null) return;
    final delta = d.localPosition - _dragStart!;
    final dx = delta.dx / _previewSize.width;
    final dy = delta.dy / _previewSize.height;
    final base = _dragBoxStart!;

    Rect newBox;
    switch (_activeHandle) {
      case _DragHandle.center:
        newBox = base.translate(dx, dy);
        newBox = Rect.fromLTWH(
          newBox.left.clamp(0.0, 1.0 - newBox.width),
          newBox.top.clamp(0.0, 1.0 - newBox.height),
          newBox.width,
          newBox.height,
        );
      case _DragHandle.topLeft:
        newBox = Rect.fromLTRB(
          (base.left + dx).clamp(0.0, base.right - 0.05),
          (base.top + dy).clamp(0.0, base.bottom - 0.05),
          base.right,
          base.bottom,
        );
      case _DragHandle.topRight:
        newBox = Rect.fromLTRB(
          base.left,
          (base.top + dy).clamp(0.0, base.bottom - 0.05),
          (base.right + dx).clamp(base.left + 0.05, 1.0),
          base.bottom,
        );
      case _DragHandle.bottomLeft:
        newBox = Rect.fromLTRB(
          (base.left + dx).clamp(0.0, base.right - 0.05),
          base.top,
          base.right,
          (base.bottom + dy).clamp(base.top + 0.05, 1.0),
        );
      case _DragHandle.bottomRight:
        newBox = Rect.fromLTRB(
          base.left,
          base.top,
          (base.right + dx).clamp(base.left + 0.05, 1.0),
          (base.bottom + dy).clamp(base.top + 0.05, 1.0),
        );
      case null:
        return;
    }
    setState(() => _dragBox = newBox);
  }

  void _onPanEnd(DragEndDetails d) {
    setState(() {
      _isDragging = false;
      _activeHandle = null;
    });
  }

  // ── Confirm & Navigate ────────────────────────────────────────────────────

  void _confirmSelection() {
    if (_confirmed) return;
    setState(() => _confirmed = true);

    final session = ref.read(scanSessionProvider.notifier);

    if (widget.mode == ScanMode.auto) {
      // Sort corners: TL, TR, BR, BL
      final sorted = _sortCorners(_corners);
      final cornerPoints = sorted
          .map((o) => CornerPoint(o.dx, o.dy))
          .toList();
      session.setCorners(cornerPoints);
      _engine.setPerspectiveCorners(cornerPoints);

      // Derive ROI from bounding box of corners
      final minX = sorted.map((o) => o.dx).reduce((a, b) => a < b ? a : b);
      final minY = sorted.map((o) => o.dy).reduce((a, b) => a < b ? a : b);
      final maxX = sorted.map((o) => o.dx).reduce((a, b) => a > b ? a : b);
      final maxY = sorted.map((o) => o.dy).reduce((a, b) => a > b ? a : b);
      final roi = RoiRect(left: minX, top: minY, right: maxX, bottom: maxY);
      session.setRoi(roi);
      _engine.setRoi(roi);
    } else {
      // Manual: use drag box as ROI
      final roi = RoiRect(
        left: _dragBox.left,
        top: _dragBox.top,
        right: _dragBox.right,
        bottom: _dragBox.bottom,
      );
      session.setRoi(roi);
      _engine.setRoi(roi);
      _engine.setPerspectiveCorners(null);
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LiveCaptureScreen()),
    );
  }

  List<Offset> _sortCorners(List<Offset> pts) {
    // Sort by: top-left, top-right, bottom-right, bottom-left
    final center = pts.fold(Offset.zero, (acc, p) => acc + p) / pts.length.toDouble();
    final sorted = List<Offset>.from(pts)
      ..sort((a, b) {
        final angleA = (a - center).direction;
        final angleB = (b - center).direction;
        return angleA.compareTo(angleB);
      });
    // Rotate so topmost-leftmost is first
    int topLeftIdx = 0;
    double minDist = double.maxFinite;
    for (int i = 0; i < sorted.length; i++) {
      final d = sorted[i].dx + sorted[i].dy;
      if (d < minDist) {
        minDist = d;
        topLeftIdx = i;
      }
    }
    final result = <Offset>[];
    for (int i = 0; i < sorted.length; i++) {
      result.add(sorted[(topLeftIdx + i) % sorted.length]);
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final isAuto = widget.mode == ScanMode.auto;
    final canConfirm = isAuto ? _corners.length == 4 : true;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Camera preview
          if (_engine.controller != null &&
              _engine.controller!.value.isInitialized)
            LayoutBuilder(builder: (ctx, constraints) {
              _previewSize = Size(constraints.maxWidth, constraints.maxHeight);
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: isAuto ? _onTapDown : null,
                onPanStart: !isAuto ? _onPanStart : null,
                onPanUpdate: !isAuto ? _onPanUpdate : null,
                onPanEnd: !isAuto ? _onPanEnd : null,
                child: Stack(
                  children: [
                    CameraPreview(_engine.controller!),
                    // Overlay
                    CustomPaint(
                      size: Size(constraints.maxWidth, constraints.maxHeight),
                      painter: isAuto
                          ? _CornerTapPainter(corners: _corners)
                          : _DragBoxPainter(
                              box: _dragBox,
                              isDragging: _isDragging,
                            ),
                    ),
                  ],
                ),
              );
            })
          else
            const Center(
              child: CircularProgressIndicator(color: Colors.white38),
            ),

          // Top bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
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
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back_ios_new_rounded,
                          color: Colors.white70),
                    ),
                    const Spacer(),
                    // Mode badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: isAuto
                            ? const Color(0xFF3949AB).withValues(alpha: 0.8)
                            : const Color(0xFF388E3C).withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isAuto
                                ? Icons.sensors_rounded
                                : Icons.touch_app_rounded,
                            color: Colors.white,
                            size: 14,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            isAuto ? 'Auto' : 'Manual',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Bottom instruction + confirm
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
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
                    // Instruction
                    _InstructionBanner(
                      isAuto: isAuto,
                      cornersCount: _corners.length,
                    ),
                    const SizedBox(height: 16),

                    // Auto: undo button + counter
                    if (isAuto && _corners.isNotEmpty)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '${_corners.length}/4 corners tapped',
                            style: const TextStyle(
                              color: Colors.white60,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(width: 16),
                          GestureDetector(
                            onTap: _removeLast,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.white10,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.undo_rounded,
                                      color: Colors.white54, size: 16),
                                  SizedBox(width: 4),
                                  Text('Undo',
                                      style: TextStyle(
                                          color: Colors.white54, fontSize: 12)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),

                    const SizedBox(height: 16),

                    // Confirm button
                    AnimatedOpacity(
                      opacity: canConfirm ? 1.0 : 0.35,
                      duration: const Duration(milliseconds: 300),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: canConfirm ? _confirmSelection : null,
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF3949AB),
                            padding:
                                const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          icon: const Icon(Icons.check_circle_outline_rounded,
                              color: Colors.white),
                          label: Text(
                            isAuto
                                ? (_corners.length == 4
                                    ? 'Confirm Area & Start Scanning'
                                    : 'Tap all 4 corners first')
                                : 'Confirm Area & Start Scanning',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),
                    _StepIndicator(step: 2, total: 3, label: 'Define Screen Area'),
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

// ── Drag handle enum ──────────────────────────────────────────────────────────

enum _DragHandle { topLeft, topRight, bottomLeft, bottomRight, center }

// ── Corner Tap Painter ────────────────────────────────────────────────────────

class _CornerTapPainter extends CustomPainter {
  final List<Offset> corners; // normalized
  const _CornerTapPainter({required this.corners});

  @override
  void paint(Canvas canvas, Size size) {
    final pts =
        corners.map((n) => Offset(n.dx * size.width, n.dy * size.height)).toList();

    // Draw corner dots
    final dotPaint = Paint()
      ..color = const Color(0xFF00BCD4)
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    for (final pt in pts) {
      canvas.drawCircle(pt, 12, dotPaint);
      canvas.drawCircle(pt, 12, borderPaint);
    }

    // Connecting lines
    if (pts.length >= 2) {
      final linePaint = Paint()
        ..color = const Color(0xFF00BCD4).withValues(alpha: 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round;

      final path = Path()..moveTo(pts[0].dx, pts[0].dy);
      for (int i = 1; i < pts.length; i++) {
        path.lineTo(pts[i].dx, pts[i].dy);
      }
      if (pts.length == 4) {
        path.close();
        // Fill polygon with translucent overlay
        canvas.drawPath(
          path,
          Paint()
            ..color = const Color(0xFF00BCD4).withValues(alpha: 0.12)
            ..style = PaintingStyle.fill,
        );
      }
      canvas.drawPath(path, linePaint);
    }

    // Labels
    final labels = ['TL', 'TR', 'BR', 'BL'];
    for (int i = 0; i < pts.length; i++) {
      final textPainter = TextPainter(
        text: TextSpan(
          text: labels[i],
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(
        canvas,
        pts[i] + const Offset(14, -6),
      );
    }
  }

  @override
  bool shouldRepaint(_CornerTapPainter old) => old.corners != corners;
}

// ── Drag Box Painter ──────────────────────────────────────────────────────────

class _DragBoxPainter extends CustomPainter {
  final Rect box; // normalized
  final bool isDragging;
  const _DragBoxPainter({required this.box, required this.isDragging});

  @override
  void paint(Canvas canvas, Size size) {
    final screenBox = Rect.fromLTRB(
      box.left * size.width,
      box.top * size.height,
      box.right * size.width,
      box.bottom * size.height,
    );

    // Dim outside
    final dimPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRect(screenBox)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(
      dimPath,
      Paint()..color = Colors.black.withValues(alpha: 0.55),
    );

    // Border
    canvas.drawRect(
      screenBox,
      Paint()
        ..color = isDragging
            ? const Color(0xFF69F0AE)
            : const Color(0xFF00BCD4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );

    // Corner handles
    const handleSize = 20.0;
    final handlePaint = Paint()
      ..color = isDragging
          ? const Color(0xFF69F0AE)
          : const Color(0xFF00BCD4)
      ..style = PaintingStyle.fill;

    for (final corner in [
      screenBox.topLeft,
      screenBox.topRight,
      screenBox.bottomLeft,
      screenBox.bottomRight,
    ]) {
      canvas.drawCircle(corner, handleSize / 2, handlePaint);
      canvas.drawCircle(
        corner,
        handleSize / 2,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }

    // Grid lines inside
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.15)
      ..strokeWidth = 0.8;

    final thirdW = screenBox.width / 3;
    final thirdH = screenBox.height / 3;

    for (int i = 1; i <= 2; i++) {
      canvas.drawLine(
        Offset(screenBox.left + thirdW * i, screenBox.top),
        Offset(screenBox.left + thirdW * i, screenBox.bottom),
        gridPaint,
      );
      canvas.drawLine(
        Offset(screenBox.left, screenBox.top + thirdH * i),
        Offset(screenBox.right, screenBox.top + thirdH * i),
        gridPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_DragBoxPainter old) =>
      old.box != box || old.isDragging != isDragging;
}

// ── Instruction Banner ────────────────────────────────────────────────────────

class _InstructionBanner extends StatelessWidget {
  final bool isAuto;
  final int cornersCount;
  const _InstructionBanner(
      {required this.isAuto, required this.cornersCount});

  @override
  Widget build(BuildContext context) {
    String text;
    IconData icon;

    if (isAuto) {
      if (cornersCount == 0) {
        text = 'Tap the 4 corners of the projector/screen area';
        icon = Icons.touch_app_rounded;
      } else if (cornersCount < 4) {
        text = 'Tap ${4 - cornersCount} more corner${cornersCount == 3 ? '' : 's'}';
        icon = Icons.adjust_rounded;
      } else {
        text = 'All 4 corners selected! Ready to scan.';
        icon = Icons.check_circle_outline_rounded;
      }
    } else {
      text = 'Drag the handles to define the capture area';
      icon = Icons.open_with_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: const Color(0xFF00BCD4), size: 18),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              text,
              style: const TextStyle(color: Colors.white, fontSize: 13.5),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Step Indicator (reused) ───────────────────────────────────────────────────

class _StepIndicator extends StatelessWidget {
  final int step;
  final int total;
  final String label;
  const _StepIndicator(
      {required this.step, required this.total, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Step $step of $total — $label',
            style: const TextStyle(color: Colors.white38, fontSize: 11)),
        const SizedBox(height: 8),
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
