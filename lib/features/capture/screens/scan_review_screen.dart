import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:test123/core/providers/app_providers.dart';
import 'package:test123/core/services/pdf_generator_service.dart';
import 'package:test123/features/capture/screens/image_edit_screen.dart';
import 'package:test123/features/capture/widgets/course_tag_sheet.dart';

class ScanReviewScreen extends ConsumerStatefulWidget {
  const ScanReviewScreen({super.key});

  @override
  ConsumerState<ScanReviewScreen> createState() => _ScanReviewScreenState();
}

class _ScanReviewScreenState extends ConsumerState<ScanReviewScreen>
    with TickerProviderStateMixin {
  bool _checkingDuplicates = false;
  bool _generatingPdf = false;
  List<int> _duplicateIndices = [];
  bool _showOrderView = false;

  late final AnimationController _enterCtrl;
  late final Animation<double> _enterFade;

  @override
  void initState() {
    super.initState();
    _enterCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..forward();
    _enterFade =
        CurvedAnimation(parent: _enterCtrl, curve: Curves.easeOut);

    WidgetsBinding.instance
        .addPostFrameCallback((_) => _detectDuplicates());
  }

  @override
  void dispose() {
    _enterCtrl.dispose();
    super.dispose();
  }

  Future<void> _detectDuplicates() async {
    final slides = ref.read(capturedSlidesProvider);
    if (slides.length < 2) return;
    setState(() => _checkingDuplicates = true);
    final dupes = await PdfGeneratorService.findDuplicates(slides);
    if (mounted) {
      setState(() {
        _duplicateIndices = dupes;
        _checkingDuplicates = false;
      });
      if (dupes.isNotEmpty) _showDuplicateSnack(dupes.length);
    }
  }

  void _showDuplicateSnack(int count) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Found $count possible duplicate(s)'),
        action: SnackBarAction(
          label: 'Remove All',
          onPressed: _removeDuplicates,
        ),
        backgroundColor: const Color(0xFF21262D),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _removeDuplicates() {
    final notifier = ref.read(capturedSlidesProvider.notifier);
    final sorted = [..._duplicateIndices]..sort((a, b) => b.compareTo(a));
    for (final i in sorted) {
      notifier.removeAt(i);
    }
    setState(() => _duplicateIndices = []);
  }

  Future<void> _openEditor(int index) async {
    final slides = ref.read(capturedSlidesProvider);
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => ImageEditScreen(
          imagePath: slides[index],
          slideIndex: index + 1,
        ),
      ),
    );
    if (result != null && mounted) {
      ref.read(capturedSlidesProvider.notifier).updateAt(index, result);
    }
  }

  Future<void> _generatePdf() async {
    final slides = ref.read(capturedSlidesProvider);
    if (slides.isEmpty) return;

    final courseName = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const CourseTagSheet(),
    );

    if (courseName == null || !mounted) return;

    setState(() => _generatingPdf = true);
    try {
      final courseId = courseName.toLowerCase().replaceAll(' ', '_');
      final lecture = await PdfGeneratorService.instance.generateAndSave(
        imagePaths: slides,
        courseName: courseName,
        courseId: courseId,
      );
      await ref.read(lecturesProvider.notifier).addLecture(lecture);

      if (mounted) {
        ref.read(capturedSlidesProvider.notifier).clear();
        ref.read(scanSessionProvider.notifier).reset();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '✓ PDF saved! ${lecture.slideCount} slides → $courseName'),
            backgroundColor: const Color(0xFF1B5E20),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
        );
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _generatingPdf = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final slides = ref.watch(capturedSlidesProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      body: FadeTransition(
        opacity: _enterFade,
        child: CustomScrollView(
          slivers: [
            // ── App Bar ─────────────────────────────────────────────────────
            SliverAppBar(
              backgroundColor: const Color(0xFF161B22),
              pinned: true,
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Review Slides',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '${slides.length} captured',
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              actions: [
                // Duplicate check
                if (_checkingDuplicates)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Center(
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white54),
                      ),
                    ),
                  )
                else if (_duplicateIndices.isNotEmpty)
                  TextButton.icon(
                    onPressed: _removeDuplicates,
                    icon: const Icon(Icons.auto_fix_high,
                        size: 16, color: Colors.orange),
                    label: Text(
                      'Dupes (${_duplicateIndices.length})',
                      style: const TextStyle(color: Colors.orange, fontSize: 12),
                    ),
                  ),

                // Grid / Order toggle
                IconButton(
                  icon: Icon(
                    _showOrderView
                        ? Icons.grid_view_rounded
                        : Icons.reorder_rounded,
                    color: Colors.white70,
                  ),
                  tooltip: _showOrderView ? 'Grid view' : 'Reorder',
                  onPressed: () =>
                      setState(() => _showOrderView = !_showOrderView),
                ),
              ],
            ),

            // ── Content ──────────────────────────────────────────────────────
            if (slides.isEmpty)
              const SliverFillRemaining(child: _EmptyState())
            else if (_showOrderView)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                sliver: _ReorderList(
                  slides: slides,
                  duplicateIndices: _duplicateIndices,
                  onDelete: (i) =>
                      ref.read(capturedSlidesProvider.notifier).removeAt(i),
                  onEdit: _openEditor,
                  onReorder: (oldIndex, newIndex) => ref
                      .read(capturedSlidesProvider.notifier)
                      .reorder(oldIndex, newIndex),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                sliver: _PhotoGrid(
                  slides: slides,
                  duplicateIndices: _duplicateIndices,
                  onDelete: (i) =>
                      ref.read(capturedSlidesProvider.notifier).removeAt(i),
                  onEdit: _openEditor,
                ),
              ),
          ],
        ),
      ),

      // ── Bottom PDF Button ─────────────────────────────────────────────────
      bottomNavigationBar: slides.isEmpty
          ? null
          : Container(
              color: const Color(0xFF0D1117),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              child: FilledButton.icon(
                onPressed: _generatingPdf ? null : _generatePdf,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF3949AB),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                icon: _generatingPdf
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.picture_as_pdf_rounded,
                        color: Colors.white),
                label: Text(
                  _generatingPdf
                      ? 'Generating PDF…'
                      : 'Create PDF (${slides.length} slides)',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
    );
  }
}

