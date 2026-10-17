// Tool-only: samples the evidence captures for the fixture images'
// signature colors, proving real bytes rendered (not placeholders).
import 'dart:io';
import 'package:image/image.dart' as img;

void main() {
  for (final n in [
    '320_light', '320_dark', '360_light', '360_dark', '390_light', '390_dark'
  ]) {
    final im =
        img.decodePng(File('.screenshots/mix_tiles_$n.png').readAsBytesSync())!;
    var yellow = 0; // logo disc (255,204,10)
    var mound = 0; // jollof mound (200,90,30)
    var plate = 0; // plate (245,235,220)
    var weave = 0; // kenkey weave (g > r + 40)
    for (final px in im) {
      final r = px.r.toInt(), g = px.g.toInt(), b = px.b.toInt();
      if ((r - 255).abs() <= 12 && (g - 204).abs() <= 12 && (b - 10).abs() <= 12) yellow++;
      if ((r - 200).abs() <= 14 && (g - 90).abs() <= 14 && (b - 30).abs() <= 14) mound++;
      if ((r - 245).abs() <= 10 && (g - 235).abs() <= 10 && (b - 220).abs() <= 10) plate++;
      if (r >= 15 && r <= 65 && g >= 100 && g <= 190 && b >= 50 && b <= 100 && g > r + 40) weave++;
    }
    print('$n: logo-disc=$yellow jollof-mound=$mound plate=$plate weave=$weave');
  }
}
