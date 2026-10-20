/// 地图点击城市时填入出发地（true）还是目的地（false）。
///
/// 规则：底部选择器打开时，填入正在选择的字段；选择器收起时，
/// 已有目的地而出发地为空则填出发地，其余情况填目的地。
bool mapTapFillsOrigin({
  required bool? pickingOrigin,
  required bool hasOrigin,
  required bool hasDestination,
}) => pickingOrigin ?? (hasDestination && !hasOrigin);