// ── Photo Grid ────────────────────────────────────────────────────────────────

class _PhotoGrid extends StatelessWidget {
  final List<String> slides;
  final List<int> duplicateIndices;
  final void Function(int) onDelete;
  final void Function(int) onEdit;

  const _PhotoGrid({
    required this.slides,
    required this.duplicateIndices,
    required this.onDelete,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return SliverGrid(
      delegate: SliverChildBuilderDelegate(
        (ctx, index) {
          final isDupe = duplicateIndices.contains(index);
          return _GridSlideCard(
            imagePath: slides[index],
            index: index,
            isDuplicate: isDupe,
            onDelete: () => onDelete(index),
            onEdit: () => onEdit(index),
          );
        },
        childCount: slides.length,
      ),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 4 / 3,
      ),
    );
  }
}

class _GridSlideCard extends StatelessWidget {
  final String imagePath;
  final int index;
  final bool isDuplicate;
  final VoidCallback onDelete;
  final VoidCallback onEdit;

  const _GridSlideCard({
    required this.imagePath,
    required this.index,
    required this.isDuplicate,
    required this.onDelete,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onEdit,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Image
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.file(
              File(imagePath),
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                color: const Color(0xFF21262D),
                child: const Icon(Icons.broken_image,
                    color: Colors.white24, size: 40),
              ),
            ),
          ),

          // Duplicate overlay
          if (isDuplicate)
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  color: Colors.orange.withValues(alpha: 0.2),
                ),
              ),
            ),

          // Border
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isDuplicate
                      ? Colors.orange.withValues(alpha: 0.7)
                      : Colors.white.withValues(alpha: 0.08),
                  width: isDuplicate ? 2 : 1,
                ),
              ),
            ),
          ),

          // Slide number badge
          Positioned(
            top: 8,
            left: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${index + 1}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),

          // Dupe badge
          if (isDuplicate)
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'DUPE',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),

          // Bottom action bar
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(14)),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.8),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    GestureDetector(
                      onTap: onEdit,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.tune_rounded,
                            color: Colors.white70, size: 16),
                      ),
                    ),
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: onDelete,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color:
                              Colors.redAccent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.delete_outline_rounded,
                            color: Colors.redAccent, size: 16),
                      ),
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

// ── Reorder List ──────────────────────────────────────────────────────────────

class _ReorderList extends StatelessWidget {
  final List<String> slides;
  final List<int> duplicateIndices;
  final void Function(int) onDelete;
  final void Function(int) onEdit;
  final void Function(int, int) onReorder;

  const _ReorderList({
    required this.slides,
    required this.duplicateIndices,
    required this.onDelete,
    required this.onEdit,
    required this.onReorder,
  });

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: ReorderableListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        buildDefaultDragHandles: false,
        onReorder: onReorder,
        itemCount: slides.length,
        itemBuilder: (ctx, index) {
          final isDupe = duplicateIndices.contains(index);
          return _ListSlideCard(
            key: ValueKey(slides[index]),
            imagePath: slides[index],
            index: index,
            isDuplicate: isDupe,
            onDelete: () => onDelete(index),
            onEdit: () => onEdit(index),
          );
        },
      ),
    );
  }
}

class _ListSlideCard extends StatelessWidget {
  final String imagePath;
  final int index;
  final bool isDuplicate;
  final VoidCallback onDelete;
  final VoidCallback onEdit;

  const _ListSlideCard({
    super.key,
    required this.imagePath,
    required this.index,
    required this.isDuplicate,
    required this.onDelete,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDuplicate
              ? Colors.orange.withValues(alpha: 0.7)
              : Colors.white12,
          width: isDuplicate ? 2 : 1,
        ),
        color: const Color(0xFF161B22),
      ),
      child: Row(
        children: [
          // Drag handle
          ReorderableDragStartListener(
            index: index,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 16),
              child:
                  Icon(Icons.drag_handle_rounded, color: Colors.white30),
            ),
          ),

          // Thumbnail
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(
              File(imagePath),
              width: 80,
              height: 60,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: 80,
                height: 60,
                color: Colors.white10,
                child: const Icon(Icons.broken_image,
                    color: Colors.white24),
              ),
            ),
          ),
          const SizedBox(width: 14),

          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Slide ${index + 1}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                if (isDuplicate)
                  const Text(
                    '⚠ Possible duplicate',
                    style:
                        TextStyle(color: Colors.orange, fontSize: 11),
                  ),
              ],
            ),
          ),

          // Actions
          IconButton(
            icon: const Icon(Icons.tune_rounded,
                color: Colors.white54, size: 20),
            onPressed: onEdit,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded,
                color: Colors.redAccent, size: 20),
            onPressed: onDelete,
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

// ── Empty State ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.photo_library_outlined,
              size: 72, color: Colors.white12),
          const SizedBox(height: 16),
          const Text(
            'No slides captured yet',
            style: TextStyle(color: Colors.white38, fontSize: 16),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Go back to camera'),
          ),
        ],
      ),
    );
  }
}
