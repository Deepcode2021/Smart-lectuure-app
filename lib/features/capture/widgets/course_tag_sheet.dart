import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:test123/core/providers/app_providers.dart';
import 'package:test123/models/lecture_model.dart';

/// Bottom sheet for selecting or creating a course before PDF generation.
class CourseTagSheet extends ConsumerStatefulWidget {
  const CourseTagSheet({super.key});

  @override
  ConsumerState<CourseTagSheet> createState() => _CourseTagSheetState();
}

class _CourseTagSheetState extends ConsumerState<CourseTagSheet> {
  String? _selectedCourse;
  bool _isCustom = false;
  final _customController = TextEditingController();

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

  void _confirm() {
    final course = _isCustom
        ? _customController.text.trim()
        : _selectedCourse;
    if (course == null || course.isEmpty) return;

    // Add custom course to database if it's new
    if (_isCustom) {
      ref.read(coursesProvider.notifier).addCourse(Course(name: course));
    }

    Navigator.pop(context, course);
  }

  @override
  Widget build(BuildContext context) {
    final coursesAsync = ref.watch(coursesProvider);

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF161B22),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Title
          Row(
            children: [
              const Icon(Icons.local_library_outlined,
                  color: Color(0xFF00BCD4)),
              const SizedBox(width: 10),
              const Text(
                'Tag Course',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Select the subject for this lecture PDF.',
            style: TextStyle(color: Colors.white54, fontSize: 13),
          ),
          const SizedBox(height: 20),

          // Course chips
          coursesAsync.when(
            loading: () => const CircularProgressIndicator(),
            error: (e, _) => Text('Error: $e',
                style: const TextStyle(color: Colors.redAccent)),
            data: (courses) => Wrap(
              spacing: 8,
              runSpacing: 8,
              children: courses.map((course) {
                final selected = _selectedCourse == course.name && !_isCustom;
                return ChoiceChip(
                  label: Text(course.name),
                  selected: selected,
                  onSelected: (_) {
                    setState(() {
                      _selectedCourse = course.name;
                      _isCustom = false;
                    });
                  },
                  selectedColor: const Color(0xFF3949AB),
                  labelStyle: TextStyle(
                    color: selected ? Colors.white : Colors.white70,
                    fontWeight: selected
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                  backgroundColor: const Color(0xFF21262D),
                  side: BorderSide(
                    color: selected
                        ? const Color(0xFF3949AB)
                        : Colors.white12,
                  ),
                );
              }).toList()
                ..add(
                  ChoiceChip(
                    label: const Text('+ Custom'),
                    selected: _isCustom,
                    onSelected: (_) {
                      setState(() {
                        _isCustom = true;
                        _selectedCourse = null;
                      });
                    },
                    selectedColor: const Color(0xFF00BCD4).withValues(alpha: 0.3),
                    labelStyle: TextStyle(
                      color: _isCustom
                          ? const Color(0xFF00BCD4)
                          : Colors.white54,
                    ),
                    backgroundColor: const Color(0xFF21262D),
                    side: BorderSide(
                      color: _isCustom
                          ? const Color(0xFF00BCD4)
                          : Colors.white12,
                    ),
                  ),
                ),
            ),
          ),

          // Custom course text field
          if (_isCustom) ...[
            const SizedBox(height: 16),
            TextField(
              controller: _customController,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Custom Course Name',
                labelStyle: const TextStyle(color: Colors.white54),
                filled: true,
                fillColor: const Color(0xFF21262D),
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
                  borderSide: const BorderSide(
                    color: Color(0xFF00BCD4),
                  ),
                ),
              ),
            ),
          ],

          const SizedBox(height: 24),

          // Confirm button
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _confirm,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF3949AB),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(Icons.picture_as_pdf, color: Colors.white),
              label: const Text(
                'Generate PDF',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
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
