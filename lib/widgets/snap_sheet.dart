import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// 可拖动的底部面板，只有两个停靠点：默认收起摘要和展开详情。
///
/// 内容须使用 [builder] 提供的滚动控制器：面板未完全展开时，上下拖动改变面板高度；
/// 完全展开后继续上滑滚动内容，内容回到顶部后下滑再收起面板。
/// 下滑最低停在默认收起高度，不会更低也不会关闭；关闭只能由内容中的显式操作完成。
class SnapSheet extends StatefulWidget {
  const SnapSheet({
    super.key,
    required this.collapsedHeight,
    required this.builder,
    this.expandedFraction = 0.94,
  });

  /// 收起时的高度，单位为逻辑像素。
  final double collapsedHeight;

  /// 展开时占父级高度的比例。
  final double expandedFraction;

  final Widget Function(
    BuildContext context,
    ScrollController controller,
    VoidCallback toggle,
    ValueListenable<double> expansion,
  )
  builder;

  @override
  State<SnapSheet> createState() => SnapSheetState();
}

class SnapSheetState extends State<SnapSheet> {
  final _controller = DraggableScrollableController();
  double _collapsed = 0.3;
  double _expanded = 0.94;

  bool get _attached => _controller.isAttached;

  /// 展开进度：默认收起为 0，完全展开为 1，随拖动连续变化。
  final _expansion = ValueNotifier<double>(0);

  bool _onExtent(DraggableScrollableNotification notification) {
    _expansion.value =
        ((notification.extent - _collapsed) /
                math.max(_expanded - _collapsed, 1e-6))
            .clamp(0.0, 1.0);
    return false;
  }

  /// 是否接近展开停靠点。
  bool get isExpanded =>
      _attached && _controller.size > (_collapsed + _expanded) / 2;

  @override
  void dispose() {
    _controller.dispose();
    _expansion.dispose();
    super.dispose();
  }

  /// 点击把手或摘要：在收起摘要和展开详情之间切换。
  void toggle() {
    if (!_attached) {
      return;
    }
    _controller.animateTo(
      isExpanded ? _collapsed : _expanded,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = math.max(constraints.maxHeight, 1.0);
        _expanded = widget.expandedFraction.clamp(0.2, 1.0);
        _collapsed = (widget.collapsedHeight / height).clamp(
          0.1,
          _expanded - 0.05,
        );
        return NotificationListener<DraggableScrollableNotification>(
          onNotification: _onExtent,
          child: DraggableScrollableSheet(
            controller: _controller,
            initialChildSize: _collapsed,
            // 最小即默认收起高度：下拖到底停在这里，与首次打开时一致。
            minChildSize: _collapsed,
            maxChildSize: _expanded,
            snap: true,
            snapAnimationDuration: const Duration(milliseconds: 220),
            builder: (context, controller) => Material(
              key: const ValueKey('snap-sheet-body'),
              color: AppColors.background,
              elevation: 6,
              shadowColor: const Color(0x30244e42),
              clipBehavior: Clip.antiAlias,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
              child: widget.builder(context, controller, toggle, _expansion),
            ),
          ),
        );
      },
    );
  }
}
