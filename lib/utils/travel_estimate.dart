import 'dart:math' as math;

import '../models/city.dart';

/// 仅为城市比较的距离模型，不查询铁路网或时刻表。
class TravelEstimate {
  TravelEstimate(this.origin, this.destination)
    : straightKm = distanceKm(origin, destination);
  final City origin;
  final City destination;
  final double straightKm;

  String? get unavailableReason {
    if (origin.code == destination.code) {
      return '出发地与目的地是同一座城市';
    }
    if (_network(origin) != _network(destination) ||
        _network(origin) == 'unverified') {
      return '跨海或特殊区域，暂不适用此铁路耗时估算';
    }
    return null;
  }

  /// 采用假设的绕行系数 1.15–1.50；不将结果称为实测铁路里程。
  /// 高铁假设均速 160–250 km/h，普铁 60–100 km/h，向外取整到半小时。
  (double, double) hours({required bool highSpeed}) {
    if (unavailableReason != null) {
      throw StateError('该城市组合不适用估算');
    }
    final fast = highSpeed ? 250 : 100;
    final slow = highSpeed ? 160 : 60;
    final low = math.max(0.5, (straightKm * 1.15 / fast * 2).floor() / 2);
    final high = math.max(low, (straightKm * 1.5 / slow * 2).ceil() / 2);
    return (low, high);
  }

  static String _network(City city) {
    if (city.provinceCode == '820000' ||
        city.code == '460300' ||
        city.code == 'tw_09007' ||
        city.code == 'tw_09020') {
      return 'unverified';
    }
    if (city.provinceCode == '710000') {
      return 'taiwan';
    }
    if (city.provinceCode == '460000') {
      return 'hainan';
    }
    return 'mainland';
  }
}

double distanceKm(City first, City second) {
  final lat1 = first.latitude * math.pi / 180;
  final lat2 = second.latitude * math.pi / 180;
  final dLat = lat2 - lat1;
  final dLon = (second.longitude - first.longitude) * math.pi / 180;
  final a =
      math.pow(math.sin(dLat / 2), 2) +
      math.cos(lat1) * math.cos(lat2) * math.pow(math.sin(dLon / 2), 2);
  return 6371.0088 * 2 * math.asin(math.sqrt(a.clamp(0, 1)));
}

String formatHours((double, double) range) {
  String number(double hours) => hours == hours.roundToDouble()
      ? hours.toStringAsFixed(0)
      : hours.toStringAsFixed(1);
  return range.$1 == range.$2
      ? '约 ${number(range.$1)} 小时'
      : '约 ${number(range.$1)}–${number(range.$2)} 小时';
}
