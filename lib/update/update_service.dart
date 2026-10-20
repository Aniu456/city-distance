import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_release.dart';

/// 取消一次下载：关闭连接并删除未完成的文件。
class UpdateCancelToken {
  bool _cancelled = false;
  final _listeners = <void Function()>[];

  bool get isCancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final listener in List.of(_listeners)) {
      listener();
    }
    _listeners.clear();
  }

  void _onCancel(void Function() listener) {
    if (_cancelled) {
      listener();
    } else {
      _listeners.add(listener);
    }
  }
}

/// 下载被取消时抛出。
class UpdateCancelledException implements Exception {
  const UpdateCancelledException();
}

typedef ApkInstaller = Future<bool> Function(File apk);

/// 通过 GitHub Releases 检查与下载安卓更新。
class UpdateService {
  UpdateService({
    http.Client? client,
    http.Client Function()? downloadClientFactory,
    ApkInstaller? installer,
    Future<Directory> Function()? downloadDirectory,
    this.connectTimeout = const Duration(seconds: 15),
    this.idleTimeout = const Duration(seconds: 30),
  }) : _client = client ?? http.Client(),
       _downloadClientFactory = downloadClientFactory ?? http.Client.new,
       _installer = installer ?? _openInstaller,
       _downloadDirectory = downloadDirectory ?? getTemporaryDirectory;

  static const latestUrl =
      'https://api.github.com/repos/Aniu456/city-distance/releases/latest';
  static const _lastCheckKey = 'update.lastCheckMs';
  static const checkInterval = Duration(days: 1);

  /// 建立连接并收到响应头的最长等待。
  final Duration connectTimeout;

  /// 两个数据块之间允许的最长空闲。
  final Duration idleTimeout;

  final http.Client _client;
  final http.Client Function() _downloadClientFactory;
  final ApkInstaller _installer;
  final Future<Directory> Function() _downloadDirectory;

  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// 有新版本时返回它；未到检查间隔、网络失败或已是最新时返回 null。
  Future<AppRelease?> check({bool force = false}) async {
    if (!isSupported) return null;
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now().millisecondsSinceEpoch;
      final last = prefs.getInt(_lastCheckKey) ?? 0;
      if (!force && now - last < checkInterval.inMilliseconds) return null;
      final res = await _client
          .get(
            Uri.parse(latestUrl),
            headers: const {'Accept': 'application/vnd.github+json'},
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      await prefs.setInt(_lastCheckKey, now);
      final release = AppRelease.fromJson(jsonDecode(res.body));
      if (release == null) return null;
      final info = await PackageInfo.fromPlatform();
      return isNewerVersion(release.version, info.version) ? release : null;
    } catch (_) {
      return null;
    }
  }

  /// 下载 APK，onProgress 取值 0..1（大小未知时为 null）。
  ///
  /// 超时抛出 [TimeoutException]，取消抛出 [UpdateCancelledException]；
  /// 两种情况和其他失败一样，都会删除未完成的文件。
  Future<File> download(
    AppRelease release, {
    required void Function(double? progress) onProgress,
    UpdateCancelToken? cancelToken,
  }) async {
    final token = cancelToken ?? UpdateCancelToken();
    if (token.isCancelled) throw const UpdateCancelledException();
    final dir = await _downloadDirectory();
    final file = File('${dir.path}/chengxiang-${release.version}.apk');
    final client = _downloadClientFactory();
    final done = Completer<void>();
    StreamSubscription<List<int>>? sub;
    IOSink? sink;

    void fail(Object error) {
      if (!done.isCompleted) done.completeError(error);
    }

    token._onCancel(() {
      client.close();
      sub?.cancel();
      fail(const UpdateCancelledException());
    });

    try {
      final responseFuture = client
          .send(http.Request('GET', Uri.parse(release.apkUrl)))
          .timeout(connectTimeout);
      final res = await Future.any([
        responseFuture,
        done.future.then<http.StreamedResponse>(
          (_) => throw const UpdateCancelledException(),
        ),
      ]);
      if (token.isCancelled) throw const UpdateCancelledException();
      if (res.statusCode != 200) {
        throw HttpException('下载失败（${res.statusCode}）');
      }
      final total = res.contentLength ?? release.apkSize;
      final out = file.openWrite();
      sink = out;
      var received = 0;
      sub = res.stream
          .timeout(idleTimeout)
          .listen(
            (chunk) {
              out.add(chunk);
              received += chunk.length;
              onProgress(total > 0 ? received / total : null);
            },
            onError: (Object e) {
              sub?.cancel();
              fail(e);
            },
            onDone: () {
              if (!done.isCompleted) done.complete();
            },
            cancelOnError: true,
          );
      await done.future;
      await out.close();
      sink = null;
      if (token.isCancelled) throw const UpdateCancelledException();
      return file;
    } catch (_) {
      await sub?.cancel();
      try {
        await sink?.close();
      } catch (_) {}
      if (await file.exists()) await file.delete();
      rethrow;
    } finally {
      client.close();
    }
  }

  /// 打开系统安装器；安卓 8+ 首次会引导用户允许“安装未知应用”。
  Future<bool> install(File apk) => _installer(apk);

  static Future<bool> _openInstaller(File apk) async {
    final result = await OpenFilex.open(
      apk.path,
      type: 'application/vnd.android.package-archive',
    );
    return result.type == ResultType.done;
  }
}
