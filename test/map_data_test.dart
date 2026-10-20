import 'dart:io';

import 'package:china_map/data/geojson_parser.dart';
import 'package:china_map/models/map_region.dart';
import 'package:flutter_test/flutter_test.dart';

List<MapRegion> load(String code) =>
    parseRegions(File('assets/maps/$code.json').readAsStringSync());

void main() {
  test('34 个省级区域都有真实边界，所有声明的下级资源完整', () {
    final provinces = load('100000');
    expect(provinces.where((r) => r.level == 'province'), hasLength(34));
    final seen = <String>{};
    void visit(String code) {
      expect(seen.add(code), isTrue, reason: '行政层级出现循环: $code');
      for (final region in load(code)) {
        expect(region.bounds.isEmpty, isFalse, reason: region.name);
        expect(region.bounds.isFinite, isTrue);
        if (region.hasChildren) {
          visit(region.code);
        }
      }
    }

    visit('100000');
    expect(seen.length, greaterThan(380));
  });

  test('浙江 → 杭州 → 西湖，直辖市及台湾补充层级存在', () {
    expect(load('100000').any((r) => r.name == '浙江省'), isTrue);
    expect(load('330000').any((r) => r.name == '杭州市'), isTrue);
    expect(load('330100').any((r) => r.name == '西湖区'), isTrue);
    expect(load('110000').any((r) => r.name == '东城区'), isTrue);
    expect(load('710000'), hasLength(22));
    final taipei = load('710000')
        .firstWhere((r) => r.name == '台北市' || r.name == '臺北市');
    expect(load(taipei.code).length, 12);
  });

  test('损坏的数据明确报错', () {
    expect(() => parseRegions('{"type":"Feature"}'), throwsFormatException);
  });
}
