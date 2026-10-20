import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../update/update_check_button.dart';
import '../update/update_service.dart';

/// 地图的返回全国与缩放按钮；安卓上末尾多一个“检查更新”。
///
/// 宽屏竖排在地图右下角（返回全国、放大、缩小）；手机横排在提示行右侧
/// （返回全国、缩小、放大）。
class MapToolbar extends StatelessWidget {
  const MapToolbar({
    super.key,
    required this.onHome,
    required this.onZoomIn,
    required this.onZoomOut,
    this.horizontal = false,
  });

  final VoidCallback onHome;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final bool horizontal;

  @override
  Widget build(BuildContext context) {
    final home = _button('返回全国', Icons.public, onHome);
    final zoomIn = _button('放大', Icons.add, onZoomIn);
    final zoomOut = _button('缩小', Icons.remove, onZoomOut);
    final update = UpdateService.isSupported ? const UpdateCheckButton() : null;
    return Material(
      elevation: horizontal ? 2 : 3,
      shadowColor: Color(horizontal ? 0x30244e42 : 0x40244e42),
      color: AppColors.background,
      borderRadius: BorderRadius.circular(horizontal ? 12 : 10),
      child: horizontal
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [home, zoomOut, zoomIn, ?update],
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [home, zoomIn, zoomOut, ?update],
            ),
    );
  }

  Widget _button(String tooltip, IconData icon, VoidCallback onPressed) =>
      IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        style: IconButton.styleFrom(
          minimumSize: const Size(40, 40),
          maximumSize: const Size(40, 40),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: EdgeInsets.zero,
          foregroundColor: AppColors.label,
        ),
        icon: Icon(icon, size: 18),
      );
}
