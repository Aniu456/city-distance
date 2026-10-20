/// 地图点击城市时要填入的字段：true 为出发地，false 为目的地。
///
/// 只有用户先点了出发或目的字段（其选择器打开）时才填入该字段；返回 null
/// 时点击只查看城市（聚焦并显示详情），不改动出发地和目的地。
bool? mapTapField({required bool? pickingOrigin}) => pickingOrigin;
