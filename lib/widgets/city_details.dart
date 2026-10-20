import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/city.dart';
import '../models/city_profile.dart';
import '../theme/app_colors.dart';
import '../utils/travel_estimate.dart';

/// 目的城市详情：顶部摘要固定，下面依次是产业、租房、生活支出三个同构分区，
/// 最后是合并后的“估算方式与数据来源”折叠项。
///
/// 宽屏侧栏和手机底部面板共用；提供 [controller] 时为面板模式，显示拖动把手。
class CityDetails extends StatelessWidget {
  const CityDetails({
    super.key,
    required this.destination,
    required this.origin,
    required this.profile,
    required this.rent,
    required this.onClose,
    this.onExpand,
    this.controller,
    this.expansion,
  });
  final City destination;
  final City? origin;
  final CityProfile? profile;
  final RentReference? rent;
  final VoidCallback onClose;

  /// 面板模式下点击把手或“产业 · 租房 · 生活成本”时调用，用于展开或收起。
  final VoidCallback? onExpand;

  /// 提供时为底部面板模式：须使用面板的滚动控制器，拖动才能改变面板高度。
  final ScrollController? controller;

  /// 面板展开进度（0 收起，1 展开）。入口行只是收起状态的展开提示，随展开淡出收起。
  final ValueListenable<double>? expansion;

  /// 无数据分区显示的唯一一行文字。
  static const emptyText = '暂无该城市数据';

