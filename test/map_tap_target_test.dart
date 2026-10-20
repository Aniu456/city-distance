import 'package:china_map/utils/map_tap_target.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('先点了出发或目的字段时，地图点击填入该字段', () {
    expect(mapTapField(pickingOrigin: true), isTrue);
    expect(mapTapField(pickingOrigin: false), isFalse);
  });

  test('未激活任何字段时，地图点击不填入任何字段', () {
    expect(mapTapField(pickingOrigin: null), isNull);
  });
}
