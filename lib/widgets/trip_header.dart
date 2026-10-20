import 'package:flutter/material.dart';

import '../models/city.dart';
import '../theme/app_colors.dart';

/// 顶部行程卡片：两块等大的出发/目的字段，中间是交换按钮。
///
/// 宽屏（[compact] 为 false）时下方另有“查看耗时与城市”按钮。
class TripHeader extends StatelessWidget {
  const TripHeader({
    super.key,
    required this.origin,
    required this.destination,
    required this.activeOrigin,
    required this.onFieldTap,
    this.onSwap,
    this.onShowResult,
    this.compact = false,
  });

  final City? origin;
  final City? destination;

  /// 正在选择的字段：true 为出发，false 为目的，null 表示两栏都不高亮。
  final bool? activeOrigin;

  /// 点击字段时调用，参数表示是否为出发字段；为 null 时字段不可点击。
  final void Function({required bool origin})? onFieldTap;

  /// 交换出发地和目的地；为 null 时按钮禁用。
  final VoidCallback? onSwap;

  /// 宽屏下查看结果；为 null 时按钮禁用。
  final VoidCallback? onShowResult;

  final bool compact;

  @override
  Widget build(BuildContext context) => Padding(
    // 四周等距：两块字段到卡片边缘的距离一致。
    padding: const EdgeInsets.all(10),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          key: const ValueKey('trip-fields'),
          children: [
            _field(origin: true),
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
              onPressed: onSwap,
              icon: const Icon(Icons.swap_horiz, size: 24),
            ),
            const SizedBox(width: 8),
            _field(origin: false),
          ],
        ),
        if (!compact) ...[
          const SizedBox(height: 4),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onShowResult,
              child: const Text('查看耗时与城市'),
            ),
          ),
        ],
      ],
    ),
  );

  Widget _field({required bool origin}) {
    final onTap = onFieldTap;
    return Expanded(
      child: _CityField(
        origin: origin,
        city: origin ? this.origin : destination,
        active: activeOrigin == origin,
        onTap: onTap == null ? null : () => onTap(origin: origin),
      ),
    );
  }
}

class _CityField extends StatelessWidget {
  const _CityField({
    required this.origin,
    required this.city,
    required this.active,
    required this.onTap,
  });

  final bool origin;
  final City? city;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final city = this.city;
    return Semantics(
      button: true,
      selected: active,
      label: origin ? '选择出发城市' : '选择目的城市',
      child: InkWell(
        key: ValueKey(origin ? 'origin-field' : 'destination-field'),
        onTap: onTap,
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
                  color: city == null ? AppColors.placeholder : AppColors.label,
                  fontWeight: city == null ? FontWeight.w400 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
