import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:test123/core/constants/app_constants.dart';
import 'package:test123/models/lecture_model.dart';

class DatabaseService {
  DatabaseService._();
  static final DatabaseService instance = DatabaseService._();

  Database? _db;

  Future<Database> get database async {
    _db ??= await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, AppConstants.dbName);
    return openDatabase(
      path,
      version: AppConstants.dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE ${AppConstants.coursesTable} (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL UNIQUE,
        icon_name TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE ${AppConstants.lecturesTable} (
        id TEXT PRIMARY KEY,
        course_id TEXT NOT NULL,
        course_name TEXT NOT NULL,
        title TEXT NOT NULL DEFAULT '',
        date TEXT NOT NULL,
        slide_count INTEGER NOT NULL DEFAULT 0,
        pdf_path TEXT NOT NULL DEFAULT '',
        FOREIGN KEY (course_id) REFERENCES ${AppConstants.coursesTable} (id)
      )
    ''');

    // Insert default courses
    for (final name in AppConstants.defaultCourses) {
      await db.insert(
        AppConstants.coursesTable,
        {
          'id': name.toLowerCase().replaceAll(' ', '_'),
          'name': name,
          'icon_name': _iconForCourse(name),
          'created_at': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Handle future migrations here
  }

  static String _iconForCourse(String name) {
    switch (name) {
      case 'Thermodynamics':
        return 'local_fire_department';
      case 'Mechanics of Materials':
        return 'architecture';
      case 'Kinematics of Machinery':
        return 'settings';
      case 'Materials Science':
        return 'science';
      default:
        return 'book';
    }
  }

  // ── Courses ──────────────────────────────────────────────────────────────

  Future<void> insertCourse(Course course) async {
    final db = await database;
    await db.insert(
      AppConstants.coursesTable,
      {
        'id': course.name.toLowerCase().replaceAll(' ', '_'),
        'name': course.name,
        'icon_name': course.iconName,
        'created_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Course>> getAllCourses() async {
    final db = await database;
    final maps = await db.query(
      AppConstants.coursesTable,
      orderBy: 'name ASC',
    );
    return maps.map((m) => Course(
      name: m['name'] as String,
      iconName: m['icon_name'] as String? ?? '',
    )).toList();
  }

  Future<Course?> getCourseByName(String name) async {
    final db = await database;
    final maps = await db.query(
      AppConstants.coursesTable,
      where: 'name = ?',
      whereArgs: [name],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return Course(
      name: maps.first['name'] as String,
      iconName: maps.first['icon_name'] as String? ?? '',
    );
  }

  Future<void> deleteCourse(String id) async {
    final db = await database;
    await db.delete(
      AppConstants.coursesTable,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ── Lectures ──────────────────────────────────────────────────────────────

  Future<void> insertLecture(Lecture lecture) async {
    final db = await database;
    await db.insert(
      AppConstants.lecturesTable,
      lecture.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Lecture>> getAllLectures() async {
    final db = await database;
    final maps = await db.query(
      AppConstants.lecturesTable,
      orderBy: 'date DESC',
    );
    return maps.map(Lecture.fromMap).toList();
  }

  Future<List<Lecture>> getLecturesByCourse(String courseName) async {
    final db = await database;
    final maps = await db.query(
      AppConstants.lecturesTable,
      where: 'course_name = ?',
      whereArgs: [courseName],
      orderBy: 'date DESC',
    );
    return maps.map(Lecture.fromMap).toList();
  }

  Future<void> deleteLecture(String id) async {
    final db = await database;
    await db.delete(
      AppConstants.lecturesTable,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> updateLecture(Lecture lecture) async {
    final db = await database;
    await db.update(
      AppConstants.lecturesTable,
      lecture.toMap(),
      where: 'id = ?',
      whereArgs: [lecture.id],
    );
  }

  // ── Stats ─────────────────────────────────────────────────────────────────

  Future<int> getTotalLectureCount() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM ${AppConstants.lecturesTable}',
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<List<String>> getDistinctCourseNames() async {
    final db = await database;
    final maps = await db.rawQuery(
      'SELECT DISTINCT course_name FROM ${AppConstants.lecturesTable}',
    );
    return maps.map((m) => m['course_name'] as String).toList();
  }

  Future<int> getLectureCountForCourse(String courseName) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM ${AppConstants.lecturesTable} WHERE course_name = ?',
      [courseName],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<int> getTotalCourseCount() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM ${AppConstants.coursesTable}',
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }
}
