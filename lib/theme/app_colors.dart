import 'dart:ui';

/// 应用与地图绘制使用的颜色。
abstract final class AppColors {
  static const primary = Color(0xff287565);
  static const background = Color(0xfff7f9f8);
  static const mapBackground = Color(0xffeef3f2);
  static const placeholder = Color(0xff727772);
  static const hintText = Color(0xff5c706a);

  /// 区域按编码哈希轮换的填充色。
  static const regionPalette = [
    Color(0xffe7ede9),
    Color(0xffe2eae5),
    Color(0xffedf1ed),
  ];
  static const regionSelected = Color(0xffb9d7cb);
  static const regionBorder = Color(0xff78958b);
  static const provinceBase = Color(0xffe7ede9);
  static const provinceBorder = Color(0xff52776b);
  static const label = Color(0xff244e42);
}
