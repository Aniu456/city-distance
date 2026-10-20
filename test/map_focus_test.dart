import 'package:china_map/animations/map_camera.dart';
import 'package:china_map/utils/map_focus.dart';
import 'package:flutter_test/flutter_test.dart';

const _parents = {
  '610000': '100000',
  '620000': '100000',
  '610100': '610000',
  '610300': '610000',
  '610102': '610100',
  '610302': '610300',
};

String? parentOf(String code) => _parents[code];

void main() {
  test('聚焦西安只展开陕西和西安内部，其余省市保持粗粒度', () {
    const focus = MapFocus(['610000', '610100']);
    expect(focus.includes('610000', parentOf), isTrue);
    expect(focus.includes('610100', parentOf), isTrue);
    expect(focus.includes('610102', parentOf), isTrue);
    expect(focus.includes('610300', parentOf), isFalse);
    expect(focus.includes('610302', parentOf), isFalse);
    expect(focus.includes('620000', parentOf), isFalse);
    expect(focus.provinceCode, '610000');
  });

  test('聚焦省份时省内所有城市都可下钻', () {
    const focus = MapFocus(['610000']);
    expect(focus.includes('610300', parentOf), isTrue);
    expect(focus.includes('610302', parentOf), isTrue);
    expect(focus.includes('620000', parentOf), isFalse);
  });

  test('按钮放大逐步移向聚焦区域，缩小逐步回到全国中心', () {
    const national = Offset(600, 600);
    const focus = Offset(400, 500);
    Offset center(double scale, {required bool zoomingIn, Offset? current}) =>
        focusZoomCenter(
          current: current ?? national,
          focus: focus,
          national: national,
          scale: scale,
          fitScale: 1,
          focusScale: 16,
          zoomingIn: zoomingIn,
        );
    expect(center(1, zoomingIn: true), national);
    expect(center(4, zoomingIn: true), const Offset(500, 550));
    expect(center(16, zoomingIn: true), focus);
    expect(center(32, zoomingIn: true), focus);
    expect(center(16, zoomingIn: false, current: focus), focus);
    expect(center(4, zoomingIn: false, current: focus), const Offset(500, 550));
    expect(center(1, zoomingIn: false, current: focus), national);
  });

  test('相机插值按对数缩放，中点为几何平均', () {
    final camera = lerpMapCamera(
      (center: Offset.zero, scale: 1),
      (center: const Offset(100, 50), scale: 16),
      0.5,
    );
    expect(camera.center, const Offset(50, 25));
    expect(camera.scale, closeTo(4, 1e-9));
  });
}
