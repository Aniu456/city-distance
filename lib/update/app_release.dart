/// GitHub Release 中与应用更新相关的信息。
class AppRelease {
  const AppRelease({
    required this.version,
    required this.notes,
    required this.apkUrl,
    required this.apkSize,
  });

  /// 去掉前缀 v 的版本号，例如 1.0.1。
  final String version;
  final String notes;
  final String apkUrl;
  final int apkSize;

  /// 解析 releases/latest 接口返回的 JSON；数据不完整时返回 null。
  static AppRelease? fromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    if (json['draft'] == true || json['prerelease'] == true) return null;
    final tag = json['tag_name'];
    if (tag is! String || parseVersion(tag) == null) return null;
    final assets = json['assets'];
    if (assets is! List) return null;
    Map<String, Object?>? picked;
    for (final asset in assets) {
      if (asset is! Map<String, Object?>) continue;
      final name = asset['name'];
      final url = asset['browser_download_url'];
      if (name is! String || url is! String || !name.endsWith('.apk')) continue;
      // 优先通用包（不含 ABI 后缀的文件名）。
      final isUniversal = !RegExp(r'(arm|x86)').hasMatch(name);
      if (picked == null || isUniversal) picked = asset;
      if (isUniversal) break;
    }
    if (picked == null) return null;
    final body = json['body'];
    final size = picked['size'];
    return AppRelease(
      version: normalizeVersion(tag),
      notes: body is String ? body.trim() : '',
      apkUrl: picked['browser_download_url'] as String,
      apkSize: size is int ? size : 0,
    );
  }
}

/// 去掉 v 前缀和 +build 部分。
String normalizeVersion(String raw) {
  var v = raw.trim();
  if (v.startsWith('v') || v.startsWith('V')) v = v.substring(1);
  final plus = v.indexOf('+');
  if (plus >= 0) v = v.substring(0, plus);
  return v;
}

/// 解析成数字列表；格式不合法返回 null。预发布后缀（-beta）会被忽略。
List<int>? parseVersion(String raw) {
  var v = normalizeVersion(raw);
  final dash = v.indexOf('-');
  if (dash >= 0) v = v.substring(0, dash);
  if (v.isEmpty) return null;
  final parts = <int>[];
  for (final p in v.split('.')) {
    final n = int.tryParse(p);
    if (n == null || n < 0) return null;
    parts.add(n);
  }
  return parts;
}

/// remote 比 current 新时返回 true；任一无法解析时返回 false。
bool isNewerVersion(String remote, String current) {
  final r = parseVersion(remote);
  final c = parseVersion(current);
  if (r == null || c == null) return false;
  final len = r.length > c.length ? r.length : c.length;
  for (var i = 0; i < len; i++) {
    final a = i < r.length ? r[i] : 0;
    final b = i < c.length ? c[i] : 0;
    if (a != b) return a > b;
  }
  return false;
}
