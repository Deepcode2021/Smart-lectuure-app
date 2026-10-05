import 'dart:io';

import 'package:flutter/material.dart';
import 'package:test123/core/services/document_scanner_service.dart';
import 'package:test123/core/services/pdf_generator_service.dart';

/// Bottom sheet for editing a single slide: rotate, enhance, crop, no-op.
class SlideEditSheet extends StatefulWidget {
  final String imagePath;
  const SlideEditSheet({super.key, required this.imagePath});

  @override
  State<SlideEditSheet> createState() => _SlideEditSheetState();
}

class _SlideEditSheetState extends State<SlideEditSheet> {
  late String _currentPath;
  bool _processing = false;

  // Crop state
  double _cropLeft = 0.0;
  double _cropTop = 0.0;
  double _cropRight = 1.0;
  double _cropBottom = 1.0;
  bool _showCropOverlay = false;

  @override
  void initState() {
    super.initState();
    _currentPath = widget.imagePath;
  }

  Future<void> _applyEnhancement(ImageEnhancement enhancement) async {
    setState(() => _processing = true);
    final result = await PdfGeneratorService.applyEnhancement(
      _currentPath,
      enhancement,
    );
    if (mounted) {
      setState(() {
        _currentPath = result;
        _processing = false;
      });
    }
  }

  Future<void> _rotate(int degrees) async {
    setState(() => _processing = true);
    final result = await PdfGeneratorService.rotateImage(_currentPath, degrees);
    if (mounted) {
      setState(() {
        _currentPath = result;
        _processing = false;
      });
    }
  }

  Future<void> _autoCrop() async {
    setState(() => _processing = true);
    // Apply a 10% margin center crop (perspective correction is handled during capture)
    final result = await DocumentScannerService.instance.manualCrop(
      _currentPath,
      left: 0.08,
      top: 0.08,
      right: 0.92,
      bottom: 0.92,
    );
    if (mounted) {
      setState(() {
        _currentPath = result;
        _processing = false;
      });
    }
  }

  Future<void> _applyManualCrop() async {
    setState(() => _processing = true);
    final result = await DocumentScannerService.instance.manualCrop(
      _currentPath,
      left: _cropLeft,
      top: _cropTop,
      right: _cropRight,
      bottom: _cropBottom,
    );
    if (mounted) {
      setState(() {
        _currentPath = result;
        _processing = false;
        _showCropOverlay = false;
      });
    }
  }

