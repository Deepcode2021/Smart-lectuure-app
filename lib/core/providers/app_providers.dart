import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:test123/core/constants/app_constants.dart';
import 'package:test123/core/services/camera_engine_service.dart';
import 'package:test123/core/services/database_service.dart';
import 'package:test123/core/services/document_scanner_service.dart';
import 'package:test123/models/lecture_model.dart';

// ── Courses State ─────────────────────────────────────────────────────────────

class CoursesNotifier extends AsyncNotifier<List<Course>> {
  @override
  Future<List<Course>> build() => DatabaseService.instance.getAllCourses();

  Future<void> addCourse(Course course) async {
    await DatabaseService.instance.insertCourse(course);
    ref.invalidateSelf();
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
  }
}

final coursesProvider =
    AsyncNotifierProvider<CoursesNotifier, List<Course>>(
  CoursesNotifier.new,
);

// ── Lectures State ────────────────────────────────────────────────────────────

class LecturesNotifier extends AsyncNotifier<List<Lecture>> {
  @override
  Future<List<Lecture>> build() => DatabaseService.instance.getAllLectures();

  Future<void> addLecture(Lecture lecture) async {
    await DatabaseService.instance.insertLecture(lecture);
    ref.invalidateSelf();
  }

  Future<void> deleteLecture(String id) async {
    await DatabaseService.instance.deleteLecture(id);
    ref.invalidateSelf();
  }

  Future<void> updateLecture(Lecture lecture) async {
    await DatabaseService.instance.updateLecture(lecture);
    ref.invalidateSelf();
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
  }
}

final lecturesProvider =
    AsyncNotifierProvider<LecturesNotifier, List<Lecture>>(
  LecturesNotifier.new,
);

// ── Stats State ───────────────────────────────────────────────────────────────

class AppStats {
  final int totalLectures;
  final int totalCourses;
  final int totalPdfs;

  const AppStats({
    required this.totalLectures,
    required this.totalCourses,
    required this.totalPdfs,
  });

  static const AppStats empty = AppStats(
    totalLectures: 0,
    totalCourses: 0,
    totalPdfs: 0,
  );
}

final appStatsProvider = FutureProvider<AppStats>((ref) async {
  final lectures = await ref.watch(lecturesProvider.future);
  final courses = await ref.watch(coursesProvider.future);
  return AppStats(
    totalLectures: lectures.length,
    totalCourses: courses.length,
    totalPdfs: lectures.where((l) => l.pdfPath.isNotEmpty).length,
  );
});

// ── Course Lectures ───────────────────────────────────────────────────────────

final courseLecturesProvider =
    FutureProvider.family<List<Lecture>, String>((ref, courseName) async {
  ref.watch(lecturesProvider); // auto-refresh
  return DatabaseService.instance.getLecturesByCourse(courseName);
});

// ── All Course Names (default + DB) ──────────────────────────────────────────

final allCourseNamesProvider = FutureProvider<List<String>>((ref) async {
  ref.watch(lecturesProvider);
  ref.watch(coursesProvider);
  final dbNames = await DatabaseService.instance.getDistinctCourseNames();
  final merged = {...AppConstants.defaultCourses, ...dbNames}.toList()..sort();
  return merged;
});

// ── Captured Slides (in-memory during session) ────────────────────────────────

class CapturedSlidesNotifier extends Notifier<List<String>> {
  @override
  List<String> build() => [];

  void addSlide(String path) => state = [...state, path];

  void removeAt(int index) {
    final list = [...state];
    list.removeAt(index);
    state = list;
  }

  void reorder(int oldIndex, int newIndex) {
    final list = [...state];
    if (newIndex > oldIndex) newIndex--;
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);
    state = list;
  }

  void updateAt(int index, String newPath) {
    final list = [...state];
    list[index] = newPath;
    state = list;
  }

  void clear() => state = [];
}

final capturedSlidesProvider =
    NotifierProvider<CapturedSlidesNotifier, List<String>>(
  CapturedSlidesNotifier.new,
);

// ── Scan Session State ────────────────────────────────────────────────────────

enum ScanSessionStep {
  modeSelect,
  steadyPhone,
  cornerTap,     // AUTO: tap 4 corners
  roiSelect,     // MANUAL: drag crop box
  scanning,
  review,
}

class ScanSessionState {
  final ScanMode mode;
  final ScanSessionStep step;
  final RoiRect? roi;
  final List<CornerPoint>? corners;
  final bool isScanning;

  const ScanSessionState({
    this.mode = ScanMode.auto,
    this.step = ScanSessionStep.modeSelect,
    this.roi,
    this.corners,
    this.isScanning = false,
  });

  ScanSessionState copyWith({
    ScanMode? mode,
    ScanSessionStep? step,
    RoiRect? roi,
    List<CornerPoint>? corners,
    bool? isScanning,
  }) {
    return ScanSessionState(
      mode: mode ?? this.mode,
      step: step ?? this.step,
      roi: roi ?? this.roi,
      corners: corners ?? this.corners,
      isScanning: isScanning ?? this.isScanning,
    );
  }
}

class ScanSessionNotifier extends Notifier<ScanSessionState> {
  @override
  ScanSessionState build() => const ScanSessionState();

  void setMode(ScanMode mode) {
    state = state.copyWith(mode: mode);
  }

  void setStep(ScanSessionStep step) {
    state = state.copyWith(step: step);
  }

  void setRoi(RoiRect roi) {
    state = state.copyWith(roi: roi);
  }

  void setCorners(List<CornerPoint> corners) {
    state = state.copyWith(corners: corners);
  }

  void setScanning(bool value) {
    state = state.copyWith(isScanning: value);
  }

  void reset() {
    state = const ScanSessionState();
  }
}

final scanSessionProvider =
    NotifierProvider<ScanSessionNotifier, ScanSessionState>(
  ScanSessionNotifier.new,
);

// ── Auto-Scan Toggle ──────────────────────────────────────────────────────────

final autoScanEnabledProvider = StateProvider<bool>((ref) => false);

// ── Flash Toggle ──────────────────────────────────────────────────────────────

final flashEnabledProvider = StateProvider<bool>((ref) => false);
