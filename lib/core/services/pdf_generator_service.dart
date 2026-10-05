import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:test123/models/lecture_model.dart';
import 'package:intl/intl.dart';

class PdfGeneratorService {
  PdfGeneratorService._();
  static final PdfGeneratorService instance = PdfGeneratorService._();

  /// Generates a PDF from a list of image file paths and saves it to the
  /// application documents directory.
  ///
  /// Heavy image decoding runs in an isolate to prevent UI jank.
  ///
  /// Returns the saved [Lecture] with the pdf path set.
  Future<Lecture> generateAndSave({
    required List<String> imagePaths,
    required String courseName,
    String courseId = '',
  }) async {
    final pdf = pw.Document();
    final dateStr = DateFormat('yyyy-MM-dd_HHmm').format(DateTime.now());
    final safeCourse = courseName.replaceAll(RegExp(r'[^\w]'), '_');
    final fileName = '${safeCourse}_$dateStr.pdf';

    // Process all images in parallel isolates for maximum throughput
    final processedImages = await Future.wait(
      imagePaths.map((path) => _processImageInIsolate(path)),
    );

    for (final imageBytes in processedImages) {
      if (imageBytes == null) continue;

      final pdfImage = pw.MemoryImage(imageBytes);

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(12),
          build: (pw.Context context) {
            return pw.Center(
              child: pw.Image(pdfImage, fit: pw.BoxFit.contain),
            );
          },
        ),
      );
    }

    // Save to documents directory
    final docsDir = await getApplicationDocumentsDirectory();
    final pdfDir = Directory(p.join(docsDir.path, 'SmartLectureScanner'));
    if (!await pdfDir.exists()) await pdfDir.create(recursive: true);

    final pdfFile = File(p.join(pdfDir.path, fileName));
    final pdfBytes = await pdf.save();
    await pdfFile.writeAsBytes(pdfBytes);

    return Lecture(
      courseId: courseId,
      courseName: courseName,
      date: DateTime.now(),
      slideCount: imagePaths.length,
      pdfPath: pdfFile.path,
    );
  }

  /// Decodes and re-encodes an image in a background isolate.
  static Future<Uint8List?> _processImageInIsolate(String imagePath) async {
    try {
      return await Isolate.run(() async {
        final file = File(imagePath);
        if (!await file.exists()) return null;
        final bytes = await file.readAsBytes();
        final image = img.decodeImage(bytes);
        if (image == null) return null;
        return img.encodeJpg(image, quality: 88);
      });
    } catch (_) {
      return null;
    }
  }

  // ── Image Enhancements (Isolate-based) ───────────────────────────────────

  /// Applies grayscale + contrast boost to make projector slides more legible.
  static Future<String> applyEnhancement(
    String imagePath,
    ImageEnhancement enhancement,
  ) async {
    try {
      final result = await Isolate.run(() async {
        final file = File(imagePath);
        final bytes = await file.readAsBytes();
        img.Image? image = img.decodeImage(bytes);
        if (image == null) return null;

        switch (enhancement) {
          case ImageEnhancement.grayscale:
            image = img.grayscale(image);
          case ImageEnhancement.highContrast:
            image = img.adjustColor(image, contrast: 1.6, brightness: 1.05);
          case ImageEnhancement.magicColor:
            image = img.adjustColor(image, saturation: 1.4, contrast: 1.3);
          case ImageEnhancement.none:
            return null;
        }

        return img.encodeJpg(image, quality: 90);
      });

      if (result == null) return imagePath;

      final tempDir = await getApplicationDocumentsDirectory();
      final outPath = p.join(
        tempDir.path,
        'enhanced_${p.basename(imagePath)}',
      );
      await File(outPath).writeAsBytes(result);
      return outPath;
    } catch (_) {
      return imagePath;
    }
  }

  /// Rotates an image by [degrees] (must be 90, 180, or 270).
  static Future<String> rotateImage(String imagePath, int degrees) async {
    try {
      final result = await Isolate.run(() async {
        final file = File(imagePath);
        final bytes = await file.readAsBytes();
        img.Image? image = img.decodeImage(bytes);
        if (image == null) return null;

        image = img.copyRotate(image, angle: degrees.toDouble());
        return img.encodeJpg(image, quality: 90);
      });

      if (result == null) return imagePath;

      final tempDir = await getApplicationDocumentsDirectory();
      final outPath = p.join(
        tempDir.path,
        'rotated_${p.basename(imagePath)}',
      );
      await File(outPath).writeAsBytes(result);
      return outPath;
    } catch (_) {
      return imagePath;
    }
  }

  // ── Duplicate Detection (dHash in Isolate) ──────────────────────────────

  /// Returns indices of duplicate slides (those that are too similar to
  /// a previously seen slide in the list).
  static Future<List<int>> findDuplicates(List<String> imagePaths) async {
    try {
      // Compute all hashes in parallel isolates
      final hashes = await Future.wait(
        imagePaths.map((path) => _computeDHashInIsolate(path)),
      );

      final duplicates = <int>[];
      final seenHashes = <int>[];

      for (int i = 0; i < hashes.length; i++) {
        final hash = hashes[i];
        if (hash == null) continue;

        bool isDuplicate = false;
        for (final prev in seenHashes) {
          final distance = _hammingDistance(hash, prev);
          if (distance < 12) {
            isDuplicate = true;
            break;
          }
        }

        if (isDuplicate) {
          duplicates.add(i);
        } else {
          seenHashes.add(hash);
        }
      }
      return duplicates;
    } catch (_) {
      return [];
    }
  }

  static Future<int?> _computeDHashInIsolate(String imagePath) async {
    try {
      return await Isolate.run(() async {
        final bytes = await File(imagePath).readAsBytes();
        img.Image? image = img.decodeImage(bytes);
        if (image == null) return null;

        // Resize to 9×8 for dHash
        image = img.copyResize(image, width: 9, height: 8);
        int hash = 0;
        int bit = 0;
        for (int y = 0; y < 8; y++) {
          for (int x = 0; x < 8; x++) {
            final leftPixel = image.getPixel(x, y);
            final rightPixel = image.getPixel(x + 1, y);
            final leftLum = 0.299 * leftPixel.r +
                0.587 * leftPixel.g +
                0.114 * leftPixel.b;
            final rightLum = 0.299 * rightPixel.r +
                0.587 * rightPixel.g +
                0.114 * rightPixel.b;
            if (leftLum > rightLum) {
              hash |= (1 << bit);
            }
            bit++;
          }
        }
        return hash;
      });
    } catch (_) {
      return null;
    }
  }

  static int _hammingDistance(int a, int b) {
    int xor = a ^ b;
    int count = 0;
    while (xor != 0) {
      count += xor & 1;
      xor = xor >>> 1;
    }
    return count;
  }
}

enum ImageEnhancement { none, grayscale, highContrast, magicColor }
