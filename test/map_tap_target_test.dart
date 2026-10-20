import 'package:china_map/utils/map_tap_target.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('选择器打开时地图点击填入其字段', () {
    for (final hasOrigin in [false, true]) {
      for (final hasDestination in [false, true]) {
        expect(
          mapTapFillsOrigin(
            pickingOrigin: true,
            hasOrigin: hasOrigin,
            hasDestination: hasDestination,
          ),
          isTrue,
        );
        expect(
          mapTapFillsOrigin(
            pickingOrigin: false,
            hasOrigin: hasOrigin,
            hasDestination: hasDestination,
          ),
          isFalse,
        );
      }
    }
  });

  test('选择器收起时，只有“有目的地、缺出发地”才填出发地', () {
    bool fills({required bool origin, required bool destination}) =>
        mapTapFillsOrigin(
          pickingOrigin: null,
          hasOrigin: origin,
          hasDestination: destination,
        );
    expect(fills(origin: false, destination: false), isFalse);
    expect(fills(origin: false, destination: true), isTrue);
    expect(fills(origin: true, destination: false), isFalse);
    expect(fills(origin: true, destination: true), isFalse);
  });
}
