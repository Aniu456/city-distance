// ignore_for_file: avoid_print
// 长距离多省平移基准：flutter test tool/bench/long_pan_bench_test.dart
// 江西 → 湖南 → 贵州 → 重庆 → 四川，城市与区县两个缩放层级，统计 p50 / p95 /
// 最差帧耗时、每帧新建文字排版数和区县文件加载数（测试环境，只用于前后对比；
// 测试中地图文件在当前线程解析，加载开销计入所在帧）。
// 设 BENCH_FONT 为真实中文字体以接近真机排版开销。
import 'dart:io';
import 'dart:math' as math;

import 'package:china_map/data/map_repository.dart';
import 'package:china_map/main.dart';
import 'package:china_map/utils/map_projection.dart';
import 'package:china_map/widgets/label_text_cache.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 150));
  // 地图文件未预热，真实 IO 需在真实时间里完成：交替等待与推进帧。
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// 途经点（经度、纬度），相邻两点之间平均分配帧数。
const _route = [
  (115.9, 27.6),
  (111.7, 27.6),
  (106.7, 26.6),
  (106.5, 29.6),
  (104.1, 30.7),
];

void main() {
  for (final span in [190.0, 60.0]) {
    testWidgets('long pan bench span $span', (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      // BENCH_BG=1 时与应用一致，在后台 isolate 解码地图文件。
      MapRepository.decodeInBackground =
          Platform.environment['BENCH_BG'] == '1';
      addTearDown(() => MapRepository.decodeInBackground = false);
      var reads = 0;
      await tester.runAsync(() async {
        for (final dir in ['assets/cities']) {
          for (final file in Directory(dir).listSync()) {
            if (file.path.endsWith('.json')) {
              await rootBundle.loadString(file.path);
            }
          }
        }
        final font = Platform.environment['BENCH_FONT'];
        if (font != null) {
          final bytes = File(font).readAsBytesSync();
          final loader = FontLoader('Roboto')
            ..addFont(Future.value(ByteData.sublistView(bytes)));
          await loader.load();
        }
      });
      // 地图文件不预热，每次读取都经由资源通道，计为一次加载。
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMessageHandler('flutter/assets', (message) async {
        reads++;
        final key = String.fromCharCodes(message!.buffer.asUint8List());
        return ByteData.sublistView(File(Uri.decodeFull(key)).readAsBytesSync());
      });
      addTearDown(() => messenger.setMockMessageHandler('flutter/assets', null));
      await tester.pumpWidget(const ChinaMapApp());
      await settle(tester);
      final map = find.byType(InteractiveViewer);
      final controller =
          tester.widget<InteractiveViewer>(map).transformationController!;
      final size = tester.getSize(map);
      final scale = math.max(size.width, size.height) / span;
      final start = project(_route.first.$1, _route.first.$2);
      final translation = size.center(Offset.zero) - start * scale;
      controller.value = Matrix4.identity()
        ..translateByDouble(translation.dx, translation.dy, 0, 1)
        ..scaleByDouble(scale, scale, scale, 1);
      await settle(tester);
      const perLeg = 50;
      final times = <double>[];
      final layouts = <int>[];
      final loads = <int>[];
      reads = 0;
      final gesture = await tester.startGesture(tester.getCenter(map));
      for (var leg = 1; leg < _route.length; leg++) {
        final from = project(_route[leg - 1].$1, _route[leg - 1].$2);
        final to = project(_route[leg].$1, _route[leg].$2);
        final step = (from - to) * scale / perLeg.toDouble();
        for (var i = 0; i < perLeg; i++) {
          final misses = LabelTextCache.shared.misses;
          final before = reads;
          final watch = Stopwatch()..start();
          await gesture.moveBy(step);
          await tester.pump(const Duration(milliseconds: 16));
          watch.stop();
          times.add(watch.elapsedMicroseconds / 1000.0);
          layouts.add(LabelTextCache.shared.misses - misses);
          loads.add(reads - before);
          // 让本帧发起的真实 IO 有机会完成，下一帧解析。
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 2)),
          );
        }
      }
      await gesture.up();
      await settle(tester);
      final sorted = [...times]..sort();
      double at(double q) => sorted[((sorted.length - 1) * q).round()];
      final worst = times.indexOf(sorted.last);
      print(
        'BENCH long-pan span=$span frames ${times.length}: '
        'p50 ${at(0.5).toStringAsFixed(2)} ms, '
        'p95 ${at(0.95).toStringAsFixed(2)} ms, '
        'max ${sorted.last.toStringAsFixed(2)} ms (frame $worst: '
        '${layouts[worst]} layouts, ${loads[worst]} loads), '
        'frames >8ms ${times.where((t) => t > 8).length}, '
        'text layouts total ${layouts.reduce((a, b) => a + b)} '
        '(max/frame ${layouts.reduce(math.max)}), '
        'file loads ${loads.reduce((a, b) => a + b)}',
      );
    });
  }
}
