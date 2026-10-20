import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
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

  for (final useBack in [false, true]) {
    testWidgets('late installer result does not pop the page after '
        '${useBack ? 'system back' : 'later button'}', (tester) async {
      final observer = _PopObserver();
      final installer = _PendingInstaller();
      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [observer],
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (context) => Scaffold(
                      body: TextButton(
                        onPressed: () => showDialog<void>(
                          context: context,
                          builder: (_) => UpdateDialog(
                            release: _release,
                            service: installer,
                          ),
                        ),
                        child: const Text('map page'),
                      ),
                    ),
                  ),
                ),
                child: const Text('open map'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open map'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('map page'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('更新'));
      await tester.pump();
      expect(installer.calls, 1);
      if (useBack) {
        await tester.binding.handlePopRoute();
      } else {
        await tester.tap(find.text('稍后'));
      }
      // 在退出动画结束前返回；此时 mounted 仍为 true。
      installer.result.complete(true);
      await tester.pumpAndSettle();
      expect(observer.pops, 1);
      expect(find.text('map page'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  group('UpdateCheckButton', () {
    Future<void> tapWith(WidgetTester tester, UpdateCheckResult result) async {
      final gate = Completer<UpdateCheckResult>();
      await tester.pumpWidget(
        MaterialApp(
          home: UpdatePrompt(
            service: _FakeService(gate.future),
            child: const Scaffold(body: Center(child: UpdateCheckButton())),
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

  group('UpdatePrompt coordination', () {
    Future<void> start(WidgetTester tester, _PendingChecks service) async {
      await tester.pumpWidget(
        MaterialApp(
          home: UpdatePrompt(
            service: service,
            child: const Scaffold(body: UpdateCheckButton()),
          ),
        ),
      );
    }

    for (final automaticFirst in [false, true]) {
      testWidgets('concurrent checks show one dialog when '
          '${automaticFirst ? 'automatic' : 'manual'} finishes first', (
        tester,
      ) async {
        final service = _PendingChecks();
        await start(tester, service);
        await tester.tap(find.byTooltip('检查更新'));
        await tester.pump();
        if (automaticFirst) {
          service.automatic.complete(_release);
        } else {
          service.manual.complete(const UpdateCheckResult.available(_release));
        }
        await tester.pump();
        if (automaticFirst) {
          service.manual.complete(const UpdateCheckResult.available(_release));
        } else {
          service.automatic.complete(_release);
        }
        await tester.pumpAndSettle();
        expect(find.byType(UpdateDialog, skipOffstage: false), findsOneWidget);
        await tester.tap(find.text('稍后'));
        await tester.pumpAndSettle();
        expect(find.byType(UpdateDialog, skipOffstage: false), findsNothing);
        expect(tester.takeException(), isNull);
      }, variant: TargetPlatformVariant.only(TargetPlatform.android));
    }

    testWidgets('late automatic result does not reopen a dismissed dialog', (
      tester,
    ) async {
      final service = _PendingChecks();
      await start(tester, service);
      await tester.tap(find.byTooltip('检查更新'));
      service.manual.complete(const UpdateCheckResult.available(_release));
      await tester.pumpAndSettle();
      await tester.tap(find.text('稍后'));
      await tester.pumpAndSettle();
      service.automatic.complete(_release);
      await tester.pumpAndSettle();
      expect(find.byType(UpdateDialog, skipOffstage: false), findsNothing);
      // 旧的自动结果被忽略，但用户仍可再次主动检查。
      await tester.tap(find.byTooltip('检查更新'));
      await tester.pumpAndSettle();
      expect(service.manualCalls, 2);
      expect(find.byType(UpdateDialog, skipOffstage: false), findsOneWidget);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));

    testWidgets('automatic check still prompts without a manual request', (
      tester,
    ) async {
      final service = _PendingChecks();
      await start(tester, service);
      service.automatic.complete(_release);
      await tester.pumpAndSettle();
      expect(find.byType(UpdateDialog, skipOffstage: false), findsOneWidget);
      expect(service.manualCalls, 0);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));

    testWidgets('recreated manual entry shares the pending check', (
      tester,
    ) async {
      final service = _PendingChecks();
      final entry = ValueNotifier(0);
      addTearDown(entry.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: UpdatePrompt(
            service: service,
            child: Scaffold(
              body: ValueListenableBuilder<int>(
                valueListenable: entry,
                builder: (_, value, _) =>
                    UpdateCheckButton(key: ValueKey(value)),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('检查更新'));
      await tester.pump();
      entry.value++;
      await tester.pump();
      await tester.tap(find.byTooltip('检查更新'));
      await tester.pump();
      expect(service.manualCalls, 1);
      service.manual.complete(const UpdateCheckResult.available(_release));
      await tester.pumpAndSettle();
      expect(find.byType(UpdateDialog, skipOffstage: false), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

class _FakeService extends UpdateService {
  _FakeService(this._result);

  final Future<UpdateCheckResult> _result;

  @override
  Future<AppRelease?> check({bool force = false}) async => null;

  @override
  Future<UpdateCheckResult> checkNow() => _result;
}

class _PendingInstaller extends UpdateService {
  final result = Completer<bool>();
  int calls = 0;

  @override
  Future<File> download(
    AppRelease release, {
    required void Function(double? progress) onProgress,
    UpdateCancelToken? cancelToken,
  }) async => File('/unused-review.apk');

  @override
  Future<bool> install(File apk) {
    calls++;
    return result.future;
  }
}

class _PopObserver extends NavigatorObserver {
  int pops = 0;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pops++;
  }
}

class _PendingChecks extends UpdateService {
  final automatic = Completer<AppRelease?>();
  final manual = Completer<UpdateCheckResult>();
  int manualCalls = 0;

  @override
  Future<AppRelease?> check({bool force = false}) => automatic.future;

  @override
  Future<UpdateCheckResult> checkNow() {
    manualCalls++;
    return manual.future;
  }
}
