import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/city.dart';
import '../models/map_region.dart';
import '../theme/app_colors.dart';

/// 停靠在页面底部的省 / 市 / 区县三列联动选择器。
///
/// 省份和区县来自地图 GeoJSON，地级市来自城市目录，因为耗时估算以目录城市为单位。
/// 选中省份筛选城市列，选中城市筛选区县列；每一步都立即回调，供地图同步聚焦。
class CityPicker extends StatefulWidget {
  const CityPicker({
    super.key,
    required this.title,
    required this.provinces,
    required this.cities,
    required this.loadCounties,
    required this.onProvince,
    required this.onCity,
    required this.onCounty,
    required this.onClose,
    this.initial,
  });

  final String title;
  final List<MapRegion> provinces;
  final List<City> cities;

  /// 当前已选城市；打开时预先选中其省份和城市。
  final City? initial;

  /// 读取城市下一级区县；没有下级时返回空列表。
  /// 加载城市的下级区县；不设区县的城市返回空列表，失败时抛出异常。
  final Future<List<MapRegion>> Function(City city) loadCounties;
  final ValueChanged<MapRegion> onProvince;
  final ValueChanged<City> onCity;
  final void Function(City city, MapRegion county) onCounty;
  final VoidCallback onClose;

  @override
  State<CityPicker> createState() => _CityPickerState();
}

class _CityPickerState extends State<CityPicker> {
  static const _itemExtent = 44.0;
  static const _collapsedHeight = 220.0;

  /// 超过此速度（逻辑像素/秒）的松手视为快速滑动。
  static const _flingVelocity = 300.0;

  /// 当前停靠点；像素高度每次构建时按布局换算，旋转或改变窗口后仍然有效。
  _PickerSnap _snap = _PickerSnap.normal;

  /// 拖动中的列表高度；不在拖动时为 null，高度取自 [_snap]。
  double? _dragHeight;

  bool get _dragging => _dragHeight != null;

  double _heightOf(_PickerSnap snap) => switch (snap) {
    _PickerSnap.minimized => 0,
    _PickerSnap.normal => _collapsedHeight,
    _PickerSnap.expanded => _expandedHeight,
  };

  double get _listHeight => _dragHeight ?? _heightOf(_snap);
  final _provinceScroll = ScrollController();
  final _cityScroll = ScrollController();
  String? _provinceCode;
  City? _city;
  String? _countyCode;
  List<MapRegion> _counties = const [];
  bool _loadingCounties = false;
  bool _countiesFailed = false;

  @override
  void initState() {
    super.initState();
    _syncTo(widget.initial);
  }

  @override
  void didUpdateWidget(CityPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 地图点击改变了当前字段的城市时，三列跟随到对应省市。
    // 只响应外部变化；用户在列中切换省份时不会被拉回原城市。
    final initial = widget.initial;
    if (initial != null &&
        initial.code != oldWidget.initial?.code &&
        initial.code != _city?.code) {
      _syncTo(initial);
    }
  }

  @override
  void dispose() {
    _provinceScroll.dispose();
    _cityScroll.dispose();
    super.dispose();
  }

