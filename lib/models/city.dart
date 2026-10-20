import 'dart:ui';

import '../utils/map_projection.dart';

/// 城市位置用于城市间估算，不代表火车站位置。
class City {
  const City({
    required this.code,
    required this.name,
    required this.province,
    required this.provinceCode,
    required this.longitude,
    required this.latitude,
    required this.isCapital,
    required this.capitalKind,
  });

  final String code;
  final String name;
  final String province;
  final String provinceCode;
  final double longitude;
  final double latitude;
  final bool isCapital;
  final String capitalKind;

  Offset get point => project(longitude, latitude);

  factory City.fromJson(Map<String, Object?> json) {
    final longitude = json['longitude'];
    final latitude = json['latitude'];
    if (longitude is! num ||
        latitude is! num ||
        !longitude.isFinite ||
        !latitude.isFinite ||
        longitude.abs() > 180 ||
        latitude.abs() >= 90) {
      throw const FormatException('城市坐标无效');
    }
    return City(
      code: readText(json, 'code'),
      name: readText(json, 'name'),
      province: readText(json, 'province'),
      provinceCode: readText(json, 'provinceCode'),
      longitude: longitude.toDouble(),
      latitude: latitude.toDouble(),
      isCapital: json['isCapital'] as bool,
      capitalKind: readText(json, 'capitalKind'),
    );
  }
}

String readText(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('城市资料缺少 $key');
  }
  return value;
}

double readNumber(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! num || !value.isFinite || value < 0) {
    throw FormatException('城市资料中的 $key 无效');
  }
  return value.toDouble();
}

Map<String, Object?> readObject(Object? value) {
  if (value is! Map<String, Object?>) {
    throw const FormatException('城市资料对象格式无效');
  }
  return value;
}

List<Object?> readList(Object? value) {
  if (value is! List<Object?>) {
    throw const FormatException('城市资料数组格式无效');
  }
  return value;
}
