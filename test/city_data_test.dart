import 'dart:convert';
import 'dart:io';

import 'package:china_map/models/city.dart';
import 'package:china_map/models/city_profile.dart';
import 'package:china_map/utils/travel_estimate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final cities = readList(
    jsonDecode(File('assets/cities/catalog.json').readAsStringSync()),
  ).map((raw) => City.fromJson(readObject(raw))).toList();
  City named(String name) => cities.firstWhere((c) => c.name == name);

  test('省会、首府和直辖市覆盖全部省级区域，坐标有效', () {
    final capitals = cities.where((city) => city.isCapital);
    expect(capitals, hasLength(34));
    expect(capitals.map((city) => city.provinceCode).toSet(), hasLength(34));
    expect(named('石家庄').isCapital, isTrue);
    expect(named('呼和浩特').capitalKind, '首府');
    expect(named('北京').capitalKind, '直辖市');
    expect(named('深圳').isCapital, isFalse);
    expect(cities.map((city) => city.code).toSet(), hasLength(cities.length));
  });

  test('六城统计与五十城租赁数据均有来源、时间和完整口径', () {
    final profiles = readList(
      jsonDecode(File('assets/cities/profiles.json').readAsStringSync()),
    ).map((raw) => CityProfile.fromJson(readObject(raw))).toList();
    expect(profiles, hasLength(6));
    for (final profile in profiles) {
      expect(cities.any((city) => city.code == profile.code), isTrue);
      expect(profile.annualConsumption, greaterThan(0));
      expect(profile.sources, isNotEmpty);
    }
    final rents = readObject(
      jsonDecode(File('assets/cities/rents.json').readAsStringSync()),
    );
    expect(rents['period'], '2026-09');
    expect(readList(rents['cities']), hasLength(50));
    for (final raw in readList(rents['cities'])) {
      final row = readObject(raw);
      expect(cities.any((city) => city.name == row['name']), isTrue);
      expect(readNumber(row, 'average'), greaterThan(0));
    }
  });

  test('城市距离对称、估算区间有序，普铁预估耗时更长', () {
    final first = named('北京');
    final second = named('上海');
    final estimate = TravelEstimate(first, second);
    expect(estimate.straightKm, inInclusiveRange(1000, 1150));
    expect(
      distanceKm(first, second),
      closeTo(distanceKm(second, first), 0.001),
    );
    expect(estimate.unavailableReason, isNull);
    final highSpeed = estimate.hours(highSpeed: true);
    final train = estimate.hours(highSpeed: false);
    expect(highSpeed.$2, greaterThan(highSpeed.$1));
    expect(train.$1, greaterThan(highSpeed.$1));
    expect(train.$2, greaterThan(highSpeed.$2));
  });

  test('同城、跨海及未验证特殊区域不会伪造铁路耗时', () {
    for (final pair in [
      ('北京', '北京'),
      ('上海', '台北'),
      ('广州', '海口'),
      ('广州', '澳门'),
    ]) {
      final estimate = TravelEstimate(named(pair.$1), named(pair.$2));
      expect(estimate.unavailableReason, isNotNull);
      expect(() => estimate.hours(highSpeed: true), throwsStateError);
    }
  });
}
