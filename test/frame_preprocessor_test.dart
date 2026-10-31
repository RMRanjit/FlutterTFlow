import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:movement_poc/detection/frame_preprocessor.dart';

/// 4x2 BGRA frame, all black except a red marker at raw (0,0) (top-left).
RawFrame markerFrame() {
  final b = Uint8List(4 * 2 * 4);
  for (var i = 3; i < b.length; i += 4) {
    b[i] = 255;
  }
  b[2] = 255; // red channel of pixel (0,0) in BGRA
  return RawFrame(4, 2, RawFormat.bgra8888, [RawPlane(b, 16, 4)]);
}

/// Returns the (x,y) of the single red pixel in a 4x4 RGB output.
(int, int) redPixel(Uint8List out, {int size = 4}) {
  final hits = <(int, int)>[];
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final i = (y * size + x) * 3;
      if (out[i] > 200 && out[i + 1] < 50 && out[i + 2] < 50) hits.add((x, y));
    }
  }
  expect(hits.length, 1, reason: 'expected exactly one red pixel, got $hits');
  return hits.single;
}

void main() {
  test('rotation 0 letterboxes a landscape frame with vertical padding', () {
    final out = Uint8List(4 * 4 * 3);
    final lb = preprocessFrame(markerFrame(), 0, 4, out);
    expect((lb.uprightWidth, lb.uprightHeight), (4, 2));
    expect(redPixel(out), (0, 1));
    // Padding rows (0 and 3) are black.
    expect(out.sublist(0, 12).every((v) => v == 0), isTrue);
    expect(out.sublist(36, 48).every((v) => v == 0), isTrue);
  });

  test('rotation 90 moves raw top-left to upright top-right', () {
    final out = Uint8List(48);
    final lb = preprocessFrame(markerFrame(), 90, 4, out);
    expect((lb.uprightWidth, lb.uprightHeight), (2, 4));
    expect(redPixel(out), (2, 0));
  });

  test('rotation 180 and 270 place the marker correctly', () {
    var out = Uint8List(48);
    preprocessFrame(markerFrame(), 180, 4, out);
    expect(redPixel(out), (3, 2));
    out = Uint8List(48);
    preprocessFrame(markerFrame(), 270, 4, out);
    expect(redPixel(out), (1, 3));
  });

  test('letterbox maps model coords back to the upright image', () {
    const lb = Letterbox(2, 4); // portrait: pad left/right by 1 px each
    expect(lb.toImage(0.5, 0.5), (0.5, 0.5));
    expect(lb.toImage(0.25, 0.0), (0.0, 0.0)); // left edge of image
    expect(lb.toImage(0.75, 1.0), (1.0, 1.0));
    expect(lb.aspect, 0.5);
  });

  test('converts YUV420 and NV21 grey/colour correctly', () {
    // 2x2 frame, mid-grey (Y=128, U=V=128) => ~ (128,128,128)
    final y = Uint8List.fromList([128, 128, 128, 128]);
    final u = Uint8List.fromList([128]);
    final v = Uint8List.fromList([128]);
    var out = Uint8List(2 * 2 * 3);
    preprocessFrame(RawFrame(2, 2, RawFormat.yuv420, [RawPlane(y, 2, 1), RawPlane(u, 1, 1), RawPlane(v, 1, 1)]), 0, 2, out);
    expect(out.every((c) => (c - 128).abs() <= 1), isTrue);

    // Strongly red: Y=76 U=85 V=255 (BT.601) => red channel high.
    final nv21 = Uint8List.fromList([76, 76, 76, 76, 255, 85]); // Y*4 then V,U
    out = Uint8List(12);
    preprocessFrame(RawFrame(2, 2, RawFormat.nv21, [RawPlane(nv21, 2, 1)]), 0, 2, out);
    expect(out[0], greaterThan(220));
    expect(out[1], lessThan(40));
    expect(out[2], lessThan(40));
  });
}
