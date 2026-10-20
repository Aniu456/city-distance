import 'dart:math' as math;

import 'package:china_map/main.dart';
import 'package:china_map/utils/map_projection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// 途经点（经度、纬度）：江西 → 湖南 → 贵州 → 重庆 → 四川 → 返回江西。
const _route = [
  (115.9, 27.6),
  (111.7, 27.6),
  (106.7, 26.6),
  (106.5, 29.6),
  (104.1, 30.7),
  (115.9, 27.6),
];

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized()
    // 按真实帧率出帧，测得的帧耗时与日常使用一致。
    ..framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  Future<void> wait(WidgetTester tester, int ms) async {
    final end = DateTime.now().add(Duration(milliseconds: ms));
    while (DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  /// 把镜头对准 [lon]/[lat]，视野最长边约为 [span] 个地图单位。
  Future<void> lookAt(WidgetTester tester, double span) async {
    final map = find.byType(InteractiveViewer);
    final controller = tester
        .widget<InteractiveViewer>(map)
        .transformationController!;
    final size = tester.getSize(map);
    final scale = math.max(size.width, size.height) / span;
    final start = project(_route.first.$1, _route.first.$2);
    final translation = size.center(Offset.zero) - start * scale;
    controller.value = Matrix4.identity()
      ..translateByDouble(translation.dx, translation.dy, 0, 1)
      ..scaleByDouble(scale, scale, scale, 1);
    await wait(tester, 1500);
  }

  /// 按途经点逐段拖动，每段约 1 秒、60 步，模拟手指连续平移。
  Future<void> pan(WidgetTester tester, double span) async {
    final map = find.byType(InteractiveViewer);
    final size = tester.getSize(map);
    final scale = math.max(size.width, size.height) / span;
    for (var leg = 1; leg < _route.length; leg++) {
      final from = project(_route[leg - 1].$1, _route[leg - 1].$2);
      final to = project(_route[leg].$1, _route[leg].$2);
      final total = (from - to) * scale;
      // 每段拆成多次手势，单次不超过屏幕宽度的 60%。
      final strokes = (total.distance / (size.width * 0.6)).ceil().clamp(1, 40);
      for (var s = 0; s < strokes; s++) {
        final gesture = await tester.startGesture(tester.getCenter(map));
        for (var i = 0; i < 30; i++) {
          await gesture.moveBy(total / (strokes * 30.0));
          await tester.pump(const Duration(milliseconds: 16));
        }
        await gesture.up();
        await tester.pump(const Duration(milliseconds: 16));
      }
    }
    await wait(tester, 500);
  }

  for (final (name, span) in [('city', 190.0), ('district', 60.0)]) {
    testWidgets('long pan $name zoom', (tester) async {
      await tester.pumpWidget(const ChinaMapApp());
      await wait(tester, 3000);
      await lookAt(tester, span);
      await binding.traceAction(
        () => pan(tester, span),
        reportKey: 'pan_$name',
      );
    });
  }
}
