import 'dart:io';

import 'package:flutter/material.dart';
import 'package:test123/core/services/document_scanner_service.dart';
import 'package:test123/core/services/pdf_generator_service.dart';

/// Full-screen image editor for a single slide.
/// Returns the updated image path via Navigator.pop().
class ImageEditScreen extends StatefulWidget {
  final String imagePath;
  final int slideIndex;

  const ImageEditScreen({
    super.key,
    required this.imagePath,
    required this.slideIndex,
  });

  @override
  State<ImageEditScreen> createState() => _ImageEditScreenState();
}

class _ImageEditScreenState extends State<ImageEditScreen>
    with TickerProviderStateMixin {
  late String _currentPath;
  bool _processing = false;
  String _slideName = '';

  // Crop state (normalized)
  double _cropLeft = 0.0;
  double _cropTop = 0.0;
  double _cropRight = 1.0;
  double _cropBottom = 1.0;
  bool _cropMode = false;

  // Tab controller
  late final TabController _tabCtrl;

  // Active enhancement
  ImageEnhancement _activeEnhancement = ImageEnhancement.none;

  static const _tabs = ['Crop', 'Rotate', 'Enhance', 'Rename'];

  @override
  void initState() {
    super.initState();
    _currentPath = widget.imagePath;
    _slideName = 'Slide ${widget.slideIndex}';
    _tabCtrl = TabController(length: _tabs.length, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> _applyCrop() async {
    if (_cropLeft == 0 &&
        _cropTop == 0 &&
        _cropRight == 1 &&
        _cropBottom == 1) return;

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
        _cropMode = false;
        _resetCropHandles();
      });
    }
  }

  void _resetCropHandles() {
    _cropLeft = 0;
    _cropTop = 0;
    _cropRight = 1;
    _cropBottom = 1;
  }

  Future<void> _rotate(int degrees) async {
    setState(() => _processing = true);
    final result =
        await PdfGeneratorService.rotateImage(_currentPath, degrees);
    if (mounted) {
      setState(() {
        _currentPath = result;
        _processing = false;
      });
    }
  }

  Future<void> _applyEnhancement(ImageEnhancement enhancement) async {
    if (_activeEnhancement == enhancement) {
      // Toggle off → apply None (no-op, just reset visual state)
      setState(() => _activeEnhancement = ImageEnhancement.none);
      return;
    }
    setState(() {
      _processing = true;
      _activeEnhancement = enhancement;
    });
    final result = await PdfGeneratorService.applyEnhancement(
        _currentPath, enhancement);
    if (mounted) {
      setState(() {
        _currentPath = result;
        _processing = false;
      });
    }
  }

  void _confirmChanges() {
    Navigator.pop(context, _currentPath);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161B22),
        title: Text(
          _slideName,
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17),
        ),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: Colors.white70),
          onPressed: () => Navigator.pop(context, widget.imagePath),
        ),
        actions: [
          TextButton.icon(
            onPressed: _processing ? null : _confirmChanges,
            icon: const Icon(Icons.check_rounded,
                color: Color(0xFF00BCD4), size: 18),
            label: const Text(
              'Apply',
              style: TextStyle(
                  color: Color(0xFF00BCD4), fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 8),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          isScrollable: false,
          labelColor: const Color(0xFF00BCD4),
          unselectedLabelColor: Colors.white38,
          indicatorColor: const Color(0xFF00BCD4),
          indicatorSize: TabBarIndicatorSize.label,
          labelStyle:
              const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          tabs: _tabs.map((t) => Tab(text: t)).toList(),
        ),
      ),

      body: Column(
        children: [
          // ── Image Preview ──────────────────────────────────────────────────
          Expanded(
            flex: 3,
            child: Container(
              color: Colors.black,
              padding: const EdgeInsets.all(8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: _processing
                    ? const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(
                                color: Color(0xFF00BCD4)),
                            SizedBox(height: 12),
                            Text('Processing…',
                                style: TextStyle(color: Colors.white54)),
                          ],
                        ),
                      )
                    : Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.file(
                            File(_currentPath),
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => Container(
                              color: Colors.white10,
                              child: const Icon(Icons.broken_image,
                                  color: Colors.white24, size: 60),
                            ),
                          ),
                          // Crop overlay
                          if (_cropMode)
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
            ),
          ),

          // ── Tab Content ────────────────────────────────────────────────────
          Expanded(
            flex: 2,
            child: Container(
              decoration: const BoxDecoration(
                color: Color(0xFF161B22),
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: TabBarView(
                controller: _tabCtrl,
                children: [
                  _CropTab(
                    cropLeft: _cropLeft,
                    cropTop: _cropTop,
                    cropRight: _cropRight,
                    cropBottom: _cropBottom,
                    cropMode: _cropMode,
                    onToggleCropMode: () =>
                        setState(() => _cropMode = !_cropMode),
                    onCropLeftChanged: (v) =>
                        setState(() => _cropLeft = v),
                    onCropTopChanged: (v) => setState(() => _cropTop = v),
                    onCropRightChanged: (v) =>
                        setState(() => _cropRight = v),
                    onCropBottomChanged: (v) =>
                        setState(() => _cropBottom = v),
                    onApply: _applyCrop,
                    onReset: () => setState(() => _resetCropHandles()),
                    processing: _processing,
                  ),
                  _RotateTab(
                    onRotate: _rotate,
                    processing: _processing,
                  ),
                  _EnhanceTab(
                    active: _activeEnhancement,
                    onApply: _applyEnhancement,
                    processing: _processing,
                  ),
                  _RenameTab(
                    name: _slideName,
                    onNameChanged: (v) => setState(() => _slideName = v),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Crop Tab ──────────────────────────────────────────────────────────────────

class _CropTab extends StatelessWidget {
  final double cropLeft, cropTop, cropRight, cropBottom;
  final bool cropMode, processing;
  final VoidCallback onToggleCropMode, onApply, onReset;
  final ValueChanged<double> onCropLeftChanged, onCropTopChanged,
      onCropRightChanged, onCropBottomChanged;

  const _CropTab({
    required this.cropLeft,
    required this.cropTop,
    required this.cropRight,
    required this.cropBottom,
    required this.cropMode,
    required this.processing,
    required this.onToggleCropMode,
    required this.onCropLeftChanged,
    required this.onCropTopChanged,
    required this.onCropRightChanged,
    required this.onCropBottomChanged,
    required this.onApply,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _EditChip(
                label: cropMode ? '✓ Done Crop' : '✂  Crop',
                active: cropMode,
                onTap: onToggleCropMode,
              ),
              const SizedBox(width: 8),
              if (cropMode)
                _EditChip(label: '↺ Reset', onTap: onReset),
              const Spacer(),
              if (cropMode)
                FilledButton(
                  onPressed: processing ? null : onApply,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF00BCD4),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Apply Crop',
                      style: TextStyle(fontSize: 13, color: Colors.black)),
                ),
            ],
          ),
          if (cropMode) ...[
            const SizedBox(height: 16),
            _CropSlider(
                label: 'Left',
                value: cropLeft,
                onChanged: onCropLeftChanged),
            _CropSlider(
                label: 'Top',
                value: cropTop,
                onChanged: onCropTopChanged),
            _CropSlider(
                label: 'Right',
                value: cropRight,
                onChanged: onCropRightChanged),
            _CropSlider(
                label: 'Bottom',
                value: cropBottom,
                onChanged: onCropBottomChanged),
          ] else ...[
            const SizedBox(height: 16),
            const Text(
              'Tap "Crop" to enter crop mode, then adjust handles and apply.',
              style: TextStyle(color: Colors.white38, fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }
}

class _CropSlider extends StatelessWidget {
  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  const _CropSlider(
      {required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 46,
            child: Text(label,
                style: const TextStyle(color: Colors.white54, fontSize: 12)),
          ),
          Expanded(
            child: Slider(
              value: value,
              onChanged: onChanged,
              activeColor: const Color(0xFF00BCD4),
              inactiveColor: Colors.white10,
            ),
          ),
          SizedBox(
            width: 38,
            child: Text('${(value * 100).toInt()}%',
                style: const TextStyle(color: Colors.white38, fontSize: 11),
                textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }
}

// ── Rotate Tab ────────────────────────────────────────────────────────────────

class _RotateTab extends StatelessWidget {
  final void Function(int) onRotate;
  final bool processing;
  const _RotateTab({required this.onRotate, required this.processing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Rotate Image',
              style: TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _BigIconButton(
                icon: Icons.rotate_left_rounded,
                label: '90° Left',
                onTap: processing ? null : () => onRotate(270),
                color: const Color(0xFF3949AB),
              ),
              _BigIconButton(
                icon: Icons.rotate_right_rounded,
                label: '90° Right',
                onTap: processing ? null : () => onRotate(90),
                color: const Color(0xFF00BCD4),
              ),
              _BigIconButton(
                icon: Icons.screen_rotation_alt_rounded,
                label: '180°',
                onTap: processing ? null : () => onRotate(180),
                color: const Color(0xFF6A1B9A),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BigIconButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color color;
  const _BigIconButton(
      {required this.icon,
      required this.label,
      required this.onTap,
      required this.color});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null ? 0.4 : 1,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: color.withValues(alpha: 0.5)),
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(height: 8),
            Text(label,
                style:
                    const TextStyle(color: Colors.white54, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

// ── Enhance Tab ───────────────────────────────────────────────────────────────

class _EnhanceTab extends StatelessWidget {
  final ImageEnhancement active;
  final void Function(ImageEnhancement) onApply;
  final bool processing;

  const _EnhanceTab(
      {required this.active, required this.onApply, required this.processing});

  @override
  Widget build(BuildContext context) {
    final filters = [
      (ImageEnhancement.grayscale, '⬛', 'Grayscale',
          const Color(0xFF607D8B)),
      (ImageEnhancement.highContrast, '🔆', 'High Contrast',
          const Color(0xFFF57F17)),
      (ImageEnhancement.magicColor, '🎨', 'Magic Color',
          const Color(0xFF6A1B9A)),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Apply Filter',
              style: TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: filters.map((f) {
              final (enh, emoji, label, color) = f;
              final isActive = active == enh;
              return GestureDetector(
                onTap: processing ? null : () => onApply(enh),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 80,
                  padding: const EdgeInsets.symmetric(
                      vertical: 12, horizontal: 8),
                  decoration: BoxDecoration(
                    color: isActive
                        ? color.withValues(alpha: 0.2)
                        : Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isActive ? color : Colors.white12,
                      width: isActive ? 2 : 1,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(emoji, style: const TextStyle(fontSize: 24)),
                      const SizedBox(height: 6),
                      Text(
                        label,
                        style: TextStyle(
                          color: isActive ? color : Colors.white54,
                          fontSize: 11,
                          fontWeight: isActive
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          if (active != ImageEnhancement.none) ...[
            const SizedBox(height: 16),
            Center(
              child: TextButton.icon(
                onPressed:
                    processing ? null : () => onApply(ImageEnhancement.none),
                icon: const Icon(Icons.undo_rounded,
                    color: Colors.white38, size: 16),
                label: const Text('Remove Filter',
                    style: TextStyle(color: Colors.white38, fontSize: 12)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Rename Tab ────────────────────────────────────────────────────────────────

class _RenameTab extends StatefulWidget {
  final String name;
  final ValueChanged<String> onNameChanged;
  const _RenameTab({required this.name, required this.onNameChanged});

  @override
  State<_RenameTab> createState() => _RenameTabState();
}

class _RenameTabState extends State<_RenameTab> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.name);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Slide Name',
              style: TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          TextField(
            controller: _ctrl,
            style: const TextStyle(color: Colors.white),
            onChanged: widget.onNameChanged,
            decoration: InputDecoration(
              hintText: 'e.g. Slide 1 — Newton's Laws',
              hintStyle: const TextStyle(color: Colors.white24),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.06),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.white12),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.white12),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFF00BCD4)),
              ),
              prefixIcon: const Icon(Icons.label_outline_rounded,
                  color: Colors.white38),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Name is stored with the slide for your reference.',
            style: TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

// ── Crop Overlay Painter ──────────────────────────────────────────────────────

class _CropOverlayPainter extends CustomPainter {
  final double left, top, right, bottom;
  const _CropOverlayPainter(
      {required this.left,
      required this.top,
      required this.right,
      required this.bottom});

  @override
  void paint(Canvas canvas, Size size) {
    final cropRect = Rect.fromLTRB(
      left * size.width,
      top * size.height,
      right * size.width,
      bottom * size.height,
    );

    // Dim outside
    final dimPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRect(cropRect)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(
        dimPath, Paint()..color = Colors.black.withValues(alpha: 0.55));

    // Border
    canvas.drawRect(
      cropRect,
      Paint()
        ..color = const Color(0xFF00BCD4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // Handles
    final hp = Paint()
      ..color = const Color(0xFF00BCD4)
      ..style = PaintingStyle.fill;
    for (final c in [
      cropRect.topLeft,
      cropRect.topRight,
      cropRect.bottomLeft,
      cropRect.bottomRight,
    ]) {
      canvas.drawCircle(c, 8, hp);
      canvas.drawCircle(
          c,
          8,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2);
    }

    // Grid lines
    final gp = Paint()
      ..color = Colors.white.withValues(alpha: 0.2)
      ..strokeWidth = 0.8;
    final tw = cropRect.width / 3;
    final th = cropRect.height / 3;
    for (int i = 1; i <= 2; i++) {
      canvas.drawLine(Offset(cropRect.left + tw * i, cropRect.top),
          Offset(cropRect.left + tw * i, cropRect.bottom), gp);
      canvas.drawLine(Offset(cropRect.left, cropRect.top + th * i),
          Offset(cropRect.right, cropRect.top + th * i), gp);
    }
  }

  @override
  bool shouldRepaint(_CropOverlayPainter old) =>
      old.left != left ||
      old.top != top ||
      old.right != right ||
      old.bottom != bottom;
}

// ── Edit Chip ─────────────────────────────────────────────────────────────────

class _EditChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool active;
  const _EditChip(
      {required this.label, required this.onTap, this.active = false});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: active
              ? const Color(0xFF00BCD4).withValues(alpha: 0.15)
              : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: active ? const Color(0xFF00BCD4) : Colors.white12,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? const Color(0xFF00BCD4) : Colors.white60,
            fontSize: 13,
            fontWeight:
                active ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
