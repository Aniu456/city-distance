import 'package:flutter/services.dart';

import '../models/map_region.dart';
import 'geojson_parser.dart';

class MapRepository {
  MapRepository({AssetBundle? bundle}) : _bundle = bundle ?? rootBundle;

  final AssetBundle _bundle;
  final _cache = <String, List<MapRegion>>{};
  final _pending = <String, Future<List<MapRegion>>>{};
  final _regions = <String, MapRegion>{};
  final _parents = <String, String>{};

  List<MapRegion>? cached(String code) => _cache[code];

  /// 已加载过的区域；所在的上级文件尚未加载时返回 null。
  MapRegion? region(String code) => _regions[code];

  /// 已加载区域的上级编码；全国文件中的省级区域返回 `100000`。
  String? parentOf(String code) => _parents[code];

  /// 从省级到 [code] 的编码路径，只包含已加载的层级。
  List<String> pathTo(String code) {
    final path = <String>[];
    String? current = code;
    while (current != null && current != '100000' && path.length < 8) {
      path.insert(0, current);
      current = _parents[current];
    }
    return path;
  }

  Future<List<MapRegion>> load(String code) async {
    final existing = _cache[code];
    if (existing != null) {
      return existing;
    }
    final pending = _pending[code];
    if (pending != null) {
      return pending;
    }
    final future = _read(code);
    _pending[code] = future;
    try {
      final regions = await future;
      _cache[code] = regions;
      for (final region in regions) {
        _regions[region.code] = region;
        _parents[region.code] = code;
      }
      return regions;
    } finally {
      _pending.remove(code);
    }
  }

  Future<List<MapRegion>> _read(String code) async {
    final source = await _bundle.loadString('assets/maps/$code.json');
    return parseRegions(source);
  }
}
