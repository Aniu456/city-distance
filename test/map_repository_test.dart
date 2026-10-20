import 'dart:convert';

import 'package:china_map/data/map_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// 内存中的地图资源，记录每个文件被读取的次数。
class _FakeBundle extends CachingAssetBundle {
  _FakeBundle(this.files);

  final Map<String, String> files;
  final reads = <String, int>{};

  @override
  Future<ByteData> load(String key) async {
    reads.update(key, (n) => n + 1, ifAbsent: () => 1);
    final source = files[key];
    if (source == null) {
      throw FlutterError('missing $key');
    }
    return ByteData.sublistView(Uint8List.fromList(utf8.encode(source)));
  }
}

String _collection(List<String> codes, {double x = 110}) => jsonEncode({
  'type': 'FeatureCollection',
  'features': [
    for (final (index, code) in codes.indexed)
      {
        'type': 'Feature',
        'properties': {
          'adcode': int.parse(code),
          'name': code,
          'level': code.endsWith('00') ? 'city' : 'district',
          'childrenNum': code.endsWith('00') ? 1 : 0,
        },
        'geometry': {
          'type': 'Polygon',
          'coordinates': [
            [
              [x + index, 30],
              [x + index + 1, 30],
              [x + index + 1, 31],
              [x + index, 30],
            ],
          ],
        },
      },
  ],
});

void main() {
  late _FakeBundle bundle;

  setUp(() {
    bundle = _FakeBundle({
      'assets/maps/360000.json': _collection(['360100', '360200', '360300']),
      'assets/maps/360100.json': _collection(['360102']),
      'assets/maps/360200.json': _collection(['360202']),
      'assets/maps/360300.json': _collection(['360302']),
    });
  });

  test('并发加载同一文件只读取一次', () async {
    final repository = MapRepository(bundle: bundle);
    final results = await Future.wait([
      repository.load('360000'),
      repository.load('360000'),
    ]);
    expect(identical(results[0], results[1]), isTrue);
    expect(bundle.reads['assets/maps/360000.json'], 1);
  });

  test('区县文件按最近最少使用淘汰，省级文件常驻，引用一并清除', () async {
    final repository = MapRepository(bundle: bundle, maxDetailFiles: 2);
    await repository.load('360000');
    await repository.load('360100');
    await repository.load('360200');
    // 使用 360100 后，360200 成为最久未使用。
    expect(repository.cached('360100'), isNotNull);
    await repository.load('360300');
    expect(repository.cached('360200'), isNull);
    expect(repository.region('360202'), isNull);
    expect(repository.parentOf('360202'), isNull);
    expect(repository.cached('360100'), isNotNull);
    expect(repository.cached('360300'), isNotNull);
    expect(repository.cached('360000'), isNotNull);
    expect(repository.region('360200'), isNotNull);
    // 被淘汰的文件可以重新加载。
    await repository.load('360200');
    expect(repository.region('360202'), isNotNull);
    expect(bundle.reads['assets/maps/360200.json'], 2);
  });

  test('仍在使用的区县文件不会被淘汰', () async {
    final repository = MapRepository(
      bundle: bundle,
      maxDetailFiles: 1,
      isRetained: (code) => code == '360100',
    );
    await repository.load('360000');
    await repository.load('360100');
    await repository.load('360200');
    await repository.load('360300');
    expect(repository.cached('360100'), isNotNull);
    expect(repository.cached('360200'), isNull);
    expect(repository.cached('360300'), isNotNull);
  });
}
