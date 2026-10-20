import 'package:flutter_test/flutter_test.dart';

import 'package:china_map/update/app_release.dart';

void main() {
  group('isNewerVersion', () {
    test('compares numerically', () {
      expect(isNewerVersion('v1.0.1', '1.0.0'), isTrue);
      expect(isNewerVersion('1.10.0', '1.9.9'), isTrue);
      expect(isNewerVersion('v1.0.0', '1.0.0'), isFalse);
      expect(isNewerVersion('1.0.0', '1.0.1'), isFalse);
    });
    test('handles uneven length, build and prerelease suffix', () {
      expect(isNewerVersion('1.1', '1.0.9'), isTrue);
      expect(isNewerVersion('1.0', '1.0.0'), isFalse);
      expect(isNewerVersion('1.0.0+5', '1.0.0'), isFalse);
      expect(isNewerVersion('v2.0.0-beta', '1.9.0'), isTrue);
    });
    test('invalid input is never newer', () {
      expect(isNewerVersion('latest', '1.0.0'), isFalse);
      expect(isNewerVersion('1.0.1', ''), isFalse);
    });
  });

  group('AppRelease.fromJson', () {
    Map<String, Object?> json({List<Object?>? assets}) => {
      'tag_name': 'v1.2.0',
      'body': '  修复若干问题  ',
      'draft': false,
      'prerelease': false,
      'assets':
          assets ??
          [
            {
              'name': 'chengxiang-v1.2.0-arm64-v8a.apk',
              'browser_download_url': 'https://x/arm64.apk',
              'size': 10,
            },
            {
              'name': 'chengxiang-v1.2.0.apk',
              'browser_download_url': 'https://x/universal.apk',
              'size': 30,
            },
          ],
    };

    test('prefers universal apk', () {
      final r = AppRelease.fromJson(json());
      expect(r?.version, '1.2.0');
      expect(r?.notes, '修复若干问题');
      expect(r?.apkUrl, 'https://x/universal.apk');
      expect(r?.apkSize, 30);
    });
    test('falls back to abi apk', () {
      final r = AppRelease.fromJson(
        json(
          assets: [
            {'name': 'a-arm64-v8a.apk', 'browser_download_url': 'https://x/a'},
          ],
        ),
      );
      expect(r?.apkUrl, 'https://x/a');
      expect(r?.apkSize, 0);
    });
    test('rejects missing apk, prerelease and malformed data', () {
      expect(AppRelease.fromJson(json(assets: [])), isNull);
      expect(AppRelease.fromJson({...json(), 'prerelease': true}), isNull);
      expect(AppRelease.fromJson({...json(), 'tag_name': 'nightly'}), isNull);
      expect(AppRelease.fromJson('oops'), isNull);
      expect(AppRelease.fromJson({'message': 'Not Found'}), isNull);
    });
  });
}
