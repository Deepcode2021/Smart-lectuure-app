// Core app constants for Smart Lecture Scanner
class AppConstants {
  AppConstants._();

  // App
  static const String appName = 'Smart Lecture Scanner';
  static const String appVersion = '1.0.0';

  // Database
  static const String dbName = 'smart_lecture_scanner.db';
  static const int dbVersion = 2;
  static const String coursesTable = 'courses';
  static const String lecturesTable = 'lectures';

  // Default courses
  static const List<String> defaultCourses = [
    'Thermodynamics',
    'Mechanics of Materials',
    'Kinematics of Machinery',
    'Materials Science',
  ];

  // Camera & Frame Diffing
  static const double slideChangeThreshold = 0.18; // 18% pixel delta
  static const int stabilityCheckMs = 1000; // 1 second steady hold
  static const int frameAnalysisIntervalMs = 500; // analyze every 500ms
  static const int thumbnailWidth = 320;
  static const int thumbnailHeight = 180;

  // PDF
  static const double pdfPageWidth = 595.28; // A4 width in points
  static const double pdfPageHeight = 841.89; // A4 height in points
}
