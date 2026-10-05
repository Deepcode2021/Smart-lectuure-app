import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import 'package:test123/core/providers/app_providers.dart';
import 'package:test123/models/lecture_model.dart';

class CourseDetailScreen extends ConsumerWidget {
  final String courseName;
  const CourseDetailScreen({super.key, required this.courseName});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lecturesAsync = ref.watch(courseLecturesProvider(courseName));

    return Scaffold(
      appBar: AppBar(
        title: Text(
          courseName,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: lecturesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text(
            'Error loading lectures: $e',
            style: const TextStyle(color: Colors.redAccent),
          ),
        ),
        data: (lectures) {
          if (lectures.isEmpty) {
            return _buildEmptyState(context, ref);
          }
          return _buildLectureList(context, ref, lectures);
        },
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, WidgetRef ref) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF21262D),
            ),
            child: const Icon(
              Icons.picture_as_pdf_outlined,
              color: Colors.white24,
              size: 44,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'No lectures yet',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.white54,
                ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Scan a lecture and tag it to this course\nto see it appear here.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white38, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildLectureList(
    BuildContext context,
    WidgetRef ref,
    List<Lecture> lectures,
  ) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      itemCount: lectures.length,
      itemBuilder: (ctx, i) {
        final lecture = lectures[i];
        return _LectureCard(
          lecture: lecture,
          onOpen: () => _openPdf(ctx, lecture.pdfPath),
          onShare: () => _sharePdf(ctx, lecture.pdfPath),
          onDelete: () => _deleteLecture(ctx, ref, lecture),
          onRename: () => _renameLecture(ctx, ref, lecture),
        );
      },
    );
  }

  Future<void> _openPdf(BuildContext context, String pdfPath) async {
    if (pdfPath.isEmpty || !await File(pdfPath).exists()) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('PDF file not found.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }
    await OpenFilex.open(pdfPath);
  }

  Future<void> _sharePdf(BuildContext context, String pdfPath) async {
    if (pdfPath.isEmpty || !await File(pdfPath).exists()) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('PDF file not found.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }
    await Share.shareXFiles(
      [XFile(pdfPath)],
      subject: 'Lecture PDF – $courseName',
    );
  }

  Future<void> _deleteLecture(
    BuildContext context,
    WidgetRef ref,
    Lecture lecture,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF21262D),
        title: const Text(
          'Delete Lecture?',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'This will remove the record. The PDF file on disk will also be deleted.',
          style: const TextStyle(color: Colors.white60),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.redAccent,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      // Delete file from disk
      final file = File(lecture.pdfPath);
      if (await file.exists()) await file.delete();
      // Remove from DB
      await ref.read(lecturesProvider.notifier).deleteLecture(lecture.id);
    }
  }

  Future<void> _renameLecture(
    BuildContext context,
    WidgetRef ref,
    Lecture lecture,
  ) async {
    final controller = TextEditingController(text: lecture.courseName);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF21262D),
        title: const Text(
          'Rename Lecture',
          style: TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'Course Name',
            labelStyle: const TextStyle(color: Colors.white54),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Colors.white12),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFF3949AB)),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF3949AB),
            ),
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    controller.dispose();

    if (newName != null && newName.isNotEmpty) {
      await ref.read(lecturesProvider.notifier).updateLecture(
            lecture.copyWith(courseName: newName),
          );
    }
  }
}

// ── Lecture Card ──────────────────────────────────────────────────────────────

class _LectureCard extends StatelessWidget {
  final Lecture lecture;
  final VoidCallback onOpen;
  final VoidCallback onShare;
  final VoidCallback onDelete;
  final VoidCallback onRename;

  const _LectureCard({
    required this.lecture,
    required this.onOpen,
    required this.onShare,
    required this.onDelete,
    required this.onRename,
  });

  @override
  Widget build(BuildContext context) {
    final dateLabel = DateFormat('dd MMM yyyy, HH:mm').format(lecture.date);
    final hasPdf = lecture.pdfPath.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: const Color(0xFF21262D),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: hasPdf
                        ? const Color(0xFF3949AB).withValues(alpha: 0.2)
                        : Colors.white10,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    hasPdf
                        ? Icons.picture_as_pdf_rounded
                        : Icons.pending_rounded,
                    color: hasPdf
                        ? const Color(0xFF7986CB)
                        : Colors.white38,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        lecture.courseName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        dateLabel,
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                // More actions menu
                PopupMenuButton<String>(
                  color: const Color(0xFF30363D),
                  icon: const Icon(Icons.more_vert,
                      color: Colors.white38, size: 20),
                  onSelected: (value) {
                    switch (value) {
                      case 'rename':
                        onRename();
                      case 'delete':
                        onDelete();
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'rename',
                      child: Row(
                        children: [
                          Icon(Icons.edit_outlined,
                              color: Colors.white70, size: 18),
                          SizedBox(width: 10),
                          Text('Rename',
                              style: TextStyle(color: Colors.white70)),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline,
                              color: Colors.redAccent, size: 18),
                          SizedBox(width: 10),
                          Text('Delete',
                              style: TextStyle(color: Colors.redAccent)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Meta pills
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              children: [
                _MetaPill(
                  label: '${lecture.slideCount} slides',
                  icon: Icons.photo_library_outlined,
                ),
                if (hasPdf)
                  _MetaPill(
                    label: 'PDF ready',
                    icon: Icons.check_circle_outline,
                    color: const Color(0xFF43A047),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 12),
          const Divider(height: 1, color: Colors.white10),

          // Action buttons
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                _ActionBtn(
                  icon: Icons.open_in_new_rounded,
                  label: 'Open',
                  onTap: hasPdf ? onOpen : null,
                ),
                _ActionBtn(
                  icon: Icons.share_rounded,
                  label: 'Share',
                  onTap: hasPdf ? onShare : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  const _MetaPill({
    required this.label,
    required this.icon,
    this.color = const Color(0xFF8B949E),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: color, fontSize: 11)),
        ],
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  const _ActionBtn({
    required this.icon,
    required this.label,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: TextButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 16,
            color: onTap != null ? const Color(0xFF7986CB) : Colors.white24),
        label: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: onTap != null ? const Color(0xFF7986CB) : Colors.white24,
          ),
        ),
      ),
    );
  }
}
