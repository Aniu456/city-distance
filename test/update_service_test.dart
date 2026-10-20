import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:china_map/update/app_release.dart';
import 'package:china_map/update/update_check_button.dart';
import 'package:china_map/update/update_prompt.dart';
import 'package:china_map/update/update_service.dart';

const _release = AppRelease(
  version: '9.9.9',
  notes: 'notes',
  apkUrl: 'https://example.com/a.apk',
  apkSize: 100,
);

/// 先发一个数据块，然后一直不再发送（模拟卡住的下载）。
MockClient _stalledBody(StreamController<List<int>> body) =>
    MockClient.streaming((request, _) async {
      body.add([1, 2, 3]);
      return http.StreamedResponse(body.stream, 200, contentLength: 100);
    });

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('update_test'));
  tearDown(() => dir.deleteSync(recursive: true));

  File apkFile() => File('${dir.path}/chengxiang-9.9.9.apk');

  UpdateService service(
    http.Client Function() factory, {
    ApkInstaller? installer,
  }) => UpdateService(
    downloadClientFactory: factory,
    downloadDirectory: () async => dir,
    installer: installer ?? (_) async => true,
    connectTimeout: const Duration(milliseconds: 100),
    idleTimeout: const Duration(milliseconds: 100),
  );

  test('connect timeout fires when no response arrives', () async {
    final never = Completer<http.StreamedResponse>();
    final s = service(() => MockClient.streaming((_, _) => never.future));
    await expectLater(
      s.download(_release, onProgress: (_) {}),
      throwsA(isA<TimeoutException>()),
    );
    expect(apkFile().existsSync(), isFalse);
  });

  test(
    'idle timeout fires when the body stalls and removes the file',
    () async {
      final body = StreamController<List<int>>();
      final s = service(() => _stalledBody(body));
      await expectLater(
        s.download(_release, onProgress: (_) {}),
        throwsA(isA<TimeoutException>()),
      );
      expect(apkFile().existsSync(), isFalse);
      await body.close();
    },
  );

  test('cancel stops the download and deletes the partial file', () async {
    final body = StreamController<List<int>>();
    final token = UpdateCancelToken();
    final s = UpdateService(
      downloadClientFactory: () => _stalledBody(body),
      downloadDirectory: () async => dir,
      idleTimeout: const Duration(minutes: 10),
    );
    final progress = <double?>[];
    final future = s.download(
      _release,
      cancelToken: token,
      onProgress: progress.add,
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(progress, isNotEmpty);
    token.cancel();
    await expectLater(future, throwsA(isA<UpdateCancelledException>()));
    expect(apkFile().existsSync(), isFalse);
    await body.close();
  });

  test('completed download writes the file', () async {
    final s = service(
      () => MockClient(
        (_) async => http.Response.bytes(List.filled(100, 7), 200),
      ),
    );
    final file = await s.download(_release, onProgress: (_) {});
    expect(file.lengthSync(), 100);
  });

  testWidgets('dismissing during download never calls install', (tester) async {
    final body = StreamController<List<int>>();
    var installs = 0;
    final s = UpdateService(
      downloadClientFactory: () => _stalledBody(body),
      downloadDirectory: () async => dir,
      idleTimeout: const Duration(minutes: 10),
      installer: (_) async {
        installs++;
        return true;
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => UpdateDialog(release: _release, service: s),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('更新'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    expect(find.textContaining('正在下载'), findsOneWidget);

    // 系统返回键关闭弹窗。
    await tester.runAsync(() async {
      await tester.binding.handlePopRoute();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(find.byType(UpdateDialog), findsNothing);

    // 即使数据随后传完，也不能打开安装器。
    await tester.runAsync(() async {
      body.add(List.filled(97, 0));
      await body.close();
      for (var i = 0; i < 40 && apkFile().existsSync(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
    });
    await tester.pump();
    expect(installs, 0);
    expect(apkFile().existsSync(), isFalse);
  });
  group('UpdateCheckButton', () {
    Future<void> tapWith(WidgetTester tester, UpdateCheckResult result) async {
      final gate = Completer<UpdateCheckResult>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: UpdateCheckButton(service: _FakeService(gate.future)),
            ),
          ),
        ),
      );
      expect(find.byTooltip('检查更新'), findsOneWidget);
      await tester.tap(find.byTooltip('检查更新'));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      gate.complete(result);
      await tester.pumpAndSettle();
    }

    testWidgets('shows dialog when newer version exists', (tester) async {
      await tapWith(tester, const UpdateCheckResult.available(_release));
      expect(find.byType(UpdateDialog), findsOneWidget);
    });

    testWidgets('shows up-to-date message', (tester) async {
      await tapWith(tester, const UpdateCheckResult.upToDate());
      expect(find.text('已是最新版本'), findsOneWidget);
    });

    testWidgets('shows failure message', (tester) async {
      await tapWith(tester, const UpdateCheckResult.failed());
      expect(find.text('检查失败，请稍后再试'), findsOneWidget);
    });
  });
}

class _FakeService extends UpdateService {
  _FakeService(this._result);

  final Future<UpdateCheckResult> _result;

  @override
  Future<UpdateCheckResult> checkNow() => _result;
}