  @override
  Widget build(BuildContext context) {
    final departure = origin;
    final estimate = departure == null
        ? null
        : TravelEstimate(departure, destination);
    final sheet = controller != null;
    return CustomScrollView(
      // 按城市区分滚动位置：换城市后从顶部开始，而不是沿用上一城市的位置。
      key: PageStorageKey('city-details-${destination.code}'),
      controller: controller,
      slivers: [
        PinnedHeaderSliver(
          child: _Summary(
            key: const ValueKey('city-summary'),
            destination: destination,
            departure: departure,
            estimate: estimate,
            sheet: sheet,
            onExpand: onExpand,
            onClose: onClose,
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          sliver: SliverList.list(
            children: [
              if (sheet)
                ValueListenableBuilder<double>(
                  valueListenable: expansion ?? ValueNotifier<double>(0),
                  builder: (context, progress, child) {
                    // 前 60% 展开内完成淡出；高度同步收起，固定摘要不受影响。
                    final visible = 1 - (progress / 0.6).clamp(0.0, 1.0);
                    return ClipRect(
                      child: Align(
                        alignment: Alignment.topCenter,
                        heightFactor: visible,
                        child: Opacity(
                          opacity: visible,
                          child: IgnorePointer(
                            ignoring: visible == 0,
                            child: child,
                          ),
                        ),
                      ),
                    );
                  },
                  child: KeyedSubtree(
                    key: const ValueKey('details-entry'),
                    child: InkWell(
                      onTap: onExpand,
                      borderRadius: BorderRadius.circular(8),
                      child: const SizedBox(
                        height: 44,
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 4),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '产业 · 租房 · 生活成本',
                                  style: TextStyle(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Icon(
                                Icons.arrow_forward,
                                size: 18,
                                color: AppColors.primary,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              _industry(profile),
              const SizedBox(height: 12),
              _rent(rent),
              const SizedBox(height: 12),
              _living(profile),
              const SizedBox(height: 8),
              _Footer(estimate: estimate, profile: profile, rent: rent),
            ],
          ),
        ),
      ],
    );
  }

  Widget _industry(CityProfile? data) {
    if (data == null) {
      return const _Section.empty(
        key: ValueKey('section-industry'),
        title: '产业与工作方向',
      );
    }
    const sectorNames = ['第一产业 · 农林牧渔', '第二产业 · 工业和建筑', '第三产业 · 服务业'];
    return _Section(
      key: const ValueKey('section-industry'),
      title: '产业与工作方向',
      rows: [
        _Row('${data.year} 年 GDP', '${data.gdp.toStringAsFixed(0)} 亿元'),
        for (var index = 0; index < 3; index++)
          _Row(
            sectorNames[index],
            '${data.sectors[index].toStringAsFixed(1)}%',
            share: data.sectors[index],
          ),
      ],
      subtitle: data.industries.isEmpty ? null : '主要行业',
      subRows: [
        for (final industry in data.industries)
          _Row(
            industry.name,
            industry.percent == null
                ? '—'
                : '${industry.percent?.toStringAsFixed(1)}%',
          ),
      ],
      footnote:
          '${data.year} 年统计公报 · 行业百分比为增加值占 GDP 比重，属于三次产业的细分；“—”表示未收录占比。产业规模不等于招聘需求。',
    );
  }

  Widget _rent(RentReference? rental) {
    if (rental == null) {
      return const _Section.empty(key: ValueKey('section-rent'), title: '租房参考');
    }
    return _Section(
      key: const ValueKey('section-rent'),
      title: '租房参考',
      rows: [
        _Row('样本住宅平均租金', '${rental.average.toStringAsFixed(1)} 元/㎡·月'),
        _Row('样本租金中位数', '${rental.median.toStringAsFixed(1)} 元/㎡·月'),
        _Row('30 ㎡整租面积折算', '约 ${(rental.average * 30).round()} 元/月'),
      ],
      footnote: '${rental.period} · 住宅挂牌样本；面积折算仅作比较，合租单间、地段及户型价格可能不同。',
    );
  }

  Widget _living(CityProfile? data) {
    if (data == null) {
      return const _Section.empty(
        key: ValueKey('section-living'),
        title: '居民生活支出参考',
      );
    }
    return _Section(
      key: const ValueKey('section-living'),
      title: '居民生活支出参考',
      rows: [
        _Row('人均每月消费折算', '约 ${(data.annualConsumption / 12).round()} 元'),
        _Row(
          '${data.consumptionScope}人均消费',
          '${data.annualConsumption.round()} 元/年',
        ),
      ],
      footnote:
          '${data.year} 年 · 年人均消费 ÷ 12。已包含居住等消费，不应再与上方租金直接相加；个人实际开销因生活方式而异。',
    );
  }
}

/// 固定在顶部的摘要：城市名、出发地和两种耗时，滚动详情时始终可见。
class _Summary extends StatelessWidget {
  const _Summary({
    super.key,
    required this.destination,
    required this.departure,
    required this.estimate,
    required this.sheet,
    required this.onExpand,
    required this.onClose,
  });

  final City destination;
  final City? departure;
  final TravelEstimate? estimate;
  final bool sheet;
  final VoidCallback? onExpand;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final estimate = this.estimate;
    final departure = this.departure;
    return ColoredBox(
      color: AppColors.background,
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, sheet ? 10 : 8, 12, 0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (sheet)
              GestureDetector(
                key: const ValueKey('city-summary-handle'),
                behavior: HitTestBehavior.opaque,
                onTap: onExpand,
                child: SizedBox(
                  height: 20,
                  child: Center(
                    child: Container(
                      width: 32,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.regionBorder.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: onExpand,
                    child: Text(
                      destination.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: AppColors.label,
                      ),
                    ),
                  ),
                ),
                if (departure != null)
                  Flexible(
                    child: Text(
                      '从 ${departure.name} 出发',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.hintText,
                      ),
                    ),
                  ),
                IconButton(
                  tooltip: '收起城市详情',
                  onPressed: onClose,
                  icon: const Icon(Icons.close, size: 20),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8, bottom: 12),
              child: switch (estimate) {
                null => const Text(
                  '选择出发城市，看看坐火车要多久。',
                  style: TextStyle(fontSize: 13, color: AppColors.hintText),
                ),
                TravelEstimate(unavailableReason: final String reason) => Text(
                  reason,
                  style: const TextStyle(fontSize: 13),
                ),
                final TravelEstimate estimate => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _metric(
                            '高铁',
                            formatHours(estimate.hours(highSpeed: true)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _metric(
                            '普通火车',
                            formatHours(estimate.hours(highSpeed: false)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '直线约 ${estimate.straightKm.round()} km · 耗时为距离模型粗估',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.hintText,
                      ),
                    ),
                  ],
                ),
              },
            ),
            Divider(
              height: 1,
              color: AppColors.regionBorder.withValues(alpha: 0.2),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metric(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(fontSize: 12, color: AppColors.hintText),
      ),
      const SizedBox(height: 2),
      // 窄侧栏中长时间段整体缩小，不截断。
      FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(
          value,
          maxLines: 1,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppColors.label,
          ),
        ),
      ),
    ],
  );
}

class _Row {
  const _Row(this.label, this.value, {this.share});
  final String label;
  final String value;

  /// 0–100，提供时在数值下方画一条细比例条。
  final double? share;
}

/// 分区组件，样式取自“租房参考”：粗体标题、标签/粗体数值行、灰色小字脚注。
/// 没有数据时整块收成一行：标题加灰色“暂无该城市数据”。
class _Section extends StatelessWidget {
  const _Section({
    super.key,
    required this.title,
    required this.rows,
    required this.footnote,
    this.subtitle,
    this.subRows = const [],
  });

  const _Section.empty({super.key, required this.title})
    : rows = const [],
      footnote = null,
      subtitle = null,
      subRows = const [];

  final String title;
  final List<_Row> rows;
  final String? subtitle;
  final List<_Row> subRows;
  final String? footnote;

  bool get _empty => rows.isEmpty;

  @override
  Widget build(BuildContext context) {
    final footnote = this.footnote;
    final subtitle = this.subtitle;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.mapBackground.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.regionBorder.withValues(alpha: 0.12),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          14,
          _empty ? 12 : 14,
          14,
          _empty ? 12 : 12,
        ),
        child: _empty
            ? Row(
                children: [
                  Expanded(child: Text(title, style: _titleStyle)),
                  const Text(
                    CityDetails.emptyText,
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.placeholder,
                    ),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(title, style: _titleStyle),
                  const SizedBox(height: 6),
                  for (final row in rows) _row(row),
                  if (subtitle != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.hintText,
                      ),
                    ),
                    for (final row in subRows) _row(row),
                  ],
                  if (footnote != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      footnote,
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: AppColors.hintText,
                      ),
                    ),
                  ],
                ],
              ),
      ),
    );
  }

  static const _titleStyle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w700,
    color: AppColors.label,
  );

  Widget _row(_Row row) {
    final share = row.share;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(row.label, style: const TextStyle(fontSize: 13)),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  row.value,
                  textAlign: TextAlign.end,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (share != null) ...[
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: share / 100,
                minHeight: 3,
                color: AppColors.primary,
                backgroundColor: AppColors.regionBorder.withValues(alpha: 0.15),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 合并后的底部折叠项：耗时估算说明、估算方式、数据来源与统计口径。
class _Footer extends StatelessWidget {
  const _Footer({
    required this.estimate,
    required this.profile,
    required this.rent,
  });

  final TravelEstimate? estimate;
  final CityProfile? profile;
  final RentReference? rent;

  static const _small = TextStyle(
    fontSize: 12,
    height: 1.45,
    color: AppColors.hintText,
  );

  @override
  Widget build(BuildContext context) {
    final estimate = this.estimate;
    final rental = rent;
    final sources = [...?profile?.sources, if (rental != null) rental.source];
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: const PageStorageKey('details-footer'),
        tilePadding: const EdgeInsets.symmetric(horizontal: 4),
        childrenPadding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        title: const Text(
          '估算方式与数据来源',
          style: TextStyle(fontSize: 13, color: AppColors.hintText),
        ),
        children: [
          _label('出行耗时'),
          if (estimate != null) ...[
            Text('城市间直线距离约 ${estimate.straightKm.round()} km。', style: _small),
          ],
          const Text('按距离模型粗估；未核实直达车次或通车情况，不含候车、换乘和市内交通。', style: _small),
          const SizedBox(height: 4),
          const Text(
            '估算方式：直线距离 × 1.15–1.50 绕行系数，再除以假设均速：高铁 160–250 km/h，普铁 60–100 km/h。取整到半小时。地图虚线仅连接两地，不是实际铁路线。',
            style: _small,
          ),
          _label('数据来源与统计口径'),
          if (profile == null)
            const Text('产业与居民消费统计当前完整资料覆盖北京、上海、广州、深圳、杭州、成都。', style: _small),
          for (final source in sources)
            Row(
              children: [
                Expanded(
                  child: Text(
                    source.title,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                IconButton(
                  tooltip: '复制来源链接',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.link, size: 18),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: source.url));
                    if (context.mounted) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(const SnackBar(content: Text('来源链接已复制')));
                    }
                  },
                ),
              ],
            ),
          const Text('资料核实于 2026-10-19，按各自年度/月度展示，不是实时数据。', style: _small),
        ],
      ),
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(top: 6, bottom: 4),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: AppColors.label,
      ),
    ),
  );
}
