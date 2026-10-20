import 'dart:convert';
import 'dart:io';

import 'package:china_map/data/geojson_parser.dart';
import 'package:china_map/models/city.dart';
import 'package:china_map/models/map_region.dart';
import 'package:china_map/widgets/map_painter.dart';
import 'package:china_map/utils/map_projection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

City city(String code, double longitude, {bool capital = false}) => City(
  code: code,
  name: '城市$code',
  province: '测试省',
  provinceCode: 'test',
  longitude: longitude,
  latitude: 30,
  isCapital: capital,
  capitalKind: '省会',
);

void expectClear(List<MapLabel> labels, Rect view) {
  for (var i = 0; i < labels.length; i++) {
    expect(view.contains(labels[i].bounds.topLeft), isTrue);
    expect(view.contains(labels[i].bounds.bottomRight), isTrue);
    for (var j = i + 1; j < labels.length; j++) {
      expect(labels[i].bounds.overlaps(labels[j].bounds), isFalse);
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('全国只标省会，市县标签随层级出现', () {
    final capital = city('A', 105, capital: true);
    final prefecture = city('B', 106);
    final center = capital.point.translate(0, 20);
    final county = MapRegion(
      code: 'C',
      name: '测试县',
      level: 'district',
      hasChildren: false,
      path: Path()
        ..addRect(Rect.fromCenter(center: center, width: 50, height: 50)),
      label: center,
    );
    final view = Rect.fromCenter(center: capital.point, width: 60, height: 50);
    List<MapLabel> labels(bool cities, bool districts) => MapPainter(
      regions: [county],
      provinces: [],
      scale: 20,
      view: view,
      cities: [capital, prefecture],
      showCities: cities,
      showDistricts: districts,
    ).layoutLabels();
    expect(labels(false, false).map((label) => label.code), ['A']);
    expect(labels(true, false).map((label) => label.code), ['A', 'B']);
    expect(labels(true, true).map((label) => label.code), ['A', 'B', 'C']);
  });

  test('密集城市中保留两个起终点，隐藏冲突的低优先级标签', () {
    final origin = city('Y', 110);
    final destination = city('Z', 110.01);
    final cities = [
      for (var i = 0; i < 20; i++) city('$i', 110 + i * 0.001, capital: true),
      origin,
      destination,
    ];
    final view = Rect.fromCenter(center: origin.point, width: 320, height: 240);
    final labels = MapPainter(
      regions: [],
      provinces: [],
      scale: 1,
      view: view,
      cities: cities,
      origin: origin,
      destination: destination,
    ).layoutLabels();
    expect(labels.take(2).map((label) => label.code), ['Y', 'Z']);
    expect(labels.length, lessThan(cities.length));
    expectClear(labels, view);
  });

  test('贴近视口边缘的选中标签完整显示', () {
    final selected = city('selected', 110);
    final view = Rect.fromLTWH(
      selected.point.dx - 1,
      selected.point.dy - 1,
      240,
      180,
    );
    final labels = MapPainter(
      regions: [],
      provinces: [],
      scale: 1,
      view: view,
      cities: [selected],
      destination: selected,
    ).layoutLabels();
    expect(labels, hasLength(1));
    expectClear(labels, view);
  });
  test('聚焦省份的城市全部标注，邻省城市淡化且受密度预算约束', () {
    final cities = readList(
      jsonDecode(File('assets/cities/catalog.json').readAsStringSync()),
    ).map((raw) => City.fromJson(readObject(raw))).toList();
    MapPainter at(double span) => MapPainter(
      regions: [],
      provinces: [],
      cities: cities,
      scale: 610 / span,
      showCities: true,
      detailProvinces: const {'410000'},
      view: Rect.fromCenter(
        center: project(115, 34),
        width: span * 373 / 610,
        height: span,
      ),
    );
    expect(
      at(359).layoutLabels().where((label) => label.priority >= 2),
      isEmpty,
    );
    final detail = at(200);
    final labels = detail.layoutLabels();
    expectClear(labels, detail.view);
    final henan = labels.where((l) => l.priority == 2 && !l.muted).toList();
    final muted = labels.where((l) => l.muted).toList();
    expect(henan, isNotEmpty);
    expect(henan.every((l) => l.code.startsWith('41')), isTrue);
    expect(muted.every((l) => !l.code.startsWith('41')), isTrue);
    expect(muted.length, lessThanOrEqualTo(373 * 610 ~/ 9000));
    expect(muted.every((l) => l.fontSize < 10), isTrue);
    // 标签透明度只随层级渐显，同一时刻的聚焦省份城市透明度一致（无残影）。
    expect(henan.map((l) => l.opacity).toSet(), hasLength(1));
    expect(detail.cityOpacity, inExclusiveRange(0, 1));
    expect(at(180).cityOpacity, 1);
  });

  test('杭州区县也渐显且保留起终点，不与上级标签挤在一起', () {
    final cities = readList(
      jsonDecode(File('assets/cities/catalog.json').readAsStringSync()),
    ).map((raw) => City.fromJson(readObject(raw))).toList();
    final hangzhou = cities.firstWhere((city) => city.name == '杭州');
    final counties = parseRegions(
      File('assets/maps/330100.json').readAsStringSync(),
    );
    MapPainter at(double span) => MapPainter(
      regions: counties,
      provinces: [],
      cities: cities,
      destination: hangzhou,
      scale: 610 / span,
      showCities: true,
      showDistricts: true,
      view: Rect.fromCenter(
        center: hangzhou.point,
        width: span * 373 / 610,
        height: span,
      ),
    );
    expect(
      at(99).layoutLabels().where((label) => label.priority == 3),
      isEmpty,
    );
    final detail = at(50);
    final labels = detail.layoutLabels();
    expect(labels.first.code, hangzhou.code);
    expect(labels.first.opacity, 1);
    expect(labels.where((label) => label.priority == 3), isNotEmpty);
    expect(labels.length, lessThanOrEqualTo(23));
    expectClear(labels, detail.view);
  });
}
