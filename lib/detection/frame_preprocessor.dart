import 'dart:typed_data';

enum RawFormat { yuv420, nv21, bgra8888 }

class RawPlane {
  const RawPlane(this.bytes, this.bytesPerRow, this.bytesPerPixel);

  final Uint8List bytes;
  final int bytesPerRow;
  final int bytesPerPixel;
}

/// A camera frame decoupled from the `camera` plugin so the conversion logic
/// can be unit-tested without a device.
class RawFrame {
  const RawFrame(this.width, this.height, this.format, this.planes);

  final int width;
  final int height;
  final RawFormat format;
  final List<RawPlane> planes;
}

/// Describes how the model input square relates to the upright camera image,
/// so model output (normalized to the square) can be mapped back.
class Letterbox {
  const Letterbox(this.uprightWidth, this.uprightHeight);

  final int uprightWidth;
  final int uprightHeight;

  int get side => uprightWidth > uprightHeight ? uprightWidth : uprightHeight;
  double get padX => (side - uprightWidth) / 2;
  double get padY => (side - uprightHeight) / 2;
  double get aspect => uprightWidth / uprightHeight;

  /// Normalized square coords -> normalized upright-image coords.
  (double, double) toImage(double xs, double ys) => ((xs * side - padX) / uprightWidth, (ys * side - padY) / uprightHeight);
}

/// Rotates the raw frame clockwise by [rotation] degrees (0/90/180/270) to be
/// upright, letterboxes it into a [size]x[size] RGB buffer (black padding) and
/// writes it to [out] (length size*size*3). Nearest-neighbour sampling.
Letterbox preprocessFrame(RawFrame f, int rotation, int size, Uint8List out) {
  assert(out.length == size * size * 3);
  final w = f.width, h = f.height;
  final swap = rotation == 90 || rotation == 270;
  final lb = Letterbox(swap ? h : w, swap ? w : h);
  final uw = lb.uprightWidth, uh = lb.uprightHeight;
  final scale = size / lb.side;
  final padX = lb.padX, padY = lb.padY;
  final p = f.planes;

  var o = 0;
  for (var oy = 0; oy < size; oy++) {
    final uy = (oy + 0.5) / scale - padY;
    for (var ox = 0; ox < size; ox++, o += 3) {
      final ux = (ox + 0.5) / scale - padX;
      if (ux < 0 || uy < 0 || ux >= uw || uy >= uh) {
        out[o] = out[o + 1] = out[o + 2] = 0;
        continue;
      }
      double sxf, syf;
      switch (rotation) {
        case 90:
          sxf = uy;
          syf = h - ux;
        case 180:
          sxf = w - ux;
          syf = h - uy;
        case 270:
          sxf = w - uy;
          syf = ux;
        default:
          sxf = ux;
          syf = uy;
      }
      final sx = sxf.floor().clamp(0, w - 1), sy = syf.floor().clamp(0, h - 1);

      switch (f.format) {
        case RawFormat.bgra8888:
          final i = sy * p[0].bytesPerRow + sx * 4;
          out[o] = p[0].bytes[i + 2];
          out[o + 1] = p[0].bytes[i + 1];
          out[o + 2] = p[0].bytes[i];
        case RawFormat.yuv420:
          final y = p[0].bytes[sy * p[0].bytesPerRow + sx * p[0].bytesPerPixel];
          final u = p[1].bytes[(sy >> 1) * p[1].bytesPerRow + (sx >> 1) * p[1].bytesPerPixel];
          final v = p[2].bytes[(sy >> 1) * p[2].bytesPerRow + (sx >> 1) * p[2].bytesPerPixel];
          _yuv(y, u, v, out, o);
        case RawFormat.nv21:
          final rs = p[0].bytesPerRow;
          final y = p[0].bytes[sy * rs + sx];
          final c = rs * h + (sy >> 1) * rs + (sx >> 1) * 2;
          _yuv(y, p[0].bytes[c + 1], p[0].bytes[c], out, o);
      }
    }
  }
  return lb;
}

void _yuv(int y, int u, int v, Uint8List out, int o) {
  final d = u - 128, e = v - 128;
  out[o] = (y + 1.402 * e).round().clamp(0, 255);
  out[o + 1] = (y - 0.344136 * d - 0.714136 * e).round().clamp(0, 255);
  out[o + 2] = (y + 1.772 * d).round().clamp(0, 255);
}
