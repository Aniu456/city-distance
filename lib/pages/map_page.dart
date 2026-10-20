import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../animations/map_camera.dart';
import '../data/city_repository.dart';
import '../data/map_repository.dart';
import '../models/city.dart';
import '../models/map_region.dart';
import '../theme/app_colors.dart';
import '../utils/map_detail_level.dart';
import '../utils/map_focus.dart';
import '../utils/map_hit_test.dart';
import '../utils/map_projection.dart';
import '../utils/map_tap_target.dart';
import '../widgets/city_details.dart';
import '../widgets/city_picker.dart';
import '../widgets/map_painter.dart';
import '../widgets/snap_sheet.dart';

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> with SingleTickerProviderStateMixin {
  late final _repository = MapRepository(isRetained: _isMapDataInUse);
  final _cities = CityRepository();
  City? _origin;
  City? _destination;
  bool _showDetails = false;

  final _transform = TransformationController();

  /// 下级边界数据加载完成时递增，只通知地图层重绘，不重建整页。
  final _mapData = ValueNotifier<int>(0);
  List<MapRegion> _provinces = [];
  Timer? _debounce;

  /// 上次按视野加载下级数据的时间；拖动过程中按此节流，不必等手势停下。
  final _sinceLoad = Stopwatch();
  Size _viewport = Size.zero;

  /// 整个全国边界恰好放入视口的缩放，所有相对倍数以它为 1×。
  double _fitScale = 1;

  /// 手指或按钮最多缩小到的缩放。
  double _minScale = 1;

  /// 相机仍停在默认视角、用户尚未操作；此时视口尺寸变化会重新计算默认视角。
  bool _atHome = true;

  /// 缩放按钮每次的倍数。
  static const _zoomStep = 1.35;

  /// 手机默认视角等于全国视图连续点击“放大”的次数。
  static const _mobileHomeSteps = 3;

  /// 点击城市标记的命中半径，屏幕逻辑像素。
  static const _markerHitRadius = 14.0;

  /// 最近一帧绘制地图的画笔，点击判定复用它的标签和标记结果。
  MapPainter? _painter;
  bool _loading = true;

  /// 全国地图或城市资料加载失败；重试会重新加载全国数据。
  String? _initialError;

  /// 视野内下级边界加载失败；只由下级加载自身设置和清除。
  String? _regionError;
  MapFocus? _focus;

  /// [_focus] 来自点击省份/区域或选择器的“省”列，而非选中城市：
  /// 不加绿色高亮，用户一拖动或缩放就让位给跟随视口的聚焦。
  bool _softFocus = false;

  /// 底部三列选择器正在为出发地（true）或目的地（false）选择；null 表示收起。
  bool? _pickingOrigin;
  int _request = 0;
  late final _camera = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  )..addListener(_onCameraTick);
  MapCamera? _cameraFrom;
  MapCamera? _cameraTo;
  int _depth = 0;

  double get _scale => _transform.value.getMaxScaleOnAxis();
  double get _zoom => _scale / _fitScale;

  Rect get _nationalBounds => _provinces.isEmpty
      ? Offset.zero & mapSize
      : _provinces
            .map((region) => region.bounds)
            .reduce((bounds, next) => bounds.expandToInclude(next));

  /// 手机布局与页面的宽屏断点一致。
  bool get _isMobile => MediaQuery.sizeOf(context).width < 760;

  void _updateFitScale() {
    final bounds = _nationalBounds;
    final fitHeight = math.max(1, _viewport.height - 48) / bounds.height;
    _fitScale = math.min(
      math.max(1, _viewport.width - (_viewport.width < 500 ? 32 : 80)) /
          bounds.width,
      fitHeight,
    );
    // 竖屏手机按宽度放下全国时上下大片留白；最小缩放改为全国撑满视口高度，
    // 南北完整可见、左右可拖动，不会缩到四周空荡的小图。宽屏仍可看全国。
    _minScale = _isMobile
        ? math.min(math.max(_fitScale, fitHeight), _homeCamera.scale)
        : _fitScale;
  }

  /// 默认视角：手机为全国视图按“放大”按钮逻辑连续放大三次，宽屏为全国视图。
  MapCamera get _homeCamera {
    var camera = (center: _nationalBounds.center, scale: _fitScale);
    if (_isMobile) {
      for (var step = 0; step < _mobileHomeSteps; step++) {
        camera = _zoomedCamera(camera, _zoomStep, focus: null);
      }
    }
    return camera;
  }

  Rect get _view => Rect.fromPoints(
    _transform.toScene(Offset.zero),
    _transform.toScene(_viewport.bottomRight(Offset.zero)),
  );

  @override
  void initState() {
    super.initState();
    _transform.addListener(_onTransform);
    unawaited(_loadNational());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _camera.dispose();
    _transform.removeListener(_onTransform);
    _transform.dispose();
    _mapData.dispose();
    super.dispose();
  }

  Future<void> _loadNational() async {
    setState(() {
      _loading = true;
      _initialError = null;
    });
    try {
      final provinces = await _repository.load('100000');
      await _cities.load();
      if (!mounted) {
        return;
      }
      setState(() {
        _provinces = provinces;
        _loading = false;
      });
      if (!_viewport.isEmpty) {
        _updateFitScale();
        _reset();
      }
    } catch (error, stack) {
      debugPrint('加载全国地图失败: $error\n$stack');
      if (mounted) {
        setState(() {
          _loading = false;
          _initialError = '地图或城市资料加载失败，请重试';
        });
      }
    }
  }

  void _onTransform() {
    if (!mounted) {
      return;
    }
    // 以可见范围决定细节，而非相对全国视图的倍数。
    // 进入与退出阈值不同；拖动不会改变层级，轻微缩放不会反复跳层。
    if (!_viewport.isEmpty) {
      final depth = mapDetailDepth(
        previous: _depth,
        visibleSpan: math.max(_viewport.width, _viewport.height) / _scale,
      );
      // 平移和缩放的每一帧只重绘地图层（见 [_map] 中的 ListenableBuilder）；
      // 层级变化会影响页面其余部分（点击判定等），才重建整页。
      if (depth != _depth) {
        setState(() => _depth = depth);
      }
    }
    // 不在此递增 [_request]：每帧递增会让进行中的逐级加载在下一层前被丢弃，
    // 新的 [_loadVisible] 调用自会取代旧请求。
    _debounce?.cancel();
    if (!_sinceLoad.isRunning ||
        _sinceLoad.elapsed > const Duration(milliseconds: 250)) {
      // 平移中每 250ms 最多加载一次，进入视野的省份很快出现市界。
      _sinceLoad
        ..reset()
        ..start();
      unawaited(_loadVisible());
    }
    _debounce = Timer(const Duration(milliseconds: 100), () {
      unawaited(_loadVisible());
    });
  }

  Future<void> _loadVisible() async {
    // 全国数据就绪前没有可展开的省份，也不能覆盖全国加载的错误状态。
    if (_provinces.isEmpty) {
      return;
    }
    final request = ++_request;
    final depth = _depth;
    final view = _view;
    Future<void> visit(List<MapRegion> regions, int remaining) async {
      if (remaining == 0) {
        return;
      }
      // 每层取一次聚焦：上一层加载完成后才能知道视口中心落在哪个地级市。
      final focus = _detailFocus;
      await Future.wait(
        regions
            .where(
              (r) =>
                  r.hasChildren &&
                  r.bounds.overlaps(view) &&
                  _canExpand(r, focus),
            )
            .map((r) async {
              final children = await _repository.load(r.code);
              if (mounted && request == _request) {
                await visit(children, remaining - 1);
              }
            }),
      );
    }

    try {
      await visit(_provinces, depth);
      if (mounted && request == _request) {
        if (_regionError == null) {
          _mapData.value++;
        } else {
          setState(() => _regionError = null);
        }
      }
    } catch (error, stack) {
      debugPrint('加载下级地图失败: $error\n$stack');
      if (mounted && request == _request) {
        setState(() => _regionError = '部分区域加载失败，点击重试');
      }
    }
  }

  /// 已缓存的区县边界文件 [code] 是否仍被视野、聚焦或起终点使用，
  /// 使用中的文件不会被仓库淘汰。
  bool _isMapDataInUse(String code) {
    for (final path in [
      ?_focus?.path,
      ?_cityFocus(_origin)?.path,
      ?_cityFocus(_destination)?.path,
    ]) {
      if (path.contains(code)) {
        return true;
      }
    }
    final region = _repository.region(code);
    return region != null && region.bounds.overlaps(_view);
  }

  /// 当前应绘制的区域；[focus] 为本次计算统一使用的细节聚焦。
  List<MapRegion> _displayedRegions(MapFocus? focus) {
    final result = <MapRegion>[];
    final view = _view.inflate(20 / _scale);
    void visit(List<MapRegion> regions, int remaining) {
      for (final region in regions) {
        if (!region.bounds.overlaps(view)) {
          continue;
        }
        final children = _repository.cached(region.code);
        if (remaining > 0 &&
            children != null &&
            region.hasChildren &&
            _canExpand(region, focus)) {
          visit(children, remaining - 1);
        } else {
          result.add(region);
        }
      }
    }

    visit(_provinces, _depth);
    return result;
  }

  /// 视野内的省份都可展开到地级市（非聚焦省份淡化显示）；
  /// 更深的区县只在细节聚焦路径上展开，避免满屏区县。
  ///
  /// [focus] 由调用方计算一次后传入，避免逐个区域重复做视口中心命中测试。
  bool _canExpand(MapRegion region, MapFocus? focus) =>
      region.level == 'province' ||
      (focus?.includes(region.code, _repository.parentOf) ?? false);

  /// 完整显示细节的聚焦：选中城市时为选中区域，否则跟随视口中心所在的省份，
  /// 放大到区县层级时再细化到中心所在的地级市。
  MapFocus? get _detailFocus => _focus ?? _viewFocus;

  MapFocus? get _viewFocus {
    if (_viewport.isEmpty || _provinces.isEmpty) {
      return null;
    }
    final center = _transform.toScene(_viewport.center(Offset.zero));
    final province = regionAt(
      _provinces.where((region) => region.level == 'province').toList(),
      center,
    );
    if (province == null) {
      return null;
    }
    final children = _depth >= 2 ? _repository.cached(province.code) : null;
    final city = children == null ? null : regionAt(children, center);
    return MapFocus([province.code, if (city != null) city.code]);
  }

  MapFocus? _cityFocus(City? city) {
    if (city == null) {
      return null;
    }
    return MapFocus([
      city.provinceCode,
      if (city.code != city.provinceCode) city.code,
    ]);
  }

  /// 设置聚焦并补齐路径上级的边界数据，供下钻和相机定位使用。
  void _setFocus(MapFocus? focus) {
    _focus = focus;
    _softFocus = false;
    if (focus == null) {
      return;
    }
    unawaited(() async {
      try {
        for (final code in focus.path.take(focus.path.length - 1)) {
          await _repository.load(code);
        }
      } catch (error, stack) {
        debugPrint('加载聚焦区域失败: $error\n$stack');
      }
      if (mounted && _focus == focus) {
        setState(() {});
        await _loadVisible();
      }
    }());
  }

  /// 恰好容纳聚焦区域的相机；边界尚未加载时退回城市坐标。
  MapCamera? get _focusCamera {
    final focus = _focus;
    if (focus == null || _viewport.isEmpty) {
      return null;
    }
    final region = _repository.region(focus.code);
    if (region == null) {
      for (final city in _cities.cities) {
        if (city.code == focus.code) {
          return (center: city.point, scale: _fitScale * 8);
        }
      }
      return null;
    }
    return _fitCamera(region.bounds);
  }

  MapCamera _fitCamera(Rect bounds) => (
    center: bounds.center,
    scale: math.min(
      _viewport.width * 0.78 / math.max(bounds.width, 1e-6),
      _viewport.height * 0.78 / math.max(bounds.height, 1e-6),
    ),
  );

  void _applyCamera(MapCamera camera) {
    final translation =
        _viewport.center(Offset.zero) - camera.center * camera.scale;
    _transform.value = Matrix4.identity()
      ..translateByDouble(translation.dx, translation.dy, 0, 1)
      ..scaleByDouble(camera.scale, camera.scale, camera.scale, 1);
  }

  void _onCameraTick() {
    final from = _cameraFrom;
    final to = _cameraTo;
    if (from == null || to == null) {
      return;
    }
    final t = Curves.easeInOutCubic.transform(_camera.value);
    _applyCamera(lerpMapCamera(from, to, t));
  }

  void _setCamera(Offset center, double scale, {bool animate = false}) {
    final target = (
      center: center,
      scale: scale.clamp(_minScale, _fitScale * 160).toDouble(),
    );
    // 任何程序化移动都离开默认视角；[_reset] 在之后重新标记。
    _atHome = false;
    _camera.stop();
    if (!animate || _viewport.isEmpty) {
      _applyCamera(target);
      return;
    }
    _cameraFrom = (
      center: _transform.toScene(_viewport.center(Offset.zero)),
      scale: _scale,
    );
    _cameraTo = target;
    unawaited(_camera.forward(from: 0));
  }

  void _reset({bool animate = false}) {
    _focus = null;
    final home = _homeCamera;
    _setCamera(home.center, home.scale, animate: animate);
    _atHome = true;
  }

  /// “放大 / 缩小”按钮从 [from] 出发的下一个相机；默认视角也由它推导。
  /// 缩放下限用全国视图而非 [_minScale]，避免默认视角依赖下限、下限又依赖默认视角。
  MapCamera _zoomedCamera(
    MapCamera from,
    double factor, {
    required MapCamera? focus,
  }) {
    final scale = (from.scale * factor)
        .clamp(_fitScale, _fitScale * 160)
        .toDouble();
    if (focus == null) {
      return (center: from.center, scale: scale);
    }
    return (
      center: focusZoomCenter(
        current: from.center,
        focus: focus.center,
        national: _nationalBounds.center,
        scale: scale,
        fitScale: _fitScale,
        focusScale: focus.scale,
        zoomingIn: factor > 1,
      ),
      scale: scale,
    );
  }

  void _zoomBy(double factor) {
    // 连续点击时以上一次动画的终点为起点，倍数不会被动画中途打断吃掉。
    final running = _camera.isAnimating ? _cameraTo : null;
    final from =
        running ??
        (
          center: _transform.toScene(_viewport.center(Offset.zero)),
          scale: _scale,
        );
    final next = _zoomedCamera(from, factor, focus: _focusCamera);
    _setCamera(next.center, next.scale, animate: true);
  }

  void _select(Offset position) {
    final point = _transform.toScene(position);
    // 与绘制共用同一份标签和标记结果：只能点中屏幕上可见的城市。
    final nearest = _painter?.cityAt(point, radius: _markerHitRadius / _scale);
    if (nearest != null) {
      _chooseFromMap(nearest);
      return;
    }
    final region = regionAt(_displayedRegions(_detailFocus), point);
    if (region == null) {
      return;
    }
    final matches = _cities.cities.where((city) => city.code == region.code);
    if (matches.isNotEmpty) {
      _chooseFromMap(matches.first);
      return;
    }
    // 点击省份或区县：暂时聚焦该区域并移动镜头，之后拖动即跟随视口。
    setState(() {
      _setFocus(MapFocus(_repository.pathTo(region.code)));
      _softFocus = true;
    });
    final camera = _fitCamera(region.bounds);
    _setCamera(
      camera.center,
      math.max(camera.scale, _fitScale * 3.2),
      animate: true,
    );
  }

  bool get _mapTapFillsOrigin => mapTapFillsOrigin(
    pickingOrigin: _pickingOrigin,
    hasOrigin: _origin != null,
    hasDestination: _destination != null,
  );

  void _chooseFromMap(City city) => _pickCity(city, origin: _mapTapFillsOrigin);

  void _chooseDestination(City city) {
    setState(() {
      _destination = city;
      _setFocus(_cityFocus(city));
      _showDetails = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _fitTrip();
      }
    });
  }

  void _togglePicker({required bool origin}) {
    setState(() {
      _pickingOrigin = _pickingOrigin == origin ? null : origin;
      // 选择器收起后详情面板重建为摘要状态。
    });
  }

  void _focusRegion(MapFocus focus, Rect? bounds) {
    setState(() => _setFocus(focus));
    if (bounds != null) {
      final camera = _fitCamera(bounds);
      _setCamera(camera.center, camera.scale, animate: true);
    }
  }

  void _pickCity(City city, {required bool origin}) {
    if (!origin) {
      _chooseDestination(city);
      return;
    }
    setState(() {
      _origin = city;
      _setFocus(_cityFocus(city));
    });
    if (_destination != null && _showDetails) {
      _fitTrip();
    } else {
      final region = _repository.region(city.code);
      _setCamera(
        region?.bounds.center ?? city.point,
        region == null ? _fitScale * 4 : _fitCamera(region.bounds).scale,
        animate: true,
      );
    }
  }

  /// [city] 的下级区县。先加载所在省份以取得 `hasChildren`，
  /// 东莞、中山等不设区县的城市返回空列表，不请求不存在的文件。
  Future<List<MapRegion>> _counties(City city) async {
    if (city.code == city.provinceCode) {
      // 直辖市等省级城市：省级文件本身就是区县列表。
      return _repository.load(city.code);
    }
    await _repository.load(city.provinceCode);
    final region = _repository.region(city.code);
    if (region == null || !region.hasChildren) {
      return const [];
    }
    return _repository.load(city.code);
  }

  Widget _picker({required bool origin}) {
    return CityPicker(
      key: ValueKey(origin ? 'origin-picker' : 'destination-picker'),
      title: origin ? '选择出发城市' : '选择目的城市',
      provinces: _provinces
          .where((region) => region.level == 'province')
          .toList(),
      cities: _cities.cities,
      initial: origin ? _origin : _destination,
      loadCounties: _counties,
      onProvince: (province) {
        _focusRegion(MapFocus([province.code]), province.bounds);
        _softFocus = true;
      },
      onCity: (city) => _pickCity(city, origin: origin),
      onCounty: (city, county) => _focusRegion(
        MapFocus([...?_cityFocus(city)?.path, county.code]),
        county.bounds,
      ),
      onClose: () => setState(() {
        _pickingOrigin = null;
      }),
    );
  }

  void _fitTrip() {
    final destination = _destination;
    if (destination == null || _viewport.isEmpty) {
      return;
    }
    final origin = _origin;
    if (origin == null || origin.code == destination.code) {
      _setCamera(destination.point, _fitScale * 4);
      return;
    }
    final bounds = Rect.fromPoints(origin.point, destination.point).inflate(30);
    final scale = math.min(
      _viewport.width * 0.72 / bounds.width,
      _viewport.height * 0.72 / bounds.height,
    );
    _setCamera(bounds.center, scale);
  }

  Widget _cityField({required bool origin}) {
    final city = origin ? _origin : _destination;
    // 当前字段即地图点击会填入的字段，用描边和标签色标出。
    final active = _mapTapFillsOrigin == origin;
    return Expanded(
      child: Semantics(
        button: true,
        selected: active,
        label: origin ? '选择出发城市' : '选择目的城市',
        child: InkWell(
          key: ValueKey(origin ? 'origin-field' : 'destination-field'),
          onTap: _loading ? null : () => _togglePicker(origin: origin),
          borderRadius: BorderRadius.circular(10),
          // 两块字段几何完全相同，激活态只改变底色和边框颜色，切换时不位移。
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              color: active
                  ? AppColors.primary.withValues(alpha: 0.07)
                  : AppColors.mapBackground.withValues(alpha: 0.7),
              border: Border.all(
                color: active
                    ? AppColors.primary
                    : AppColors.regionBorder.withValues(alpha: 0.18),
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            // 两侧等宽且内容居中，交换按钮恰好位于卡片中线。
            child: Column(
              children: [
                Text(
                  origin ? '出发城市' : '目的城市',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: active ? AppColors.primary : AppColors.hintText,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  city?.name ?? (origin ? '从哪里出发' : '想去哪里'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: city == null
                        ? AppColors.placeholder
                        : AppColors.label,
                    fontWeight: city == null
                        ? FontWeight.w400
                        : FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _controls({bool compact = false}) => Padding(
    // 四周等距：两块字段到卡片边缘的距离一致。
    padding: const EdgeInsets.all(10),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          key: const ValueKey('trip-fields'),
          children: [
            _cityField(origin: true),
            // 交换按钮居中于两块字段之间的间隙，不压住任何一侧边框。
            const SizedBox(width: 8),
            IconButton(
              tooltip: '交换出发地和目的地',
              style: IconButton.styleFrom(
                shape: const CircleBorder(),
                minimumSize: const Size(48, 48),
                maximumSize: const Size(48, 48),
                padding: EdgeInsets.zero,
                foregroundColor: AppColors.primary,
                disabledForegroundColor: AppColors.placeholder,
                backgroundColor: AppColors.mapBackground,
                disabledBackgroundColor: AppColors.mapBackground,
              ),
              onPressed: _origin == null || _destination == null
                  ? null
                  : () {
                      setState(() {
                        final previous = _origin;
                        _origin = _destination;
                        _destination = previous;
                        _setFocus(_cityFocus(_destination));
                      });
                      _fitTrip();
                    },
              icon: const Icon(Icons.swap_horiz, size: 24),
            ),
            const SizedBox(width: 8),
            _cityField(origin: false),
          ],
        ),
        if (!compact) ...[
          const SizedBox(height: 4),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _destination == null
                  ? null
                  : () => _chooseDestination(_destination!),
              child: const Text('查看耗时与城市'),
            ),
          ),
        ],
      ],
    ),
  );

  Widget _details({
    ScrollController? controller,
    VoidCallback? onToggle,
    ValueListenable<double>? expansion,
  }) {
    final destination = _destination;
    if (destination == null) {
      return const SizedBox.shrink();
    }
    return CityDetails(
      key: ValueKey(destination.code),
      origin: _origin,
      destination: destination,
      profile: _cities.profiles[destination.code],
      rent: _cities.rents[destination.name],
      onClose: () => setState(() {
        _showDetails = false;
      }),
      onExpand: onToggle,
      controller: controller,
      expansion: expansion,
    );
  }

  Widget _map() => LayoutBuilder(
    builder: (context, constraints) {
      final size = constraints.biggest;
      if (size != _viewport) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || size == _viewport) {
            return;
          }
          final hadViewport = !_viewport.isEmpty;
          final oldCenter = _transform.toScene(_viewport.center(Offset.zero));
          final oldZoom = _zoom;
          _viewport = size;
          _updateFitScale();
          // 未操作过的默认视角按新视口重新计算；已操作则保持中心和相对倍数。
          if (hadViewport && !_atHome) {
            _setCamera(oldCenter, oldZoom * _fitScale);
          } else {
            _reset();
          }
        });
      }
      return Stack(
        children: [
          Positioned.fill(
            child: ColoredBox(
              color: AppColors.mapBackground,
              child: GestureDetector(
                onTapUp: (details) => _select(details.localPosition),
                child: InteractiveViewer(
                  transformationController: _transform,
                  onInteractionStart: (_) {
                    _camera.stop();
                    _atHome = false;
                    if (_softFocus) {
                      _focus = null;
                      _softFocus = false;
                    }
                  },
                  constrained: false,
                  minScale: _minScale,
                  maxScale: _fitScale * 160,
                  boundaryMargin: const EdgeInsets.all(1400),
                  trackpadScrollCausesScale: true,
                  child: ListenableBuilder(
                    listenable: Listenable.merge([_transform, _mapData]),
                    builder: (context, _) => _mapPaint(),
                  ),
                ),
              ),
            ),
          ),
          if (_loading) const Center(child: CircularProgressIndicator()),
          if (_initialError ?? _regionError case final error?)
            Center(
              child: FilledButton.tonalIcon(
                onPressed: () => unawaited(
                  _initialError != null ? _loadNational() : _loadVisible(),
                ),
                icon: const Icon(Icons.refresh),
                label: Text(error),
              ),
            ),
        ],
      );
    },
  );

  /// 地图画布；随镜头每帧重建，依赖镜头的数据都在这里计算。
  ///
  /// 最近一次的画笔保存在 [_painter]，点击判定与它看到的画面一致。
  Widget _mapPaint() {
    final focus = _focus;
    final detail = _detailFocus;
    final regions = _displayedRegions(detail);
    final painter = _painter = MapPainter(
      regions: regions,
      provinces: _provinces,
      cityBoundaries: [
        for (final province in _provinces)
          if (province.bounds.overlaps(_view))
            ...?_repository.cached(province.code),
      ],
      scale: _scale,
      view: _view,
      // 绿色填充只表示真实选择；未选城市时不高亮任何区域。
      highlighted: {
        if (focus != null && !_softFocus) ...[
          ...focus.path,
          for (final region in regions)
            if (focus.includes(region.code, _repository.parentOf)) region.code,
        ],
      },
      detailProvinces: detail == null ? null : {detail.provinceCode},
      cities: _cities.cities,
      showCities: _depth >= 1,
      showDistricts: _depth >= 2,
      fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily,
      origin: _origin,
      destination: _destination,
      parentOf: _repository.parentOf,
    );
    return CustomPaint(size: mapSize, painter: painter);
  }

  Widget _mapArea({bool mobile = false}) => Column(
    children: [
      Expanded(
        child: ColoredBox(
          color: AppColors.mapBackground,
          child: Stack(
            children: [
              Positioned.fill(
                // 控件拥有独立侧边留白，不覆盖地图可交互区域。
                child: Padding(
                  padding: EdgeInsets.fromLTRB(8, 8, mobile ? 8 : 52, 8),
                  child: _map(),
                ),
              ),
              if (!mobile)
                Positioned(
                  right: 6,
                  bottom: 8,
                  child: Material(
                    elevation: 3,
                    shadowColor: const Color(0x40244e42),
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(10),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _mapButton(
                          '返回全国',
                          Icons.public,
                          () => _reset(animate: true),
                        ),
                        _mapButton('放大', Icons.add, () => _zoomBy(_zoomStep)),
                        _mapButton(
                          '缩小',
                          Icons.remove,
                          () => _zoomBy(1 / _zoomStep),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      Container(
        key: const ValueKey('map-hint'),
        width: double.infinity,
        color: mobile ? AppColors.mapBackground : AppColors.background,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _origin != null && _destination != null
                    ? '虚线为两地示意连线'
                    : _mapTapFillsOrigin
                    ? '点选地图城市设为出发地\n放大查看地级市与区县'
                    : '点选地图城市设为目的地\n放大查看地级市与区县',
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  color: AppColors.label,
                ),
              ),
            ),
            if (mobile) ...[
              const SizedBox(width: 8),
              Material(
                elevation: 2,
                shadowColor: const Color(0x30244e42),
                color: AppColors.background,
                borderRadius: BorderRadius.circular(12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _mapButton(
                      '返回全国',
                      Icons.public,
                      () => _reset(animate: true),
                    ),
                    _mapButton(
                      '缩小',
                      Icons.remove,
                      () => _zoomBy(1 / _zoomStep),
                    ),
                    _mapButton('放大', Icons.add, () => _zoomBy(_zoomStep)),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    ],
  );

  Widget _mapButton(String tooltip, IconData icon, VoidCallback onPressed) =>
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(child: _content()),
            // 城市选择器停靠在底部，不遮挡地图，选择结果即时反映到地图聚焦。
            if (_pickingOrigin case final origin?) _picker(origin: origin),
          ],
        ),
      ),
    );
  }

  Widget _content() {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 760) {
          return Row(
            children: [
              SizedBox(
                width: 350,
                child: Column(
                  children: [
                    _controls(),
                    if (_showDetails)
                      Expanded(child: _details())
                    else
                      const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 22,
                          vertical: 20,
                        ),
                        child: Text(
                          '选一座想去的城市，看看路上要多久、当地做什么、生活花多少。',
                          style: TextStyle(
                            color: AppColors.hintText,
                            height: 1.6,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: _mapArea()),
            ],
          );
        }
        final showSheet =
            _showDetails && _pickingOrigin == null && _destination != null;
        final sheetHeight = math.min(236.0, constraints.maxHeight * 0.42);
        return ColoredBox(
          color: AppColors.mapBackground,
          child: Column(
            children: [
              Padding(
                // 卡片与下方地图留出与左右一致的间距。
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                child: Material(
                  color: AppColors.background,
                  elevation: 2,
                  shadowColor: const Color(0x30244e42),
                  borderRadius: BorderRadius.circular(16),
                  child: _controls(compact: true),
                ),
              ),
              Expanded(
                child: Stack(
                  children: [
                    // 收起的面板占用固定高度，地图与缩放按钮始终在其上方可用；
                    // 展开时面板覆盖地图显示完整详情。
                    Positioned.fill(
                      child: Column(
                        children: [
                          Expanded(child: _mapArea(mobile: true)),
                          if (showSheet) SizedBox(height: sheetHeight),
                        ],
                      ),
                    ),
                    if (showSheet)
                      Positioned.fill(
                        child: SnapSheet(
                          key: const ValueKey('details-sheet'),
                          collapsedHeight: sheetHeight,
                          builder: (context, controller, toggle, expansion) =>
                              _details(
                                controller: controller,
                                onToggle: toggle,
                                expansion: expansion,
                              ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
