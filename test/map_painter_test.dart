import 'dart:ui';

import 'package:china_map/widgets/map_painter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('市级区域按上级关系判断所属省份，台湾编码也能识别', () {
    String? parentOf(String code) =>
        code.startsWith('tw_') ? '710000' : '${code.substring(0, 2)}0000';
    MapPainter painter(Set<String> provinces) => MapPainter(
      regions: const [],
      provinces: const [],
      scale: 1,
      view: Rect.zero,
      detailProvinces: provinces,
      parentOf: parentOf,
    );
    expect(painter({'710000'}).isDetailedRegion('tw_10014'), isTrue);
    expect(painter({'630000'}).isDetailedRegion('tw_10014'), isFalse);
    expect(painter({'360000'}).isDetailedRegion('360100'), isTrue);
    expect(painter({'430000'}).isDetailedRegion('360100'), isFalse);
  });
}
