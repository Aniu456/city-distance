import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/city.dart';
import '../models/city_profile.dart';

class CityRepository {
  CityRepository({AssetBundle? bundle}) : _bundle = bundle ?? rootBundle;
  final AssetBundle _bundle;
  List<City> cities = [];
  Map<String, CityProfile> profiles = {};
  Map<String, RentReference> rents = {};

  Future<void> load() async {
    const keys = [
      'assets/cities/catalog.json',
      'assets/cities/profiles.json',
      'assets/cities/rents.json',
    ];
    final List<String> strings;
    try {
      strings = await Future.wait([
        for (final key in keys) _bundle.loadString(key),
      ]);
    } catch (_) {
      // 资源包会缓存失败的读取，清除后重试才会真正重新读取。
      keys.forEach(_bundle.evict);
      rethrow;
    }
    final loadedCities = readList(jsonDecode(strings[0]))
        .map((value) => City.fromJson(readObject(value)))
        .toList(growable: false);
    final loadedProfiles = readList(jsonDecode(strings[1]))
        .map((value) => CityProfile.fromJson(readObject(value)))
        .toList(growable: false);
    final rentData = readObject(jsonDecode(strings[2]));
    final period = readText(rentData, 'period');
    final source = DataSource(
      title: readText(rentData, 'source'),
      url: readText(rentData, 'url'),
    );
    final loadedRents = <String, RentReference>{};
    for (final raw in readList(rentData['cities'])) {
      final item = readObject(raw);
      loadedRents[readText(item, 'name')] = RentReference(
        average: readNumber(item, 'average'),
        median: readNumber(item, 'median'),
        period: period,
        source: source,
      );
    }
    if (loadedCities.map((c) => c.code).toSet().length != loadedCities.length) {
      throw const FormatException('城市编码重复');
    }
    cities = loadedCities;
    profiles = {for (final profile in loadedProfiles) profile.code: profile};
    rents = loadedRents;
  }
}
