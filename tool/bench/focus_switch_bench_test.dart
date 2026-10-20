// ignore_for_file: avoid_print
// 跨省平移（聚焦切换）基准：flutter test tool/bench/focus_switch_bench_test.dart
// 从江西中部向西平移到湖南中部，统计每帧耗时、聚焦切换所在帧的耗时和
// 每帧重建的 widget 数量（测试环境，只用于前后对比）。
import 'dart:io';
import 'dart:math' as math;

import 'package:china_map/main.dart';
import 'package:china_map/utils/map_projection.dart';
import 'package:china_map/widgets/label_text_cache.dart';
import 'package:china_map/widgets/map_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 150));
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 100)),
  );
  await tester.pumpAndSettle();
}

MapPainter painter(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((widget) => widget.painter)
    .whereType<MapPainter>()
    .single;

void main() {
  for (final span in [190.0, 60.0]) {
    testWidgets('focus switch bench span $span', (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      await tester.runAsync(() async {
        for (final dir in ['assets/maps', 'assets/cities']) {
          for (final file in Directory(dir).listSync()) {
            if (file.path.endsWith('.json')) {
              await rootBundle.loadString(file.path);
            }
          }
        }
        // 测试默认字体排版极快；设 BENCH_FONT 为真实中文字体以接近真机排版开销。
        final font = Platform.environment['BENCH_FONT'];
        if (font != null) {
          final bytes = File(font).readAsBytesSync();
          final loader = FontLoader('Roboto')
            ..addFont(Future.value(ByteData.sublistView(bytes)));
          await loader.load();
        }
      });
      await tester.pumpWidget(const ChinaMapApp());
      await settle(tester);
      final map = find.byType(InteractiveViewer);
      final controller =
          tester.widget<InteractiveViewer>(map).transformationController!;
      final size = tester.getSize(map);
      final scale = math.max(size.width, size.height) / span;
      final translation =
          size.center(Offset.zero) - project(115.9, 27.6) * scale;
      controller.value = Matrix4.identity()
        ..translateByDouble(translation.dx, translation.dy, 0, 1)
        ..scaleByDouble(scale, scale, scale, 1);
      await settle(tester);
      final shift = (project(115.9, 27.6) - project(111.7, 27.6)) * scale;
      const frames = 40;
      final times = <double>[];
      final misses = <int>[];
      var rebuilt = 0;
      var switchFrame = -1;
      var focus = painter(tester).detailProvinces;
      debugOnRebuildDirtyWidget = (element, builtOnce) => rebuilt++;
      final gesture = await tester.startGesture(tester.getCenter(map));
      for (var i = 0; i < frames; i++) {
        final before = LabelTextCache.shared.misses;
        final watch = Stopwatch()..start();
        await gesture.moveBy(shift / frames.toDouble());
        await tester.pump(const Duration(milliseconds: 16));
        watch.stop();
        times.add(watch.elapsedMicroseconds / 1000.0);
        misses.add(LabelTextCache.shared.misses - before);
        final current = painter(tester).detailProvinces;
        if (switchFrame < 0 && current?.join() != focus?.join()) {
          switchFrame = i;
        }
        focus = current;
      }
      await gesture.up();
      debugOnRebuildDirtyWidget = null;
      await settle(tester);
      final sorted = [...times]..sort();
      print(
        'BENCH focus-switch span=$span '
        'mean ${(times.reduce((a, b) => a + b) / frames).toStringAsFixed(2)} ms, '
        'p50 ${sorted[frames ~/ 2].toStringAsFixed(2)} ms, '
        'max ${sorted.last.toStringAsFixed(2)} ms '
        '(frame ${times.indexOf(sorted.last)}), '
        'switch at frame $switchFrame '
        '(${switchFrame < 0 ? '-' : times[switchFrame].toStringAsFixed(2)} ms), '
        '${(rebuilt / frames).toStringAsFixed(0)} widgets rebuilt/frame, '
        'focus now $focus',
      );
      print('BENCH text layouts/frame ${misses.join(' ')}');
      print('BENCH frames ${times.map((t) => t.toStringAsFixed(1)).join(' ')}');
    });
  }
}
