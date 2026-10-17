// Generates the Mix tile evidence fixtures with the canonical `image`
// package encoder (tool-only; not part of the app).
import 'dart:io';
import 'package:image/image.dart' as img;

void product(String path, int w, int h, img.Color Function(int x, int y) f) {
  final im = img.Image(width: w, height: h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      im.setPixel(x, y, f(x, y));
    }
  }
  File(path).writeAsBytesSync(img.encodePng(im));
}

void main() {
  // Jollof stand-in: warm gradient, plate, mound.
  product('test/fixtures/mix_evidence/product.png', 512, 512, (x, y) {
    final t = y / 512;
    var r = (90 + 130 * t).toInt(), g = (45 + 60 * t).toInt(), b = (20 + 40 * (1 - t)).toInt();
    final dx = x - 256, dy = y - 300;
    if (dx * dx + dy * dy < 90 * 90) { r = 245; g = 235; b = 220; }
    if (dx * dx + dy * dy < 45 * 45) { r = 200; g = 90; b = 30; }
    return img.ColorRgb8(r, g, b);
  });
  // Kenkey stand-in: green weave.
  product('test/fixtures/mix_evidence/product2.png', 512, 512, (x, y) {
    final t = x / 512;
    var r = (20 + 40 * t).toInt(), g = (110 + 70 * t).toInt(), b = (60 + 30 * t).toInt();
    if ((x ~/ 32 + y ~/ 32) % 2 == 0) { r ~/= 2; g ~/= 2; b ~/= 2; }
    return img.ColorRgb8(r, g, b);
  });
  // Store logo: yellow disc on indigo.
  product('test/fixtures/mix_evidence/logo.png', 128, 128, (x, y) {
    final dx = x - 64, dy = y - 64, d2 = dx * dx + dy * dy;
    if (d2 < 40 * 40) return img.ColorRgb8(255, 204, 10);
    if (d2 < 48 * 48) return img.ColorRgb8(30, 24, 90);
    return img.ColorRgb8(250, 250, 250);
  });
  print('fixtures written');
}
