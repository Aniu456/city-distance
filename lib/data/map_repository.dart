import 'package:flutter/services.dart';

import '../models/map_region.dart';
import 'geojson_parser.dart';

/// 按行政区编码加载并缓存边界数据，并发请求同一文件时只读取一次。
///
/// 全国和省级文件（其下为地级市）常驻；地级市文件（其下为区县）按最近
/// 最少使用淘汰，最多保留 [maxDetailFiles] 个。[isRetained] 返回 true 的
/// 文件（当前视野、聚焦或选中所需）不会被淘汰。原始 JSON 解析后即丢弃，
/// 不留在资源包缓存中。
class MapRepository {
  MapRepository({
    AssetBundle? bundle,
    this.maxDetailFiles = 48,
    this.isRetained,
  }) : _bundle = bundle ?? rootBundle;

  final AssetBundle _bundle;

  /// 最多缓存的地级市（区县边界）文件数。
  final int maxDetailFiles;

  /// 判断某个已缓存文件当前是否仍在使用；为 null 时只按数量淘汰。
  bool Function(String code)? isRetained;

  final _cache = <String, List<MapRegion>>{};
  final _pending = <String, Future<List<MapRegion>>>{};
  final _regions = <String, MapRegion>{};
  final _parents = <String, String>{};

  /// 地级市文件的使用顺序，最早使用的在前。
  final _detailOrder = <String>{};

  /// [code] 的下级区域；未加载或已被淘汰时返回 null。
  List<MapRegion>? cached(String code) {
    final regions = _cache[code];
    if (regions != null && _detailOrder.remove(code)) {
      _detailOrder.add(code);
    }
    return regions;
  }

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
    final existing = cached(code);
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
      if (_isDetail(code)) {
        _detailOrder.add(code);
        _evict(keep: code);
      }
      return regions;
    } finally {
      _pending.remove(code);
    }
  }

  /// 地级市文件（其下级为区县）：编码不以 `0000` 结尾，全国和省级文件除外。
  static bool _isDetail(String code) => !code.endsWith('0000');

  /// 淘汰超出数量的区县文件；刚加载的 [keep] 正被请求方使用，不参与淘汰。
  void _evict({required String keep}) {
    var excess = _detailOrder.length - maxDetailFiles;
    if (excess <= 0) {
      return;
    }
    for (final code in _detailOrder.toList()) {
      if (excess <= 0) {
        break;
      }
      if (code == keep || (isRetained?.call(code) ?? false)) {
        continue;
      }
      _detailOrder.remove(code);
      for (final region in _cache.remove(code) ?? const <MapRegion>[]) {
        _regions.remove(region.code);
        _parents.remove(region.code);
      }
      excess--;
    }
  }

  Future<List<MapRegion>> _read(String code) async {
    final key = 'assets/maps/$code.json';
    final String source;
    try {
      source = await _bundle.loadString(key);
    } finally {
      // 解析后的区域已缓存在本仓库，原始 JSON 不必再留在资源包缓存里；
      // 读取失败时资源包会缓存失败结果，也须清除，重试才会真正重新读取。
      _bundle.evict(key);
    }
    return parseRegions(source);
  }
}
