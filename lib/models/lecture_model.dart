import 'package:uuid/uuid.dart';

class Lecture {
  final String id;
  final String courseId;
  final String courseName;
  final String title;
  final DateTime date;
  final int slideCount;
  final String pdfPath;

  Lecture({
    String? id,
    this.courseId = '',
    required this.courseName,
    this.title = '',
    required this.date,
    this.slideCount = 0,
    this.pdfPath = '',
  }) : id = id ?? const Uuid().v4();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'course_id': courseId,
      'course_name': courseName,
      'title': title,
      'date': date.toIso8601String(),
      'slide_count': slideCount,
      'pdf_path': pdfPath,
    };
  }

  factory Lecture.fromMap(Map<String, dynamic> map) {
    return Lecture(
      id: map['id'] as String,
      courseId: map['course_id'] as String? ?? '',
      courseName: map['course_name'] as String,
      title: map['title'] as String? ?? '',
      date: DateTime.parse(map['date'] as String),
      slideCount: map['slide_count'] as int,
      pdfPath: map['pdf_path'] as String? ?? '',
    );
  }

  Lecture copyWith({
    String? id,
    String? courseId,
    String? courseName,
    String? title,
    DateTime? date,
    int? slideCount,
    String? pdfPath,
  }) {
    return Lecture(
      id: id ?? this.id,
      courseId: courseId ?? this.courseId,
      courseName: courseName ?? this.courseName,
      title: title ?? this.title,
      date: date ?? this.date,
      slideCount: slideCount ?? this.slideCount,
      pdfPath: pdfPath ?? this.pdfPath,
    );
  }

  @override
  String toString() =>
      'Lecture(id: $id, courseName: $courseName, date: $date, slides: $slideCount)';
}

class Course {
  final String name;
  final String iconName;
  final int lectureCount;

  const Course({
    required this.name,
    this.iconName = '',
    this.lectureCount = 0,
  });

  Course copyWith({String? name, String? iconName, int? lectureCount}) {
    return Course(
      name: name ?? this.name,
      iconName: iconName ?? this.iconName,
      lectureCount: lectureCount ?? this.lectureCount,
    );
  }
}
