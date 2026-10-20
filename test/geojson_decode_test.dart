import 'dart:io';

import 'package:china_map/data/geojson_parser.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('后台 isolate 解码与当前线程解析结果完全一致', () async {
    final source = File('assets/maps/430000.json').readAsStringSync();
    final direct = parseRegions(source);
    final shapes = await compute(decodeRegions, source);
    final built = buildRegions(shapes);
    expect(built.length, direct.length);
    for (final (index, region) in built.indexed) {
      final expected = direct[index];
      expect(region.code, expected.code);
      expect(region.name, expected.name);
      expect(region.level, expected.level);
      expect(region.hasChildren, expected.hasChildren);
      expect(region.label, expected.label);
      expect(region.bounds, expected.bounds);
    }
  });
}
