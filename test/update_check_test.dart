import 'dart:convert';

import 'package:china_map/update/update_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: '城向',
      packageName: 'china_map',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  Future<UpdateCheckResult> checkMissingLatest(http.Response listing) {
    return UpdateService(
      client: MockClient((request) async {
        if (request.url.toString() == UpdateService.latestUrl) {
          return http.Response('{"message":"Not Found"}', 404);
        }
        expect(request.url.toString(), UpdateService.releasesUrl);
        return listing;
      }),
    ).checkNow();
  }

  test('empty public release list reports no release', () async {
    final result = await checkMissingLatest(http.Response('[]', 200));
    expect(result.status, UpdateCheckStatus.noRelease);
    expect(result.release, isNull);
  });

  test('only prereleases or drafts reports no stable release', () async {
    final result = await checkMissingLatest(
      http.Response(
        jsonEncode([
          {'draft': false, 'prerelease': true},
          {'draft': true, 'prerelease': false},
        ]),
        200,
      ),
    );
    expect(result.status, UpdateCheckStatus.noRelease);
  });

  for (final status in [403, 404, 500]) {
    test('unreadable release list ($status) remains a failure', () async {
      final result = await checkMissingLatest(http.Response('[]', status));
      expect(result.status, UpdateCheckStatus.failed);
    });
  }

  for (final body in [
    'not JSON',
    '{"message":"Not Found"}',
    '[null]',
    '[{"draft":false,"prerelease":false}]',
  ]) {
    test(
      'invalid or conflicting release list is not an empty result: $body',
      () async {
        final result = await checkMissingLatest(http.Response(body, 200));
        expect(result.status, UpdateCheckStatus.failed);
      },
    );
  }

  test('network failure does not claim that no release exists', () async {
    final result = await UpdateService(
      client: MockClient((_) async => throw http.ClientException('offline')),
    ).checkNow();
    expect(result.status, UpdateCheckStatus.failed);
  });

  for (final status in [403, 500]) {
    test('latest response $status does not query the release list', () async {
      var requests = 0;
      final result = await UpdateService(
        client: MockClient((request) async {
          requests++;
          expect(request.url.toString(), UpdateService.latestUrl);
          return http.Response('{}', status);
        }),
      ).checkNow();
      expect(requests, 1);
      expect(result.status, UpdateCheckStatus.failed);
    });
  }

  for (final version in ['1.0.0', '1.0.1']) {
    test('published version $version still uses version comparison', () async {
      final result = await UpdateService(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'tag_name': 'v$version',
              'draft': false,
              'prerelease': false,
              'body': 'notes',
              'assets': [
                {
                  'name': 'chengxiang.apk',
                  'browser_download_url': 'https://example.com/chengxiang.apk',
                  'size': 100,
                },
              ],
            }),
            200,
          ),
        ),
      ).checkNow();
      expect(
        result.status,
        version == '1.0.0'
            ? UpdateCheckStatus.upToDate
            : UpdateCheckStatus.available,
      );
    });
  }
}
