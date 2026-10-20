import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:china_map/animations/map_camera.dart';
import 'package:china_map/main.dart';
import 'package:china_map/theme/app_colors.dart';
import 'package:china_map/utils/map_projection.dart';
import 'package:china_map/widgets/city_details.dart';
import 'package:china_map/widgets/map_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _previewKey = ValueKey('preview');
final _previewDir = Platform.environment['MAP_PREVIEW_DIR'];

Future<void> preloadAssets(WidgetTester tester) async {
  await tester.runAsync(() async {
    for (final directory in ['assets/maps', 'assets/cities']) {
      for (final file in Directory(directory).listSync()) {
        if (file.path.endsWith('.json')) {
          await rootBundle.loadString(file.path);
        }
      }
    }
    final fontPath = Platform.environment['MAP_PREVIEW_FONT'];
    if (_previewDir != null && fontPath != null) {
      final icons = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await icons.load();
      final bytes = File(fontPath).readAsBytesSync();
      for (final family in ['Ahem', 'Roboto']) {
        final loader = FontLoader(family)
          ..addFont(Future.value(ByteData.sublistView(bytes)));
        await loader.load();
      }
    }
  });
}

Future<void> settleMap(WidgetTester tester) async {
  // 先等 320ms 的相机动画结束，再越过加载防抖并让真实 IO 完成。
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 150));
  await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
  });
  await tester.pumpAndSettle();
}

