// ignore_for_file: avoid_print
// 平移基准：flutter test tool/bench/pan_bench_test.dart
// 统计平移时每帧重建的 widget 数量和每帧耗时（测试环境，只用于前后对比）。
import 'dart:io';

import 'package:china_map/main.dart';
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

void main() {
  testWidgets('pan bench', (tester) async {
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
    });
    await tester.pumpWidget(const ChinaMapApp());
    await settle(tester);
    // 放大到市级再平移。
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.byTooltip('放大'));
      await settle(tester);
    }
    final map = find.byType(InteractiveViewer);
    var rebuilt = 0;
    debugOnRebuildDirtyWidget = (element, builtOnce) => rebuilt++;
    final gesture = await tester.startGesture(tester.getCenter(map));
    const frames = 60;
    final watch = Stopwatch()..start();
    for (var i = 0; i < frames; i++) {
      await gesture.moveBy(const Offset(3, 1));
      await tester.pump(const Duration(milliseconds: 16));
    }
    watch.stop();
    await gesture.up();
    debugOnRebuildDirtyWidget = null;
    await settle(tester);
    print(
      'BENCH pan ${(watch.elapsedMicroseconds / frames / 1000).toStringAsFixed(2)} ms/frame, '
      '${(rebuilt / frames).toStringAsFixed(0)} widgets rebuilt/frame',
    );
  });
}
