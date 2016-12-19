import 'dart:math';
import 'package:dart2d/phys/vec2.dart';
import 'package:dart2d/res/imageindex.dart';
import 'package:dart2d/bindings/annotations.dart';
import 'package:di/di.dart';

@Injectable()
class ByteWorld {
  int width;
  int height;
  Vec2 viewSize;
  var canvas;

  ByteWorld(var image, Vec2 viewSize, @CanvasFactory() DynamicFactory canvasFactory) {
    canvas = canvasFactory.create([image.width, image.height]);
    this.width = canvas.width;
    this.height = canvas.height;
    canvas.context2D.drawImageScaled(image, 0, 0, width, height);
    this.viewSize = viewSize;
  }
  
  ByteWorld.fromCanvas(var canvas, Vec2 viewSize) {
    this.canvas = canvas;
    this.width = canvas.width;
    this.height = canvas.height;
    this.viewSize = viewSize;
  }
  
  void drawAt(var canvas, x, y) {
    canvas.drawImageScaledFromSource(
       this.canvas,
       x, y, // Source
       viewSize.x, viewSize.y, // width.
       0, 0, viewSize.x , viewSize.y);
  }
  
  void drawAsMiniMap(var canvas, x, y, [width = 100, height = 100]) {
    canvas.drawImageScaledFromSource(
       this.canvas,
       0, 0, // Source
       this.width, this.height, // width.
       x, y, width , height);
  }
  
  bool isCanvasCollide(num x, num y, [num width = 1, num height = 1]) {
    List<int> data = canvas.context2D.getImageData(x, y, width, height).data;
    for (int i = 0; i < data.length / 4; i++) {
      if (data[i*4 + 3] > 0) {
        return true;
      }
    }
    return  false;
  }
  
  clearAtRect(int x, int y, int width, int height) {
    canvas.context2D.clearRect(x, y, width, height);
  }
  
  String asDataUrl() {
    return canvas.toDataUrl();
  }
  
  clearAt(Vec2 pos, double radius) {
    canvas.context2D
        ..save()
        ..beginPath()
        ..arc(pos.x, pos.y, radius, 0, 2 * PI, false)
        ..clip()
        ..clearRect(pos.x - radius - 1, pos.y - radius - 1,
                        radius * 2 + 2, radius * 2 + 2)
        ..restore();
  }
}