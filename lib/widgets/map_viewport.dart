import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../utils/map_projection.dart';
import 'map_painter.dart';

/// 地图视口：手势、平移缩放和画布，以及加载中与出错重试的覆盖层。
///
/// 只有画布监听 [repaint]（镜头和下级数据变化），平移缩放的每一帧不重建
/// 视口之外的页面。视口尺寸变化时调用 [onResize]。
class MapViewport extends StatelessWidget {
  const MapViewport({
    super.key,
    required this.transform,
    required this.repaint,
    required this.painter,
    required this.minScale,
    required this.maxScale,
    required this.onResize,
    required this.onTapUp,
    required this.onInteractionStart,
    required this.loading,
    this.error,
    this.onRetry,
  });

  final TransformationController transform;

  /// 触发画布重建的监听对象。
  final Listenable repaint;

  /// 每次重建画布时调用，返回本帧的画笔。
  final MapPainter Function() painter;

  final double minScale;
  final double maxScale;
  final ValueChanged<Size> onResize;

  /// 点击位置，视口坐标。
  final ValueChanged<Offset> onTapUp;
  final VoidCallback onInteractionStart;
  final bool loading;

  /// 需要显示的错误文字；为 null 时不显示重试按钮。
  final String? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      onResize(constraints.biggest);
      return Stack(
        children: [
          Positioned.fill(
            child: ColoredBox(
              color: AppColors.mapBackground,
              child: GestureDetector(
                onTapUp: (details) => onTapUp(details.localPosition),
                child: InteractiveViewer(
                  transformationController: transform,
                  onInteractionStart: (_) => onInteractionStart(),
                  constrained: false,
                  minScale: minScale,
                  maxScale: maxScale,
                  boundaryMargin: const EdgeInsets.all(1400),
                  trackpadScrollCausesScale: true,
                  child: ListenableBuilder(
                    listenable: repaint,
                    builder: (context, _) =>
                        CustomPaint(size: mapSize, painter: painter()),
                  ),
                ),
              ),
            ),
          ),
          if (loading) const Center(child: CircularProgressIndicator()),
          if (error case final error?)
            Center(
              child: FilledButton.tonalIcon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: Text(error),
              ),
            ),
        ],
      );
    },
  );
}
