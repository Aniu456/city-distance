// ignore_for_file: avoid_print
// 性能基准：flutter test tool/bench/map_bench_test.dart
// 只打印耗时，不做断言；数值随机器和调试模式变化，仅用于前后对比。
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:china_map/data/geojson_parser.dart';
import 'package:china_map/models/city.dart';
import 'package:china_map/models/map_region.dart';
import 'package:china_map/utils/map_projection.dart';
import 'package:china_map/widgets/map_painter.dart';
import 'package:flutter_test/flutter_test.dart';

List<MapRegion> read(String code) =>
    parseRegions(File('assets/maps/$code.json').readAsStringSync());

double time(int runs, void Function() body) {
  body();
  final watch = Stopwatch()..start();
  for (var i = 0; i < runs; i++) {
    body();
  }
  return watch.elapsedMicroseconds / runs / 1000;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bench', () {
    final national = File('assets/maps/100000.json').readAsStringSync();
    print(
      'BENCH parse national ${time(5, () => parseRegions(national)).toStringAsFixed(1)} ms',
    );
    final decode = time(5, () => jsonDecode(national));
    print('BENCH jsonDecode national ${decode.toStringAsFixed(1)} ms');
    var all = 0.0;
    var bytes = 0;
    for (final file in Directory(
      'assets/maps',
    ).listSync().where((f) => f.path.endsWith('.json'))) {
      final source = File(file.path).readAsStringSync();
      bytes += source.length;
      final watch = Stopwatch()..start();
      parseRegions(source);
      all += watch.elapsedMicroseconds / 1000;
    }
    print(
      'BENCH parse all ${all.toStringAsFixed(0)} ms for ${bytes ~/ 1024} KB',
    );

    final provinces = read('100000');
    final cities =
        (jsonDecode(File('assets/cities/catalog.json').readAsStringSync())
                as List)
            .map((raw) => City.fromJson(raw as Map<String, Object?>))
            .toList();
    final jiangxi = read('360000');
    final nanchang = read('360100');
    final viewport = const Size(377, 640);
    Rect view(double lon, double lat, double span) => Rect.fromCenter(
      center: project(lon, lat),
      width: span * viewport.width / viewport.height,
      height: span,
    );
    final cases = <String, MapPainter Function()>{
      'national': () => MapPainter(
        regions: provinces,
        provinces: provinces,
        cities: cities,
        scale: viewport.height / 1300,
        view: view(104, 36, 1300),
      ),
      'jiangxi-city': () => MapPainter(
        regions: [...provinces.where((r) => r.code != '360000'), ...jiangxi],
        provinces: provinces,
        cityBoundaries: jiangxi,
        cities: cities,
        showCities: true,
        detailProvinces: const {'360000'},
        scale: viewport.height / 190,
        view: view(115.9, 27.6, 190),
      ),
      'nanchang-district': () => MapPainter(
        regions: [
          ...provinces.where((r) => r.code != '360000'),
          ...jiangxi.where((r) => r.code != '360100'),
          ...nanchang,
        ],
        provinces: provinces,
        cityBoundaries: jiangxi,
        cities: cities,
        showCities: true,
        showDistricts: true,
        detailProvinces: const {'360000'},
        scale: viewport.height / 60,
        view: view(115.9, 28.7, 60),
      ),
    };
    for (final entry in cases.entries) {
      // 每次新建画笔，与真实每帧重建一致。
      final paint = time(20, () {
        final recorder = PictureRecorder();
        entry.value().paint(Canvas(recorder), viewport);
        recorder.endRecording().dispose();
      });
      final labels = time(20, () => entry.value().layoutLabels());
      print(
        'BENCH ${entry.key} paint ${paint.toStringAsFixed(2)} ms, '
        'layoutLabels ${labels.toStringAsFixed(2)} ms, '
        'labels ${entry.value().layoutLabels().length}',
      );
    }
  });
}
