import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:test123/core/providers/app_providers.dart';
import 'package:test123/features/capture/screens/mode_select_screen.dart';
import 'package:test123/features/courses/screens/course_detail_screen.dart';
import 'package:test123/models/lecture_model.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {

  static const _courseIcons = <String, IconData>{
    'Thermodynamics': Icons.local_fire_department_rounded,
    'Mechanics of Materials': Icons.architecture_rounded,
    'Kinematics of Machinery': Icons.settings_rounded,
    'Materials Science': Icons.science_rounded,
  };

  static const _courseGradients = <String, List<Color>>{
    'Thermodynamics': [Color(0xFFEF6C00), Color(0xFFFF8F00)],
    'Mechanics of Materials': [Color(0xFF1565C0), Color(0xFF1E88E5)],
    'Kinematics of Machinery': [Color(0xFF6A1B9A), Color(0xFFAB47BC)],
    'Materials Science': [Color(0xFF2E7D32), Color(0xFF43A047)],
  };

  IconData _iconForCourse(String name) {
    return _courseIcons[name] ?? Icons.book_rounded;
  }

  List<Color> _gradientForCourse(String name) {
    return _courseGradients[name] ??
        [const Color(0xFF37474F), const Color(0xFF455A64)];
  }

  @override
  Widget build(BuildContext context) {
    final statsAsync = ref.watch(appStatsProvider);
    final coursesAsync = ref.watch(coursesProvider);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // ── Animated App Bar ────────────────────────────────────────────────
          SliverAppBar(
            expandedHeight: 160,
            floating: false,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.only(left: 20, bottom: 16),
              title: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Smart Lecture',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.white.withValues(alpha: 0.7),
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  const Text(
                    'Scanner',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF1A237E), Color(0xFF283593)],
                  ),
                ),
                child: Stack(
                  children: [
                    Positioned(
                      right: -30,
                      top: -30,
                      child: Container(
                        width: 180,
                        height: 180,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.05),
                        ),
                      ),
                    ),
                    Positioned(
                      right: 20,
                      top: 20,
                      child: Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.04),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.more_vert, color: Colors.white),
                onPressed: () {},
              ),
            ],
          ),

          // ── Quick Stats ──────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
              child: statsAsync.when(
                loading: () => _StatsCardShimmer(),
                error: (e, _) => Text('Error: $e',
                    style: const TextStyle(color: Colors.redAccent)),
                data: (stats) => _StatsCard(
                  courses: stats.totalCourses,
                  lectures: stats.totalLectures,
                  pdfs: stats.totalPdfs,
                ),
              ),
            ),
          ),

          // ── Section Header ────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'My Semester Courses',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    coursesAsync.valueOrNull?.length.toString() ?? '—',
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Course Cards ─────────────────────────────────────────────────
          coursesAsync.when(
            loading: () => const SliverToBoxAdapter(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(),
                ),
              ),
            ),
            error: (e, _) => SliverToBoxAdapter(
              child: Center(child: Text('$e')),
            ),
            data: (courses) => SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
              sliver: SliverList.builder(
                itemCount: courses.length,
                itemBuilder: (ctx, i) {
                  final course = courses[i];
                  return _CourseCard(
                    course: course,
                    icon: _iconForCourse(course.name),
                    gradientColors: _gradientForCourse(course.name),
                    onTap: () => Navigator.push(
                      ctx,
                      MaterialPageRoute(
                        builder: (_) =>
                            CourseDetailScreen(courseName: course.name),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'scan_fab',
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ModeSelectScreen()),
          );
        },
        backgroundColor: const Color(0xFF3949AB),
        icon: const Icon(Icons.camera_alt_rounded, color: Colors.white),
        label: const Text(
          'Start Scanning',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

// ── Stats Card ────────────────────────────────────────────────────────────────

class _StatsCard extends StatelessWidget {
  final int courses;
  final int lectures;
  final int pdfs;
  const _StatsCard({
    required this.courses,
    required this.lectures,
    required this.pdfs,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [Color(0xFF21262D), Color(0xFF1C2128)],
        ),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _StatCell(
            value: '$courses',
            label: 'Courses',
            icon: Icons.folder_outlined,
            color: const Color(0xFF00BCD4),
          ),
          _Divider(),
          _StatCell(
            value: '$lectures',
            label: 'Lectures',
            icon: Icons.auto_stories_outlined,
            color: const Color(0xFF3949AB),
          ),
          _Divider(),
          _StatCell(
            value: '$pdfs',
            label: 'PDFs',
            icon: Icons.picture_as_pdf_outlined,
            color: const Color(0xFF43A047),
          ),
        ],
      ),
    );
  }
}



class _StatCell extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;
  final Color color;
  const _StatCell({
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: const TextStyle(color: Colors.white38, fontSize: 11),
        ),
      ],
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 50,
      color: Colors.white10,
    );
  }
}

class _StatsCardShimmer extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 100,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: const Color(0xFF21262D),
        border: Border.all(color: Colors.white10),
      ),
      child: const Center(child: CircularProgressIndicator()),
    );
  }
}

// ── Course Card ────────────────────────────────────────────────────────────────

class _CourseCard extends ConsumerWidget {
  final Course course;
  final IconData icon;
  final List<Color> gradientColors;
  final VoidCallback onTap;

  const _CourseCard({
    required this.course,
    required this.icon,
    required this.gradientColors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lecturesAsync = ref.watch(courseLecturesProvider(course.name));

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              color: const Color(0xFF21262D),
              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            ),
            child: Row(
              children: [
                // Icon Container
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: gradientColors,
                    ),
                  ),
                  child: Icon(icon, color: Colors.white, size: 26),
                ),
                const SizedBox(width: 16),

                // Text
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        course.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      lecturesAsync.when(
                        loading: () => const Text(
                          '…',
                          style: TextStyle(color: Colors.white38, fontSize: 12),
                        ),
                        error: (err, st) => const Text(
                          '0 lectures',
                          style: TextStyle(color: Colors.white38, fontSize: 12),
                        ),
                        data: (lectures) => Text(
                          '${lectures.length} lecture${lectures.length != 1 ? 's' : ''}',
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Arrow
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 14,
                    color: Colors.white38,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
