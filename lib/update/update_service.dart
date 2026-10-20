import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_release.dart';

/// 通过 GitHub Releases 检查与下载安卓更新。
class UpdateService {
  UpdateService({http.Client? client}) : _client = client ?? http.Client();

  static const latestUrl =
      'https://api.github.com/repos/Aniu456/city-distance/releases/latest';
  static const _lastCheckKey = 'update.lastCheckMs';
  static const checkInterval = Duration(days: 1);

  final http.Client _client;

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
  Future<File> download(
    AppRelease release, {
    required void Function(double? progress) onProgress,
  }) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/chengxiang-${release.version}.apk');
    final res = await _client.send(
      http.Request('GET', Uri.parse(release.apkUrl)),
    );
    if (res.statusCode != 200) {
      throw HttpException('下载失败（${res.statusCode}）');
    }
    final total = res.contentLength ?? release.apkSize;
    final sink = file.openWrite();
    var received = 0;
    try {
      await for (final chunk in res.stream) {
        sink.add(chunk);
        received += chunk.length;
        onProgress(total > 0 ? received / total : null);
      }
    } finally {
      await sink.close();
    }
    return file;
  }

  /// 打开系统安装器；安卓 8+ 首次会引导用户允许“安装未知应用”。
  Future<bool> install(File apk) async {
    final result = await OpenFilex.open(
      apk.path,
      type: 'application/vnd.android.package-archive',
    );
    return result.type == ResultType.done;
  }
}