Future<void> start(
  WidgetTester tester, {
  Size size = const Size(1200, 800),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await preloadAssets(tester);
  await tester.pumpWidget(
    const RepaintBoundary(key: _previewKey, child: ChinaMapApp()),
  );
  await settleMap(tester);
  expect(find.byType(CircularProgressIndicator), findsNothing);
  expect(find.textContaining('加载失败'), findsNothing);
}

MapPainter painter(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((widget) => widget.painter)
    .whereType<MapPainter>()
    .single;

final _catalog = [
  for (final raw in jsonDecode(
    File('assets/cities/catalog.json').readAsStringSync(),
  ) as List<Object?>)
    raw as Map<String, Object?>,
];

Future<void> tapPickerOption(
  WidgetTester tester,
  String list,
  String key,
) async {
  final option = find.byKey(ValueKey(key));
  final scrollable = find.descendant(
    of: find.byKey(ValueKey(list)),
    matching: find.byType(Scrollable),
  );
  // 选择器会滚到当前城市所在省份，先回到顶部再向下查找。
  tester.state<ScrollableState>(scrollable).position.jumpTo(0);
  await tester.pump();
  await tester.scrollUntilVisible(option, 80, scrollable: scrollable);
  await tester.ensureVisible(option);
  await tester.pumpAndSettle();
  await tester.tap(option);
  await settleMap(tester);
}

/// 通过底部三列选择器依次点省份和城市，再收起选择器。
Future<void> selectCity(WidgetTester tester, String field, String city) async {
  final entry = _catalog.firstWhere((item) => item['name'] == city);
  // 字段已有城市时占位文字不在，按字段键点击。
  final key = field == '从哪里出发' ? 'origin-field' : 'destination-field';
  await tester.tap(find.byKey(ValueKey(key)));
  await tester.pumpAndSettle();
  await tapPickerOption(
    tester,
    'picker-provinces',
    'picker-province-${entry['provinceCode']}',
  );
  await tapPickerOption(
    tester,
    'picker-cities',
    'picker-city-${entry['code']}',
  );
  await tester.tap(find.text('完成'));
  await settleMap(tester);
}

Future<void> preview(WidgetTester tester, String name) async {
  final directory = _previewDir;
  if (directory == null) {
    return;
  }
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_previewKey),
    );
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(directory).create(recursive: true);
    await File('$directory/$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

double sheetScrollOffset(WidgetTester tester) => tester
    .state<ScrollableState>(
      find
          .descendant(
            of: find.byType(CityDetails),
            matching: find.byType(Scrollable),
          )
          .first,
    )
    .position
    .pixels;

/// 点击地图上城市所在位置。
Future<void> tapCityOnMap(WidgetTester tester, String name) async {
  final finder = find.byType(InteractiveViewer);
  final controller = tester
      .widget<InteractiveViewer>(finder)
      .transformationController!;
  final city = painter(tester).cities.firstWhere((item) => item.name == name);
  final local = MatrixUtils.transformPoint(controller.value, city.point);
  final global = tester.getTopLeft(finder) + local;
  expect(tester.getRect(finder).contains(global), isTrue, reason: name);
  await tester.tapAt(global);
  await settleMap(tester);
}

String fieldText(WidgetTester tester, String key) => tester
    .widgetList<Text>(
      find.descendant(
        of: find.byKey(ValueKey(key)),
        matching: find.byType(Text),
      ),
    )
    .last
    .data!;

Color? fieldLabelColor(WidgetTester tester, String key) => tester
    .widgetList<Text>(
      find.descendant(
        of: find.byKey(ValueKey(key)),
        matching: find.byType(Text),
      ),
    )
    .first
    .style
    ?.color;

void main() {
  testWidgets('精简首页保留全部层级和省会标记', (tester) async {
    await start(tester);
    expect(find.text('从哪里出发'), findsOneWidget);
    expect(find.text('想去哪里'), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('从哪里出发')).style?.color,
      AppColors.placeholder,
    );
    final swapSize = tester.getSize(find.byTooltip('交换出发地和目的地'));
    expect(swapSize.width, greaterThanOrEqualTo(48));
    expect(swapSize.height, greaterThanOrEqualTo(48));
    final initial = painter(tester);
    expect(
      initial.layoutLabels().every((label) => label.priority == 1),
      isTrue,
    );
    for (final name in ['天津', '济南']) {
      expect(initial.layoutLabels().any((label) => label.text == name), isTrue);
    }
    expect(
      painter(tester).cities.where((city) => city.isCapital),
      hasLength(34),
    );
    expect(painter(tester).regions.any((r) => r.level == 'province'), isTrue);
    await preview(tester, 'desktop-map');
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.byTooltip('放大'));
      await settleMap(tester);
    }
    expect(painter(tester).showCities, isFalse);
    for (var i = 0; i < 12 && !painter(tester).showCities; i++) {
      await tester.tap(find.byTooltip('放大'));
      await settleMap(tester);
    }
    expect(painter(tester).regions.any((r) => r.level == 'city'), isTrue);
    for (var i = 0; i < 12 && !painter(tester).showDistricts; i++) {
      await tester.tap(find.byTooltip('放大'));
      await settleMap(tester);
    }
    expect(painter(tester).regions.any((r) => r.level == 'district'), isTrue);
    await tester.tap(find.byTooltip('返回全国'));
    await settleMap(tester);
    expect(painter(tester).regions.any((r) => r.level == 'province'), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('真实省会标记可选作目的地，拖动仍然可用', (tester) async {
    await start(tester);
    final finder = find.byType(InteractiveViewer);
    final viewer = tester.widget<InteractiveViewer>(finder);
    final controller = viewer.transformationController!;
    final guangzhou = painter(tester).cities
        .firstWhere((city) => city.name == '广州');
    final local = MatrixUtils.transformPoint(
      controller.value,
      project(guangzhou.longitude, guangzhou.latitude),
    );
    await tester.tapAt(tester.getTopLeft(finder) + local);
    await settleMap(tester);
    expect(
      tester.widget<CityDetails>(find.byType(CityDetails)).destination.name,
      '广州',
    );
    final before = controller.value.clone();
    await tester.drag(finder, const Offset(80, 40));
    await settleMap(tester);
    expect(controller.value, isNot(before));
    expect(tester.takeException(), isNull);
  });

  testWidgets('选城市显示双列估算、产业租房支出，可交换目的地', (tester) async {
    await start(tester);
    await selectCity(tester, '从哪里出发', '北京');
    await selectCity(tester, '想去哪里', '上海');
    expect(find.text('高铁'), findsOneWidget);
    expect(find.text('普通火车'), findsOneWidget);
    expect(find.text('从 北京 出发'), findsOneWidget);
    expect(find.text('直线约 1067 km · 耗时为距离模型粗估'), findsOneWidget);
    await preview(tester, 'desktop-result');
    final details = tester.widget<CityDetails>(find.byType(CityDetails));
    expect(details.profile?.code, '310000');
    expect(details.rent?.period, '2026-09');
    await tester.tap(find.byTooltip('交换出发地和目的地'));
    await settleMap(tester);
    expect(
      tester.widget<CityDetails>(find.byType(CityDetails)).destination.name,
      '北京',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('手机保留大地图，摘要可展开详情，横竖屏不溢出', (tester) async {
    await start(tester, size: const Size(390, 844));
    final mapRect = tester.getRect(find.byType(InteractiveViewer));
    final controlsRect = tester.getRect(find.byTooltip('放大'));
    final hintRect = tester.getRect(find.byKey(const ValueKey('map-hint')));
    expect(controlsRect.top, greaterThan(mapRect.bottom));
    expect(hintRect.top, greaterThan(mapRect.bottom));
    final initial = painter(tester);
    // 手机默认视角聚焦中东部，标签均在视口内。
    for (final label in initial.layoutLabels()) {
      expect(initial.view.contains(label.bounds.topLeft), isTrue);
      expect(initial.view.contains(label.bounds.bottomRight), isTrue);
    }
    await preview(tester, 'mobile-map');
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.byTooltip('放大'));
      await settleMap(tester);
    }
    expect(painter(tester).showCities, isFalse);
    await preview(tester, 'mobile-wide-map');
    for (var i = 0; i < 10 && !painter(tester).showCities; i++) {
      await tester.tap(find.byTooltip('放大'));
      await settleMap(tester);
    }
    expect(painter(tester).showCities, isTrue);
    expect(painter(tester).showDistricts, isFalse);
    await preview(tester, 'mobile-city-map');
    await tester.tap(find.byTooltip('返回全国'));
    await settleMap(tester);
    await selectCity(tester, '从哪里出发', '成都');
    await selectCity(tester, '想去哪里', '杭州');
    await preview(tester, 'mobile-result');
    expect(find.text('高铁'), findsOneWidget);
    expect(
      tester.getSize(find.byType(InteractiveViewer)).height,
      greaterThan(350),
    );
    final body = find.byKey(const ValueKey('snap-sheet-body'));
    expect(tester.getSize(body).height, lessThan(260));
    await tester.tap(find.text('产业 · 租房 · 生活成本'));
    await tester.pumpAndSettle();
    expect(tester.getSize(body).height, greaterThan(600));
    expect(find.text('产业与工作方向'), findsOneWidget);
    await preview(tester, 'mobile-details');
    final list = find.descendant(
      of: find.byType(CityDetails),
      matching: find.byType(CustomScrollView),
    );
    await tester.drag(list, const Offset(0, -700));
    await tester.pumpAndSettle();
    // 展开后继续上滑滚动内容，面板保持展开。
    expect(tester.getSize(body).height, greaterThan(600));
    expect(sheetScrollOffset(tester), greaterThan(0));
    await preview(tester, 'mobile-costs');
    expect(tester.takeException(), isNull);
    await tester.drag(list, const Offset(0, 700));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('收起城市详情'));
    await tester.pumpAndSettle();
    expect(find.byType(CityDetails), findsNothing);
    tester.view.physicalSize = const Size(320, 640);
    await settleMap(tester);
    expect(tester.takeException(), isNull);
    tester.view.physicalSize = const Size(844, 390);
    await settleMap(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('未收录城市如实显示缺失，不沿用上一城市数据', (tester) async {
    await start(tester);
    await selectCity(tester, '想去哪里', '拉萨');
    final details = tester.widget<CityDetails>(find.byType(CityDetails));
    expect(details.profile, isNull);
    expect(details.rent, isNull);
    // 无数据分区收成一行，不展示上一城市的数据。
    for (final key in ['section-industry', 'section-living']) {
      expect(
        find.descendant(
          of: find.byKey(ValueKey(key)),
          matching: find.text(CityDetails.emptyText),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(ValueKey(key)),
          matching: find.byType(Text),
        ),
        findsNWidgets(2),
      );
    }
    expect(find.textContaining('亿元'), findsNothing);
  });

  testWidgets('展开详情：摘要固定在顶部，三个分区同构，说明合并到底部折叠项', (tester) async {
    await start(tester, size: const Size(393, 852));
    Future<void> expandAndScroll(String name, {bool openFooter = false}) async {
      final body = find.byKey(const ValueKey('snap-sheet-body'));
      await tester.tap(find.text('产业 · 租房 · 生活成本'));
      await tester.pumpAndSettle();
      expect(tester.getSize(body).height, greaterThan(600));
      if (openFooter) {
        // 无数据城市内容较短，展开底部说明后才需要滚动。
        await tester.tap(find.text('估算方式与数据来源'));
        await tester.pumpAndSettle();
      }
      final summary = find.byKey(const ValueKey('city-summary'));
      final top = tester.getRect(summary).top;
      final list = find.descendant(
        of: find.byType(CityDetails),
        matching: find.byType(CustomScrollView),
      );
      await tester.drag(list, const Offset(0, -260));
      await tester.pumpAndSettle();
      expect(sheetScrollOffset(tester), greaterThan(100));
      // 滚动后城市名、出发地和耗时仍在原位。
      expect(tester.getRect(summary).top, closeTo(top, 0.5));
      for (final text in ['武汉', '杭州']) {
        final found = find.descendant(of: summary, matching: find.text(text));
        if (text == name) {
          expect(found, findsOneWidget);
        }
      }
      expect(
        find.descendant(of: summary, matching: find.text('高铁')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: summary, matching: find.text('普通火车')),
        findsOneWidget,
      );
    }

    await selectCity(tester, '从哪里出发', '成都');
    await selectCity(tester, '想去哪里', '杭州');
    await expandAndScroll('杭州');
    for (final key in ['section-industry', 'section-rent', 'section-living']) {
      expect(
        find.descendant(
          of: find.byKey(ValueKey(key)),
          matching: find.text(CityDetails.emptyText),
        ),
        findsNothing,
        reason: key,
      );
    }
    expect(find.text('2025 年 GDP'), findsOneWidget);
    expect(find.text('金融业'), findsOneWidget);
    await preview(tester, 'details-with-data');
    // 合并后的折叠项只有一个，展开后包含粗估说明、估算方式和来源。
    expect(find.text('估算方式'), findsNothing);
    expect(find.text('数据来源与统计口径'), findsNothing);
    final footer = find.text('估算方式与数据来源');
    // 滚到底，避免折叠项停在固定摘要下面。
    final scroll = tester
        .state<ScrollableState>(
          find
              .descendant(
                of: find.byType(CityDetails),
                matching: find.byType(Scrollable),
              )
              .first,
        )
        .position;
    scroll.jumpTo(scroll.maxScrollExtent);
    await tester.pumpAndSettle();
    await tester.tap(footer);
    await tester.pumpAndSettle();
    expect(find.textContaining('按距离模型粗估'), findsOneWidget);
    expect(find.textContaining('绕行系数'), findsOneWidget);
    expect(find.text('数据来源与统计口径'), findsOneWidget);
    expect(find.byTooltip('复制来源链接'), findsNWidgets(2));
    await preview(tester, 'details-footer');

    await tester.tap(find.byTooltip('收起城市详情'));
    await tester.pumpAndSettle();
    await selectCity(tester, '想去哪里', '武汉');
    await expandAndScroll('武汉', openFooter: true);
    for (final key in ['section-industry', 'section-living']) {
      expect(
        find.descendant(
          of: find.byKey(ValueKey(key)),
          matching: find.text(CityDetails.emptyText),
        ),
        findsOneWidget,
        reason: key,
      );
    }
    expect(find.textContaining('元/㎡·月'), findsWidgets);
    await preview(tester, 'details-no-data');
    expect(tester.takeException(), isNull);
  });
  testWidgets('华东连续缩放逐步显示市县，新增标签受密度限制', (tester) async {
    await start(tester, size: const Size(393, 852));
    final viewer = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    final size = tester.getSize(find.byType(InteractiveViewer));
    for (final span in [361.0, 330.0, 240.0, 99.0, 60.0]) {
      final scale = size.height / span;
      final center = project(115, 34);
      final translation = size.center(Offset.zero) - center * scale;
      viewer.transformationController!.value = Matrix4.identity()
        ..translateByDouble(translation.dx, translation.dy, 0, 1)
        ..scaleByDouble(scale, scale, scale, 1);
      await settleMap(tester);
      final labels = painter(tester).layoutLabels();
      expect(labels.length, lessThanOrEqualTo(30));
      for (var i = 0; i < labels.length; i++) {
        for (var j = i + 1; j < labels.length; j++) {
          expect(labels[i].bounds.overlaps(labels[j].bounds), isFalse);
        }
      }
      await preview(tester, 'mobile-east-${span.round()}');
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('底部三列选择西安后放大：区县只下钻西安，邻省市级细节淡化', (tester) async {
    await start(tester, size: const Size(393, 852));
    await tester.tap(find.text('想去哪里'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    final picker = tester.getRect(find.byKey(const ValueKey('city-picker')));
    expect(picker.bottom, closeTo(852, 1));
    final columns = [
      for (final key in [
        'picker-provinces',
        'picker-cities',
        'picker-counties',
      ])
        tester.getRect(
          find
              .ancestor(
                of: find.text(
                  {'picker-provinces': '省', 'picker-cities': '市'}[key] ?? '区县',
                ),
                matching: find.byType(Column),
              )
              .first,
        ),
    ];
    expect(columns[0].right, lessThanOrEqualTo(columns[1].left + 1));
    expect(columns[1].right, lessThanOrEqualTo(columns[2].left + 1));
    expect(find.text('先选省份'), findsOneWidget);
    await tapPickerOption(tester, 'picker-provinces', 'picker-province-610000');
    expect(find.byKey(const ValueKey('picker-city-610100')), findsOneWidget);
    expect(find.byKey(const ValueKey('picker-city-620100')), findsNothing);
    // 只选了省份还没选城市：镜头适配陕西，不加绿色高亮，细节聚焦跟随视口中心。
    expect(painter(tester).highlighted, isEmpty);
    expect(painter(tester).detailProvinces, {'610000'});
    await tapPickerOption(tester, 'picker-cities', 'picker-city-610100');
    expect(find.byKey(const ValueKey('picker-county-610102')), findsOneWidget);
    await preview(tester, 'focus-xian-picker');
    await tester.tap(find.text('完成'));
    await settleMap(tester);
    expect(find.byKey(const ValueKey('city-picker')), findsNothing);
    expect(
      tester.widget<CityDetails>(find.byType(CityDetails)).destination.name,
      '西安',
    );
    await preview(tester, 'focus-xian-selected');
    for (var i = 0; i < 24 && !painter(tester).showDistricts; i++) {
      await tester.tap(find.byTooltip('放大'));
      await settleMap(tester);
      final current = painter(tester);
      expect(current.detailProvinces, {'610000'});
      for (final region in current.regions) {
        // 直辖市的区即其市级，可随邻省一起显示；其余区县只下钻西安。
        final municipality = [
          '11',
          '12',
          '31',
          '50',
        ].any(region.code.startsWith);
        if (region.level == 'district' && !municipality) {
          expect(region.code.startsWith('6101'), isTrue, reason: region.name);
        }
      }
      for (final label in current.layoutLabels()) {
        if (label.priority == 2 && !label.code.startsWith('61')) {
          expect(label.muted, isTrue, reason: label.text);
        }
      }
    }
    final focused = painter(tester);
    expect(focused.showDistricts, isTrue);
    final districts = focused.regions.where((r) => r.level == 'district');
    expect(districts, isNotEmpty);
    for (final region in districts) {
      expect(region.code.startsWith('6101'), isTrue, reason: region.name);
      expect(focused.highlighted, contains(region.code));
    }
    expect(focused.regions.any((r) => r.code == '610400'), isTrue);
    expect(focused.highlighted, isNot(contains('610400')));
    final xian = focused.cities.firstWhere((city) => city.name == '西安');
    expect(focused.view.contains(xian.point), isTrue);
    await preview(tester, 'focus-xian-districts');
    for (var i = 0; i < 24 && painter(tester).showCities; i++) {
      await tester.tap(find.byTooltip('缩小'));
      await settleMap(tester);
    }
    expect(
      painter(tester).regions
          .any((r) => r.level == 'city' || r.level == 'district'),
      isFalse,
    );
    expect(tester.takeException(), isNull);
  });

  /// 详情入口行的可见高度；完全隐藏时为 0。
  double entryHeight(WidgetTester tester) {
    // 高度为 0 时视口把它算作屏幕外，需包含屏幕外元素查找。
    final entry = find.byKey(
      const ValueKey('details-entry'),
      skipOffstage: false,
    );
    final clip = find
        .ancestor(
          of: entry,
          matching: find.byType(ClipRect, skipOffstage: false),
        )
        .first;
    return tester.getSize(clip).height;
  }

  testWidgets('底部详情只有收起和展开两档：下滑停在默认高度，不出现横条也不消失', (tester) async {
    await start(tester, size: const Size(393, 852));
    await selectCity(tester, '想去哪里', '南昌');
    final body = find.byKey(const ValueKey('snap-sheet-body'));
    final handle = find.byKey(const ValueKey('city-summary-handle'));
    // 首次打开（无出发地）的默认高度。
    final initial = tester.getSize(body).height;
    expect(initial, lessThan(260));
    expect(entryHeight(tester), greaterThan(40));
    await selectCity(tester, '从哪里出发', '武汉');
    // 设了出发地后默认高度不变。
    final collapsed = tester.getSize(body).height;
    expect(collapsed, closeTo(initial, 0.5));
    final mapBottom = tester.getRect(find.byType(InteractiveViewer)).bottom;
    expect(mapBottom, lessThanOrEqualTo(tester.getRect(body).top + 1));
    final mapHeight = tester.getSize(find.byType(InteractiveViewer)).height;
    // 收起状态下慢拖、快滑都停在默认高度。
    await tester.drag(handle, const Offset(0, 200));
    await tester.pumpAndSettle();
    expect(tester.getSize(body).height, closeTo(collapsed, 1));
    await tester.fling(handle, const Offset(0, 300), 2000);
    await tester.pumpAndSettle();
    expect(tester.getSize(body).height, closeTo(collapsed, 1));
    expect(
      tester.getSize(find.byType(InteractiveViewer)).height,
      closeTo(mapHeight, 0.5),
    );
    expect(entryHeight(tester), greaterThan(40));
    await preview(tester, 'sheet-after-drag-down');
    // 上滑展开：入口行收起，固定摘要不移位。
    final summaryOffset =
        tester.getRect(find.byKey(const ValueKey('city-summary'))).top -
        tester.getRect(body).top;
    await tester.fling(handle, const Offset(0, -300), 1200);
    await tester.pumpAndSettle();
    expect(tester.getSize(body).height, greaterThan(600));
    // 展开手势的余势会滚动内容，先回到顶部再测量。
    tester
        .state<ScrollableState>(
          find
              .descendant(
                of: find.byType(CityDetails),
                matching: find.byType(Scrollable),
              )
              .first,
        )
        .position
        .jumpTo(0);
    await tester.pump();
    expect(entryHeight(tester), closeTo(0, 0.5));
    final summary = tester.getRect(find.byKey(const ValueKey('city-summary')));
    final firstCard = tester.getRect(
      find.byKey(const ValueKey('section-industry')),
    );
    // 摘要分隔线下方直接是第一张卡片。
    expect(firstCard.top - summary.bottom, lessThan(16));
    expect(summary.top - tester.getRect(body).top, closeTo(summaryOffset, 0.5));
    await preview(tester, 'sheet-expanded-no-entry');
    // 展开状态快速下滑回到默认高度，入口行重新出现。
    await tester.fling(handle, const Offset(0, 600), 4000);
    await tester.pumpAndSettle();
    expect(tester.getSize(body).height, closeTo(collapsed, 1));
    expect(entryHeight(tester), greaterThan(40));
    // 从入口行拖动同样可以展开。
    await tester.drag(find.text('产业 · 租房 · 生活成本'), const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(tester.getSize(body).height, greaterThan(600));
    await tester.fling(handle, const Offset(0, 300), 1200);
    await tester.pumpAndSettle();
    expect(tester.getSize(body).height, closeTo(collapsed, 1));
    expect(fieldText(tester, 'destination-field'), '南昌');
    // 只有关闭按钮会移除面板。
    await tester.tap(find.byTooltip('收起城市详情'));
    await tester.pumpAndSettle();
    expect(find.byType(CityDetails), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('从展开或收起状态快速下滑都回到默认收起高度', (tester) async {
    await start(tester, size: const Size(393, 852));
    await selectCity(tester, '想去哪里', '武汉');
    final body = find.byKey(const ValueKey('snap-sheet-body'));
    final handle = find.byKey(const ValueKey('city-summary-handle'));
    final collapsed = tester.getSize(body).height;
    for (var i = 0; i < 3; i++) {
      await tester.fling(handle, const Offset(0, -400), 2000);
      await tester.pumpAndSettle();
      expect(tester.getSize(body).height, greaterThan(600));
      for (var j = 0; j < 2; j++) {
        await tester.fling(handle, const Offset(0, 600), 4000);
        await tester.pumpAndSettle();
        expect(find.byType(CityDetails), findsOneWidget);
        expect(tester.getSize(body).height, closeTo(collapsed, 1));
      }
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('底部三列选择器可拖动调高、下滑只会收小，列表仍可滚动', (tester) async {
    await start(tester, size: const Size(393, 852));
    await tester.tap(find.text('从哪里出发'));
    await tester.pumpAndSettle();
    final lists = find.byKey(const ValueKey('city-picker-lists'));
    final handle = find.byKey(const ValueKey('city-picker-handle'));
    expect(tester.getSize(lists).height, closeTo(220, 1));
    await tester.drag(handle, const Offset(0, -200));
    await tester.pumpAndSettle();
    final expanded = tester.getSize(lists).height;
    expect(expanded, greaterThan(400));
    await preview(tester, 'picker-expanded');
    final provinces = find.byKey(const ValueKey('picker-provinces'));
    await tester.drag(provinces, const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(
      tester
          .state<ScrollableState>(
            find.descendant(of: provinces, matching: find.byType(Scrollable)),
          )
          .position
          .pixels,
      greaterThan(0),
    );
    expect(tester.getSize(lists).height, closeTo(expanded, 1));
    await tester.fling(handle, const Offset(0, 200), 1200);
    await tester.pumpAndSettle();
    expect(tester.getSize(lists).height, closeTo(220, 1));
    await tester.fling(handle, const Offset(0, 200), 1200);
    await tester.pumpAndSettle();
    // 下滑到底只剩标题栏，选择器仍在。
    expect(find.byKey(const ValueKey('city-picker')), findsOneWidget);
    expect(tester.getSize(lists).height, closeTo(0, 1));
    expect(find.text('完成'), findsOneWidget);
    await tester.fling(handle, const Offset(0, 200), 2000);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('city-picker')), findsOneWidget);
    await tester.tap(handle);
    await tester.pumpAndSettle();
    expect(tester.getSize(lists).height, closeTo(220, 1));
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('city-picker')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('地图点击填入当前字段：已有目的地时填出发地，选择器打开时填其字段', (tester) async {
    await start(tester, size: const Size(393, 852));
    // 无选择时点击地图仍设目的地。
    expect(fieldLabelColor(tester, 'destination-field'), AppColors.primary);
    await selectCity(tester, '想去哪里', '长沙');
    expect(fieldLabelColor(tester, 'origin-field'), AppColors.primary);
    expect(fieldLabelColor(tester, 'destination-field'), AppColors.hintText);
    expect(find.textContaining('设为出发地'), findsOneWidget);
    await tapCityOnMap(tester, '南昌');
    expect(fieldText(tester, 'origin-field'), '南昌');
    expect(fieldText(tester, 'destination-field'), '长沙');
    final labels = painter(tester).layoutLabels().map((label) => label.text);
    expect(labels, containsAll(['起 南昌', '终 长沙']));
    expect(painter(tester).highlighted, contains('360000'));
    // 两地都已选且选择器收起时，点击替换目的地。
    expect(fieldLabelColor(tester, 'destination-field'), AppColors.primary);
    // 打开出发地选择器后，点击地图改为填出发地，三列跟随到湖北/武汉。
    await tester.tap(find.byKey(const ValueKey('origin-field')));
    await tester.pumpAndSettle();
    expect(fieldLabelColor(tester, 'origin-field'), AppColors.primary);
    await tapCityOnMap(tester, '武汉');
    expect(fieldText(tester, 'origin-field'), '武汉');
    expect(fieldText(tester, 'destination-field'), '长沙');
    expect(find.byKey(const ValueKey('picker-city-420100')), findsOneWidget);
    expect(find.byKey(const ValueKey('picker-city-360100')), findsNothing);
    await preview(tester, 'map-tap-origin-picker');
    await tester.tap(find.text('完成'));
    await settleMap(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('任意城市被选中后，全国缩放下整省高亮而非城市小块', (tester) async {
    await start(tester, size: const Size(393, 852));
    for (final (name, province) in [
      ('长沙', '430000'),
      ('西安', '610000'),
      ('广州', '440000'),
      ('哈尔滨', '230000'),
      ('乌鲁木齐', '650000'),
      ('南昌', '360000'),
    ]) {
      await selectCity(tester, '想去哪里', name);
      final current = painter(tester);
      expect(current.highlighted, contains(province), reason: name);
      // 市界未显现时省级高亮完整可见。
      expect(current.cityOpacity, lessThan(0.05), reason: name);
      if (name == '长沙') {
        await preview(tester, 'highlight-changsha');
        // 截图场景：目的地长沙、打开出发地选择器后地图变矮，整省高亮仍在。
        await tester.tap(find.byKey(const ValueKey('origin-field')));
        await settleMap(tester);
        expect(painter(tester).highlighted, contains(province));
        expect(painter(tester).cityOpacity, lessThan(0.05));
        await preview(tester, 'highlight-changsha-picker');
        await tester.tap(find.text('完成'));
        await settleMap(tester);
      }
      await tester.tap(find.byTooltip('返回全国'));
      await settleMap(tester);
    }
  });

  testWidgets('两块字段尺寸一致，并相对交换按钮对称，激活哪一侧都不变', (tester) async {
    await start(tester, size: const Size(393, 852));
    Future<void> expectSymmetric(String name) async {
      final origin = tester.getRect(find.byKey(const ValueKey('origin-field')));
      final destination = tester.getRect(
        find.byKey(const ValueKey('destination-field')),
      );
      final swap = tester.getRect(find.byTooltip('交换出发地和目的地'));
      expect(origin.size, destination.size, reason: name);
      expect(origin.top, closeTo(destination.top, 0.5), reason: name);
      expect(
        swap.center.dx - origin.right,
        closeTo(destination.left - swap.center.dx, 0.5),
        reason: name,
      );
      // 交换按钮不压住任何一侧字段。
      expect(swap.left, greaterThanOrEqualTo(origin.right), reason: name);
      expect(swap.right, lessThanOrEqualTo(destination.left), reason: name);
      expect(swap.center.dy, closeTo(origin.center.dy, 0.5), reason: name);
      final card = tester.getRect(find.byKey(const ValueKey('trip-fields')));
      expect(
        origin.left - card.left,
        closeTo(card.right - destination.right, 0.5),
      );
      final map = tester.getRect(find.byType(InteractiveViewer));
      expect(map.top - card.bottom, greaterThanOrEqualTo(8), reason: name);
      await preview(tester, name);
    }

    expect(fieldLabelColor(tester, 'destination-field'), AppColors.primary);
    await expectSymmetric('header-destination-active');
    final before = tester.getRect(find.byKey(const ValueKey('origin-field')));
    await selectCity(tester, '想去哪里', '武汉');
    expect(fieldLabelColor(tester, 'origin-field'), AppColors.primary);
    expect(tester.getRect(find.byKey(const ValueKey('origin-field'))), before);
    await expectSymmetric('header-origin-active');
  });

  testWidgets('顶部出发/目的两栏等宽，交换按钮位于卡片中线', (tester) async {
    for (final size in [const Size(393, 852), const Size(1200, 800)]) {
      await start(tester, size: size);
      await selectCity(tester, '从哪里出发', '乌鲁木齐');
      await selectCity(tester, '想去哪里', '武汉');
      final row = tester.getRect(find.byKey(const ValueKey('trip-fields')));
      final swap = tester.getCenter(find.byTooltip('交换出发地和目的地'));
      final origin = tester.getRect(find.byKey(const ValueKey('origin-field')));
      final destination = tester.getRect(
        find.byKey(const ValueKey('destination-field')),
      );
      expect(swap.dx, closeTo(row.center.dx, 0.5));
      expect(origin.width, closeTo(destination.width, 0.5));
      expect(swap.dy, closeTo(origin.center.dy, 1));
      for (final text in ['乌鲁木齐', '武汉']) {
        final center = tester.getCenter(find.text(text).first);
        final field = text == '武汉' ? destination : origin;
        expect(center.dx, closeTo(field.center.dx, 1), reason: text);
      }
    }
  });

  testWidgets('手机默认视角等于全国视图点三次放大，且不能缩到全国小图', (tester) async {
    await start(tester, size: const Size(393, 852));
    final finder = find.byType(InteractiveViewer);
    final viewer = tester.widget<InteractiveViewer>(finder);
    final controller = viewer.transformationController!;
    final viewport = tester.getSize(finder);
    MapCamera camera() => (
      center: MatrixUtils.transformPoint(
        Matrix4.inverted(controller.value),
        viewport.center(Offset.zero),
      ),
      scale: controller.value.getMaxScaleOnAxis(),
    );
    // 独立重算全国视图：全国边界按页面同样的留白放进视口。
    final national = painter(tester).provinces
        .map((region) => region.bounds)
        .reduce((a, b) => a.expandToInclude(b));
    final base = math.min(
      (viewport.width - 32) / national.width,
      (viewport.height - 48) / national.height,
    );
    final home = camera();
    expect(home.scale, closeTo(base * math.pow(1.35, 3), 1e-6));
    expect((home.center - national.center).distance, lessThan(0.01));
    final current = painter(tester);
    for (final name in ['西安', '武汉', '广州', '北京', '银川', '西宁', '海口']) {
      final city = current.cities.firstWhere((item) => item.name == name);
      expect(current.view.contains(city.point), isTrue, reason: name);
    }
    final urumqi = current.cities.firstWhere((item) => item.name == '乌鲁木齐');
    expect(current.view.contains(urumqi.point), isFalse);
    await preview(tester, 'default-view');
    // 缩小到底：全国至少撑满视口高度，不出现上下大片留白的小图。
    for (var i = 0; i < 8; i++) {
      await tester.tap(find.byTooltip('缩小'));
      await settleMap(tester);
    }
    final floor = camera().scale;
    expect(floor, lessThan(home.scale));
    expect(floor, greaterThan(base * 1.2));
    expect(
      national.height * floor,
      greaterThanOrEqualTo(viewport.height - 48.5),
    );
    expect(viewer.minScale, closeTo(floor, 1e-6));
    // 双指缩小同样受下限约束。
    final center = tester.getCenter(finder);
    final first = await tester.startGesture(center - const Offset(80, 0));
    final second = await tester.startGesture(center + const Offset(80, 0));
    await first.moveBy(const Offset(70, 0));
    await second.moveBy(const Offset(-70, 0));
    await first.up();
    await second.up();
    await settleMap(tester);
    expect(find.byType(CityDetails), findsNothing);
    expect(camera().scale, greaterThanOrEqualTo(floor - 1e-6));
    await preview(tester, 'min-zoom-view');
    // 返回全国回到同一默认视角。
    await tester.tap(find.byTooltip('返回全国'));
    await settleMap(tester);
    expect(camera().scale, closeTo(home.scale, 1e-6));
    expect((camera().center - home.center).distance, lessThan(0.01));
    expect(tester.takeException(), isNull);
  });

  testWidgets('未操作前视口尺寸变化会重新计算默认视角', (tester) async {
    await start(tester, size: const Size(393, 852));
    final finder = find.byType(InteractiveViewer);
    final controller = tester
        .widget<InteractiveViewer>(finder)
        .transformationController!;
    final first = controller.value.getMaxScaleOnAxis();
    // 打开选择器会让地图变矮。
    await tester.tap(find.byKey(const ValueKey('origin-field')));
    await settleMap(tester);
    final viewport = tester.getSize(finder);
    final national = painter(tester).provinces
        .map((region) => region.bounds)
        .reduce((a, b) => a.expandToInclude(b));
    final base = math.min(
      (viewport.width - 32) / national.width,
      (viewport.height - 48) / national.height,
    );
    expect(
      controller.value.getMaxScaleOnAxis(),
      closeTo(base * math.pow(1.35, 3), 1e-6),
    );
    expect(first, isPositive);
    expect(tester.takeException(), isNull);
  });

  /// 把镜头放到 [lon]/[lat]，可见范围较长边为 [span] 个画布单位。
  Future<void> lookAt(
    WidgetTester tester,
    double lon,
    double lat,
    double span,
  ) async {
    final finder = find.byType(InteractiveViewer);
    final size = tester.getSize(finder);
    final scale = math.max(size.width, size.height) / span;
    final translation = size.center(Offset.zero) - project(lon, lat) * scale;
    tester
        .widget<InteractiveViewer>(finder)
        .transformationController!
        .value = Matrix4.identity()
      ..translateByDouble(translation.dx, translation.dy, 0, 1)
      ..scaleByDouble(scale, scale, scale, 1);
    await settleMap(tester);
  }

  Set<String> cityLabels(MapPainter painter, {required bool muted}) => {
    for (final label in painter.layoutLabels())
      if (label.priority >= 1 && label.priority <= 2 && label.muted == muted)
        label.text,
  };

  testWidgets('放大江西：全部地级市都有标签，无选中时不加绿色高亮', (tester) async {
    await start(tester, size: const Size(393, 852));
    await lookAt(tester, 115.9, 27.6, 190);
    final current = painter(tester);
    expect(current.detailProvinces, {'360000'});
    expect(current.highlighted, isEmpty);
    final jiangxi = cityLabels(current, muted: false);
    for (final name in [
      '南昌',
      '九江',
      '景德镇',
      '鹰潭',
      '新余',
      '赣州',
      '吉安',
      '宜春',
      '抚州',
      '萍乡',
      '上饶',
    ]) {
      expect(jiangxi, contains(name), reason: name);
    }
    // 上饶与其他城市同样完全不透明，不再是残影。
    final shangrao = current.layoutLabels().firstWhere((l) => l.text == '上饶');
    final jiujiang = current.layoutLabels().firstWhere((l) => l.text == '九江');
    expect(shangrao.opacity, jiujiang.opacity);
    expect(shangrao.muted, isFalse);
    // 邻省也显示淡化的市界和市名，但不下钻区县。
    expect(cityLabels(current, muted: true), isNotEmpty);
    expect(current.cityBoundaries.any((r) => r.code.startsWith('43')), isTrue);
    expect(current.regions.any((r) => r.level == 'district'), isFalse);
    await preview(tester, 'jiangxi-zoom');
    expect(tester.takeException(), isNull);
  });

  testWidgets('放大江西后平移到湖南：细节聚焦跟随视口，湖南城市有标签和市界', (tester) async {
    await start(tester, size: const Size(393, 852));
    await lookAt(tester, 115.9, 27.6, 190);
    expect(painter(tester).detailProvinces, {'360000'});
    final finder = find.byType(InteractiveViewer);
    // 向右拖动，镜头左移到湖南中部。
    final scale = tester
        .widget<InteractiveViewer>(finder)
        .transformationController!
        .value
        .getMaxScaleOnAxis();
    final shift = (project(115.9, 27.6) - project(111.7, 27.6)) * scale;
    final gesture = await tester.startGesture(tester.getCenter(finder));
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(shift / 10);
      await tester.pump(const Duration(milliseconds: 50));
    }
    // 拖动尚未松手时聚焦已切到湖南。
    expect(painter(tester).detailProvinces, {'430000'});
    await gesture.up();
    await settleMap(tester);
    final current = painter(tester);
    expect(current.detailProvinces, {'430000'});
    expect(current.highlighted, isEmpty);
    final hunan = cityLabels(current, muted: false);
    for (final name in ['长沙', '株洲', '湘潭', '衡阳', '邵阳', '娄底', '益阳']) {
      expect(hunan, contains(name), reason: name);
    }
    expect(
      current.cityBoundaries.where((r) => r.code.startsWith('43')),
      isNotEmpty,
    );
    // 江西成了邻省，城市淡化。
    expect(
      current
          .layoutLabels()
          .where((l) => l.code.startsWith('36') && l.priority == 2)
          .every((l) => l.muted),
      isTrue,
    );
    await preview(tester, 'pan-hunan');
    expect(tester.takeException(), isNull);
  });

  testWidgets('选中城市后保持强调，平移到别省仍显示淡化的市级细节', (tester) async {
    await start(tester, size: const Size(393, 852));
    await selectCity(tester, '想去哪里', '南昌');
    await tester.tap(find.byTooltip('收起城市详情'));
    await settleMap(tester);
    await lookAt(tester, 115.4, 27.8, 190);
    var current = painter(tester);
    expect(current.detailProvinces, {'360000'});
    expect(current.highlighted, contains('360100'));
    expect(cityLabels(current, muted: true), isNotEmpty);
    await preview(tester, 'selected-city-zoom');
    await lookAt(tester, 111.7, 27.6, 190);
    current = painter(tester);
    // 选中城市仍是完整细节的省份，湖南以淡化市级细节显示而不是空白。
    expect(current.detailProvinces, {'360000'});
    // 淡化标签在真正重叠时让位，具体保留哪几个取决于字体宽度。
    expect(
      current.layoutLabels().where((l) => l.muted && l.code.startsWith('43')),
      hasLength(greaterThanOrEqualTo(5)),
    );
    expect(
      current.cityBoundaries.where((r) => r.code.startsWith('43')),
      isNotEmpty,
    );
    expect(tester.takeException(), isNull);
  });
}
