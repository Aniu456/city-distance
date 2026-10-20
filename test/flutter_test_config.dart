import 'dart:async';

import 'package:china_map/data/map_repository.dart';

/// 测试的伪时钟不等待真实的后台 isolate，地图数据在当前线程解码。
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  MapRepository.decodeInBackground = false;
  await testMain();
}
