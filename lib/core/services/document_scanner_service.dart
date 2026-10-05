import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Normalized corner point (0.0–1.0 relative to image dimensions).
class CornerPoint {
  final double x;
  final double y;
  const CornerPoint(this.x, this.y);

  @override
  String toString() => 'CornerPoint($x, $y)';
}

/// Pure Dart/image-package document scanner service.
/// No ML Kit dependency — all processing done with the `image` package.
class DocumentScannerService {
  DocumentScannerService._();
  static final DocumentScannerService instance = DocumentScannerService._();

  // ── Perspective Correction ─────────────────────────────────────────────────

  /// Applies perspective correction using 4 corner points (normalized 0–1).
  ///
  /// [corners] must be ordered: topLeft, topRight, bottomRight, bottomLeft.
  /// Returns the path of the perspective-corrected image.
  Future<String> perspectiveCrop(
    String imagePath, {
    required List<CornerPoint> corners,
  }) async {
    try {
      final result = await Isolate.run(() async {
        final bytes = await File(imagePath).readAsBytes();
        final source = img.decodeImage(bytes);
        if (source == null) return null;

        final srcW = source.width.toDouble();
        final srcH = source.height.toDouble();

        // Convert normalized corners to pixel coordinates
        final tl = _Pt(corners[0].x * srcW, corners[0].y * srcH);
        final tr = _Pt(corners[1].x * srcW, corners[1].y * srcH);
        final br = _Pt(corners[2].x * srcW, corners[2].y * srcH);
        final bl = _Pt(corners[3].x * srcW, corners[3].y * srcH);

        // Compute output dimensions (max of the two sides)
        final widthTop = _dist(tl, tr);
        final widthBot = _dist(bl, br);
        final outW = math.max(widthTop, widthBot).round();

        final heightLeft = _dist(tl, bl);
        final heightRight = _dist(tr, br);
        final outH = math.max(heightLeft, heightRight).round();

        if (outW <= 0 || outH <= 0) return null;

        // Compute the perspective transform matrix (3x3 homography)
        final dst = [
          _Pt(0, 0),
          _Pt(outW.toDouble(), 0),
          _Pt(outW.toDouble(), outH.toDouble()),
          _Pt(0, outH.toDouble()),
        ];
        final H = _computeHomography([tl, tr, br, bl], dst);
        final Hinv = _invertMatrix3x3(H);

        if (Hinv == null) return null;

        // Warp by inverse mapping (for each dest pixel, find source pixel)
        final output = img.Image(width: outW, height: outH);

        for (int dy = 0; dy < outH; dy++) {
          for (int dx = 0; dx < outW; dx++) {
            // Apply inverse homography
            final hw = Hinv[6] * dx + Hinv[7] * dy + Hinv[8];
            if (hw.abs() < 1e-10) continue;
            final sx = (Hinv[0] * dx + Hinv[1] * dy + Hinv[2]) / hw;
            final sy = (Hinv[3] * dx + Hinv[4] * dy + Hinv[5]) / hw;

            // Bilinear interpolation
            final pixel = _bilinearSample(source, sx, sy);
            output.setPixel(dx, dy, pixel);
          }
        }

        return img.encodeJpg(output, quality: 92);
      });

      if (result == null) return imagePath;

      final docs = await getApplicationDocumentsDirectory();
      final outPath = p.join(
        docs.path,
        'SmartLectureScanner',
        'session',
        'perspective_${p.basename(imagePath)}',
      );
      await File(outPath).parent.create(recursive: true);
      await File(outPath).writeAsBytes(result);
      return outPath;
    } catch (e) {
      debugPrint('DocumentScannerService.perspectiveCrop error: $e');
      return imagePath;
    }
  }

  /// Simple rectangular crop using normalized LTRB coordinates.
  Future<String> manualCrop(
    String imagePath, {
    required double left,
    required double top,
    required double right,
    required double bottom,
  }) async {
    try {
      final result = await Isolate.run(() async {
        final bytes = await File(imagePath).readAsBytes();
        final decoded = img.decodeImage(bytes);
        if (decoded == null) return null;

        final x = (left * decoded.width).toInt().clamp(0, decoded.width - 1);
        final y = (top * decoded.height).toInt().clamp(0, decoded.height - 1);
        final w = ((right - left) * decoded.width)
            .toInt()
            .clamp(1, decoded.width - x);
        final h = ((bottom - top) * decoded.height)
            .toInt()
            .clamp(1, decoded.height - y);

        final cropped = img.copyCrop(decoded, x: x, y: y, width: w, height: h);
        return img.encodeJpg(cropped, quality: 92);
      });

      if (result == null) return imagePath;

      final docs = await getApplicationDocumentsDirectory();
      final outPath = p.join(
        docs.path,
        'SmartLectureScanner',
        'session',
        'cropped_${p.basename(imagePath)}',
      );
      await File(outPath).parent.create(recursive: true);
      await File(outPath).writeAsBytes(result);
      return outPath;
    } catch (e) {
      debugPrint('DocumentScannerService.manualCrop error: $e');
      return imagePath;
    }
  }