  void _resetCrop() {
    setState(() {
      _cropLeft = 0.0;
      _cropTop = 0.0;
      _cropRight = 1.0;
      _cropBottom = 1.0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF161B22),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),

          // Title
          const Text(
            'Edit Slide',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),

          // Preview with optional crop overlay
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: _processing
                ? Container(
                    height: 200,
                    color: Colors.white10,
                    child: const Center(
                      child: CircularProgressIndicator(),
                    ),
                  )
                : Stack(
                    children: [
                      Image.file(
                        File(_currentPath),
                        height: 200,
                        fit: BoxFit.contain,
                        errorBuilder: (ctx, err, st) => Container(
                          height: 200, color: Colors.white10,
                          child: const Icon(Icons.broken_image, color: Colors.white24),
                        ),
                      ),
                      if (_showCropOverlay)
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _CropOverlayPainter(
                              left: _cropLeft,
                              top: _cropTop,
                              right: _cropRight,
                              bottom: _cropBottom,
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: 20),

          // Crop controls
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Crop',
              style: TextStyle(color: Colors.white60, fontSize: 12),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _ActionChip(
                label: '✂ Auto Crop',
                onTap: _autoCrop,
              ),
              const SizedBox(width: 8),
              _ActionChip(
                label: _showCropOverlay ? '✓ Done Crop' : '⊞ Manual Crop',
                onTap: () {
                  if (_showCropOverlay) {
                    _applyManualCrop();
                  } else {
                    setState(() => _showCropOverlay = true);
                  }
                },
              ),
              if (_showCropOverlay) ...[
                const SizedBox(width: 8),
                _ActionChip(
                  label: '↺ Reset',
                  onTap: _resetCrop,
                ),
              ],
            ],
          ),

          // Crop sliders (visible when manual crop is active)
          if (_showCropOverlay) ...[
            const SizedBox(height: 12),
            _CropSlider(
              label: 'Left',
              value: _cropLeft,
              onChanged: (v) => setState(() => _cropLeft = v),
            ),
            _CropSlider(
              label: 'Top',
              value: _cropTop,
              onChanged: (v) => setState(() => _cropTop = v),
            ),
            _CropSlider(
              label: 'Right',
              value: _cropRight,
              onChanged: (v) => setState(() => _cropRight = v),
            ),
            _CropSlider(
              label: 'Bottom',
              value: _cropBottom,
              onChanged: (v) => setState(() => _cropBottom = v),
            ),
          ],

          const SizedBox(height: 16),

          // Rotate row
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Rotate',
              style: TextStyle(color: Colors.white60, fontSize: 12),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _ActionChip(
                label: '↻ 90°',
                onTap: () => _rotate(90),
              ),
              const SizedBox(width: 8),
              _ActionChip(
                label: '↻ 180°',
                onTap: () => _rotate(180),
              ),
              const SizedBox(width: 8),
              _ActionChip(
                label: '↺ 90°',
                onTap: () => _rotate(270),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Enhance row
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Enhance',
              style: TextStyle(color: Colors.white60, fontSize: 12),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _ActionChip(
                label: '⬛ Grayscale',
                onTap: () => _applyEnhancement(ImageEnhancement.grayscale),
              ),
              const SizedBox(width: 8),
              _ActionChip(
                label: '🔆 High Contrast',
                onTap: () => _applyEnhancement(ImageEnhancement.highContrast),
              ),
              const SizedBox(width: 8),
              _ActionChip(
                label: '🎨 Magic Color',
                onTap: () => _applyEnhancement(ImageEnhancement.magicColor),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Confirm button
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _processing
                  ? null
                  : () => Navigator.pop(context, _currentPath),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF3949AB),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Apply Changes',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Crop Slider ────────────────────────────────────────────────────────────────

class _CropSlider extends StatelessWidget {
  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  const _CropSlider({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 50,
          child: Text(
            label,
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          ),
        ),
        Expanded(
          child: Slider(
            value: value,
            onChanged: onChanged,
            activeColor: const Color(0xFF00BCD4),
            inactiveColor: Colors.white12,
          ),
        ),
        SizedBox(
          width: 36,
          child: Text(
            '${(value * 100).toInt()}%',
            style: const TextStyle(color: Colors.white54, fontSize: 11),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}

// ── Crop Overlay Painter ───────────────────────────────────────────────────────

class _CropOverlayPainter extends CustomPainter {
  final double left;
  final double top;
  final double right;
  final double bottom;

  const _CropOverlayPainter({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cropRect = Rect.fromLTRB(
      left * size.width,
      top * size.height,
      right * size.width,
      bottom * size.height,
    );

    // Draw dimmed overlay outside crop area
    final dimPaint = Paint()..color = Colors.black.withValues(alpha: 0.5);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), dimPaint);
    canvas.save();
    canvas.clipRect(cropRect);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = Colors.transparent,
    );
    canvas.restore();

    // Draw crop border
    final borderPaint = Paint()
      ..color = const Color(0xFF00BCD4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRect(cropRect, borderPaint);

    // Draw corner handles
    final handlePaint = Paint()
      ..color = const Color(0xFF00BCD4)
      ..style = PaintingStyle.fill;
    const handleSize = 8.0;
    for (final corner in [
      cropRect.topLeft,
      cropRect.topRight,
      cropRect.bottomLeft,
      cropRect.bottomRight,
    ]) {
      canvas.drawCircle(corner, handleSize, handlePaint);
    }
  }

  @override
  bool shouldRepaint(_CropOverlayPainter old) =>
      old.left != left || old.top != top ||
      old.right != right || old.bottom != bottom;
}

// ── Action Chip ────────────────────────────────────────────────────────────────

class _ActionChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _ActionChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF21262D),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white12),
        ),
        child: Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ),
    );
  }
}
