import 'package:flutter_driver/flutter_driver.dart' as driver;
import 'package:integration_test/integration_test_driver.dart';

/// 真机性能驱动：把集成测试上报的时间线写成摘要文件（build/ 下）。
///
/// flutter drive --profile --driver=test_driver/perf_driver.dart \
///   --target=integration_test/pan_perf_test.dart -d <设备>
Future<void> main() => integrationDriver(
  responseDataCallback: (data) async {
    if (data == null) {
      return;
    }
    for (final entry in data.entries) {
      final timeline = driver.Timeline.fromJson(
        entry.value as Map<String, dynamic>,
      );
      final summary = driver.TimelineSummary.summarize(timeline);
      await summary.writeTimelineToFile(
        entry.key,
        pretty: true,
        includeSummary: true,
      );
    }
  },
);