  /// Crops only the ROI from a full-frame image using normalized LTRB.
  Future<String> cropToRoi(
    String imagePath, {
    required double left,
    required double top,
    required double right,
    required double bottom,
  }) async {
    return manualCrop(
      imagePath,
      left: left,
      top: top,
      right: right,
      bottom: bottom,
    );
  }
}

// ── Internal math helpers (run inside isolate) ─────────────────────────────

class _Pt {
  final double x, y;
  const _Pt(this.x, this.y);
}

double _dist(_Pt a, _Pt b) {
  final dx = a.x - b.x;
  final dy = a.y - b.y;
  return math.sqrt(dx * dx + dy * dy);
}

img.Pixel _bilinearSample(img.Image src, double sx, double sy) {
  final x0 = sx.floor().clamp(0, src.width - 1);
  final y0 = sy.floor().clamp(0, src.height - 1);
  final x1 = (x0 + 1).clamp(0, src.width - 1);
  final y1 = (y0 + 1).clamp(0, src.height - 1);

  final tx = sx - x0;
  final ty = sy - y0;

  final p00 = src.getPixel(x0, y0);
  final p10 = src.getPixel(x1, y0);
  final p01 = src.getPixel(x0, y1);
  final p11 = src.getPixel(x1, y1);

  double lerp(double a, double b, double t) => a + (b - a) * t;

  final r = lerp(lerp(p00.r.toDouble(), p10.r.toDouble(), tx),
      lerp(p01.r.toDouble(), p11.r.toDouble(), tx), ty);
  final g = lerp(lerp(p00.g.toDouble(), p10.g.toDouble(), tx),
      lerp(p01.g.toDouble(), p11.g.toDouble(), tx), ty);
  final b = lerp(lerp(p00.b.toDouble(), p10.b.toDouble(), tx),
      lerp(p01.b.toDouble(), p11.b.toDouble(), tx), ty);

  // Use a fresh image pixel copy
  final out = img.Image(width: 1, height: 1);
  out.setPixelRgba(0, 0, r.round(), g.round(), b.round(), 255);
  return out.getPixel(0, 0);
}

/// Computes a 3x3 homography matrix mapping [src] points to [dst] points.
/// Returns a flat 9-element list (row-major).
List<double> _computeHomography(List<_Pt> src, List<_Pt> dst) {
  // DLT algorithm — 8x9 matrix
  final A = List.generate(8, (_) => List<double>.filled(9, 0));

  for (int i = 0; i < 4; i++) {
    final sx = src[i].x, sy = src[i].y;
    final dx = dst[i].x, dy = dst[i].y;

    A[2 * i] = [-sx, -sy, -1, 0, 0, 0, dx * sx, dx * sy, dx];
    A[2 * i + 1] = [0, 0, 0, -sx, -sy, -1, dy * sx, dy * sy, dy];
  }

  // Solve using SVD approximation via Gaussian elimination on A^T * A
  // For 4-point correspondence we can use direct solution
  final h = _solveDLT(A);
  return h;
}

List<double> _solveDLT(List<List<double>> A) {
  // Simple numerical solution for homography via LU/Gauss-Jordan on A^T*A
  // (8 equations, 9 unknowns — fix h[8] = 1)
  // Build 8x8 system after fixing h8=1
  final n = 8;
  final mat = List.generate(n, (i) {
    final row = List<double>.filled(n + 1, 0);
    for (int j = 0; j < n; j++) {
      row[j] = A[i][j];
    }
    row[n] = -A[i][8]; // move h8 to RHS
    return row;
  });

  // Gauss-Jordan elimination
  for (int col = 0; col < n; col++) {
    // Find pivot
    int pivot = col;
    double maxVal = mat[col][col].abs();
    for (int row = col + 1; row < n; row++) {
      if (mat[row][col].abs() > maxVal) {
        maxVal = mat[row][col].abs();
        pivot = row;
      }
    }
    final tmp = mat[col];
    mat[col] = mat[pivot];
    mat[pivot] = tmp;

    if (mat[col][col].abs() < 1e-10) continue;

    final scale = mat[col][col];
    for (int j = col; j <= n; j++) {
      mat[col][j] /= scale;
    }

    for (int row = 0; row < n; row++) {
      if (row == col) continue;
      final factor = mat[row][col];
      for (int j = col; j <= n; j++) {
        mat[row][j] -= factor * mat[col][j];
      }
    }
  }

  final h = List<double>.filled(9, 0);
  for (int i = 0; i < n; i++) {
    h[i] = mat[i][n];
  }
  h[8] = 1.0;
  return h;
}

List<double>? _invertMatrix3x3(List<double> m) {
  final a = m[0], b = m[1], c = m[2];
  final d = m[3], e = m[4], f = m[5];
  final g = m[6], h = m[7], i = m[8];

  final det = a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g);
  if (det.abs() < 1e-10) return null;

  final inv = 1.0 / det;
  return [
    (e * i - f * h) * inv,
    (c * h - b * i) * inv,
    (b * f - c * e) * inv,
    (f * g - d * i) * inv,
    (a * i - c * g) * inv,
    (c * d - a * f) * inv,
    (d * h - e * g) * inv,
    (b * g - a * h) * inv,
    (a * e - b * d) * inv,
  ];
}
