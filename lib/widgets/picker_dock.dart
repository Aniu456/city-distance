import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// 底部停靠选择器的布局：[children] 第一项为页面内容，可选的第二项为选择器。
///
/// 选择器高度上限按页面内容实际排版出的最小高度（行程卡片、提示栏等）计算，
/// 并至少为内容保留 [reserved]；横屏等矮屏幕下内容不会被挤到溢出。
class PickerDock extends MultiChildRenderObjectWidget {
  const PickerDock({
    super.key,
    required this.reserved,
    required super.children,
  });

  final double reserved;

  @override
  RenderPickerDock createRenderObject(BuildContext context) =>
      RenderPickerDock(reserved);

  @override
  void updateRenderObject(BuildContext context, RenderPickerDock renderObject) {
    renderObject.reserved = reserved;
  }
}

/// [RenderPickerDock] 子节点的父数据。
class DockParentData extends ContainerBoxParentData<RenderBox> {}

/// [PickerDock] 的渲染对象。
class RenderPickerDock extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, DockParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, DockParentData> {
  RenderPickerDock(this._reserved);

  double _reserved;
  set reserved(double value) {
    if (value != _reserved) {
      _reserved = value;
      markNeedsLayout();
    }
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! DockParentData) {
      child.parentData = DockParentData();
    }
  }

  @override
  void performLayout() {
    final size = this.size = constraints.biggest;
    final content = firstChild!;
    final dock = childAfter(content);
    var dockHeight = 0.0;
    if (dock != null) {
      final minContent = content.getMinIntrinsicHeight(size.width);
      final maxHeight = math.max(
        0.0,
        size.height - math.max(_reserved, minContent),
      );
      dock.layout(
        BoxConstraints(
          minWidth: size.width,
          maxWidth: size.width,
          maxHeight: maxHeight,
        ),
        parentUsesSize: true,
      );
      dockHeight = dock.size.height;
      (dock.parentData! as DockParentData).offset = Offset(
        0,
        size.height - dockHeight,
      );
    }
    content.layout(
      BoxConstraints.tightFor(
        width: size.width,
        height: size.height - dockHeight,
      ),
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}

/// 可滚动的部分不要求最小高度：计算 [PickerDock] 内容最小高度时按 0 计，
/// 也避免对列表等不支持固有尺寸的子树求固有高度。
class NoMinHeight extends SingleChildRenderObjectWidget {
  const NoMinHeight({super.key, super.child});

  @override
  RenderBox createRenderObject(BuildContext context) => _RenderNoMinHeight();
}

class _RenderNoMinHeight extends RenderProxyBox {
  @override
  double computeMinIntrinsicHeight(double width) => 0;

  @override
  double computeMaxIntrinsicHeight(double width) => 0;
}