  void _syncTo(City? city) {
    if (city == null) {
      return;
    }
    _provinceCode = city.provinceCode;
    _city = city;
    _countyCode = null;
    unawaited(_loadCounties(city));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _reveal(
        _provinceScroll,
        widget.provinces.indexWhere((p) => p.code == city.provinceCode),
      );
      _reveal(
        _cityScroll,
        _provinceCities.indexWhere((item) => item.code == city.code),
      );
    });
  }

  /// 滚动到第 [index] 项，使其位于列表可见范围内。
  void _reveal(ScrollController controller, int index) {
    if (index < 0 || !controller.hasClients) {
      return;
    }
    final position = controller.position;
    final top = index * _itemExtent;
    if (top >= position.pixels &&
        top + _itemExtent <= position.pixels + position.viewportDimension) {
      return;
    }
    controller.jumpTo(
      (top - _itemExtent).clamp(0.0, position.maxScrollExtent).toDouble(),
    );
  }

  List<City> get _provinceCities => [
    for (final city in widget.cities)
      if (city.provinceCode == _provinceCode) city,
  ];

  Future<void> _loadCounties(City city) async {
    _counties = const [];
    _loadingCounties = true;
    _countiesFailed = false;
    if (mounted) {
      setState(() {});
    }
    try {
      final counties = await widget.loadCounties(city);
      if (mounted && _city?.code == city.code) {
        setState(() {
          _counties = counties
              .where((county) => county.name.isNotEmpty)
              .toList();
          _loadingCounties = false;
        });
      }
    } catch (error, stack) {
      debugPrint('加载区县失败: $error\n$stack');
      if (mounted && _city?.code == city.code) {
        setState(() {
          _loadingCounties = false;
          _countiesFailed = true;
        });
      }
    }
  }

  void _selectProvince(MapRegion province) {
    setState(() {
      _provinceCode = province.code;
      _city = null;
      _countyCode = null;
      _counties = const [];
      _countiesFailed = false;
    });
    widget.onProvince(province);
  }

  void _selectCity(City city) {
    setState(() {
      _city = city;
      _countyCode = null;
    });
    widget.onCity(city);
    unawaited(_loadCounties(city));
  }

  void _selectCounty(MapRegion county) {
    final city = _city;
    if (city == null) {
      return;
    }
    setState(() => _countyCode = county.code);
    widget.onCounty(city, county);
  }

  double get _expandedHeight =>
      math.max(_collapsedHeight, MediaQuery.sizeOf(context).height * 0.5);

  void _onDragUpdate(DragUpdateDetails details) {
    setState(() {
      _dragHeight = (_listHeight - details.delta.dy).clamp(
        0.0,
        _expandedHeight,
      );
    });
  }

  /// 松手后吸附到最小化（仅标题栏）、常规或展开高度；下滑只会收小，不会关闭，
  /// 关闭只通过“完成”。
  void _onDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    const stops = _PickerSnap.values;
    final height = _listHeight;
    var target = stops.reduce(
      (a, b) => (_heightOf(a) - height).abs() <= (_heightOf(b) - height).abs()
          ? a
          : b,
    );
    if (velocity.abs() > _flingVelocity) {
      // 快速滑动按方向从上次停靠点移到相邻停靠点。
      final next = (_snap.index + (velocity < 0 ? 1 : -1)).clamp(
        0,
        stops.length - 1,
      );
      target = stops[next];
    }
    setState(() {
      _dragHeight = null;
      _snap = target;
    });
  }

  /// 点击把手：最小化时恢复常规高度，否则在常规和展开之间切换。
  void _toggleHeight() {
    setState(() {
      _snap = _snap == _PickerSnap.normal
          ? _PickerSnap.expanded
          : _PickerSnap.normal;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cities = _provinceCities;
    final city = _city;
    return Material(
      key: const ValueKey('city-picker'),
      color: AppColors.background,
      elevation: 6,
      shadowColor: const Color(0x30244e42),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 把手与标题行可上下拖动；三列列表各自滚动，互不抢手势。
          GestureDetector(
            key: const ValueKey('city-picker-handle'),
            behavior: HitTestBehavior.opaque,
            onTap: _toggleHeight,
            onVerticalDragUpdate: _onDragUpdate,
            onVerticalDragEnd: _onDragEnd,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Container(
                    width: 32,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.regionBorder.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 8, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.title,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      TextButton(
                        onPressed: widget.onClose,
                        child: const Text('完成'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          AnimatedContainer(
            key: const ValueKey('city-picker-lists'),
            duration: _dragging
                ? Duration.zero
                : const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            height: _listHeight,
            clipBehavior: Clip.hardEdge,
            decoration: const BoxDecoration(),
            // 收小到仅标题栏时列表按最小高度布局后裁剪，不触发溢出。
            child: LayoutBuilder(
              builder: (context, constraints) => OverflowBox(
                alignment: Alignment.topCenter,
                minHeight: math.max(constraints.maxHeight, 120),
                maxHeight: math.max(constraints.maxHeight, 120),
                child: _lists(cities, city),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _lists(List<City> cities, City? city) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _column(
          key: const ValueKey('picker-provinces'),
          controller: _provinceScroll,
          header: '省',
          empty: '暂无省份',
          children: [
            for (final province in widget.provinces)
              _option(
                key: ValueKey('picker-province-${province.code}'),
                text: province.name,
                selected: province.code == _provinceCode,
                onTap: () => _selectProvince(province),
              ),
          ],
        ),
        _divider(),
        _column(
          key: const ValueKey('picker-cities'),
          controller: _cityScroll,
          header: '市',
          empty: _provinceCode == null ? '先选省份' : '暂无城市资料',
          children: [
            for (final item in cities)
              _option(
                key: ValueKey('picker-city-${item.code}'),
                text: item.name,
                selected: item.code == city?.code,
                onTap: () => _selectCity(item),
              ),
          ],
        ),
        _divider(),
        _column(
          key: const ValueKey('picker-counties'),
          header: '区县',
          empty: city == null
              ? '先选城市'
              : _loadingCounties
              ? '加载中…'
              : _countiesFailed
              ? '区县加载失败'
              : '无下级区县',
          children: [
            for (final county in _counties)
              _option(
                key: ValueKey('picker-county-${county.code}'),
                text: county.name,
                selected: county.code == _countyCode,
                onTap: () => _selectCounty(county),
              ),
          ],
        ),
      ],
    );
  }

  Widget _divider() => const VerticalDivider(
    width: 1,
    thickness: 1,
    color: AppColors.mapBackground,
  );

  Widget _column({
    required Key key,
    ScrollController? controller,
    required String header,
    required String empty,
    required List<Widget> children,
  }) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 6, 8, 4),
          child: Text(
            header,
            style: const TextStyle(fontSize: 12, color: AppColors.hintText),
          ),
        ),
        Expanded(
          child: children.isEmpty
              ? Center(
                  child: Text(
                    empty,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.placeholder,
                    ),
                  ),
                )
              : ListView(
                  key: key,
                  controller: controller,
                  itemExtent: _itemExtent,
                  children: children,
                ),
        ),
      ],
    ),
  );

  Widget _option({
    required Key key,
    required String text,
    required bool selected,
    required VoidCallback onTap,
  }) => InkWell(
    key: key,
    onTap: onTap,
    child: Container(
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      color: selected ? AppColors.mapBackground : null,
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 14,
          color: selected ? AppColors.primary : AppColors.label,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
    ),
  );
}

/// 选择器列表的停靠点，从低到高排列。
enum _PickerSnap {
  /// 只剩把手和标题栏。
  minimized,

  /// 默认高度。
  normal,

  /// 约占屏幕一半。
  expanded,
}
