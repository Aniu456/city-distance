import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'app_release.dart';
import 'update_service.dart';

/// 包住首页，统一管理启动检查、手动检查和更新弹窗。
class UpdatePrompt extends StatefulWidget {
  const UpdatePrompt({super.key, required this.child, this.service});

  final Widget child;
  final UpdateService? service;

  /// 手动检查并显示结果；调用方必须位于 [UpdatePrompt] 的子树中。
  static Future<void> checkNow(BuildContext context) {
    final state = context.findAncestorStateOfType<_UpdatePromptState>();
    if (state == null) {
      throw FlutterError('检查更新的入口必须位于 UpdatePrompt 中。');
    }
    return state._checkManually();
  }

  @override
  State<UpdatePrompt> createState() => _UpdatePromptState();
}

class _UpdatePromptState extends State<UpdatePrompt> {
  late final UpdateService _service;
  Future<void>? _manualCheck;
  bool _manualCheckStarted = false;
  bool _dialogOpen = false;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? UpdateService();
    if (UpdateService.isSupported) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(_checkAutomatically());
        }
      });
    }
  }

  Future<void> _checkAutomatically() async {
    final release = await _service.check();
    if (release == null || !mounted || _manualCheckStarted) {
      return;
    }
    await _showRelease(release);
  }

  Future<void> _checkManually() {
    // 手动检查接管提示，较晚返回的自动请求也不能重新弹窗。
    _manualCheckStarted = true;
    if (_dialogOpen) {
      return Future<void>.value();
    }
    return _manualCheck ??= _runManualCheck().whenComplete(() {
      _manualCheck = null;
    });
  }

  Future<void> _runManualCheck() async {
    final result = await _service.checkNow();
    if (!mounted) {
      return;
    }
    final release = result.release;
    if (result.status == UpdateCheckStatus.available && release != null) {
      // 弹窗由首页继续管理，按钮只等待检查请求结束。
      unawaited(_showRelease(release));
      return;
    }
    final message = result.status == UpdateCheckStatus.upToDate
        ? '已是最新版本'
        : '检查失败，请稍后再试';
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  Future<void> _showRelease(AppRelease release) async {
    if (_dialogOpen) {
      return;
    }
    _dialogOpen = true;
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => UpdateDialog(release: release, service: _service),
      );
    } finally {
      _dialogOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// 新版本弹窗；下载中按返回键或“稍后”会取消下载，且不再打开安装器。
class UpdateDialog extends StatefulWidget {
  const UpdateDialog({super.key, required this.release, required this.service});

  final AppRelease release;
  final UpdateService service;

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  bool _downloading = false;
  double? _progress;
  String? _error;
  UpdateCancelToken? _cancelToken;

  Future<void> _update() async {
    final token = UpdateCancelToken();
    _cancelToken = token;
    setState(() {
      _downloading = true;
      _progress = null;
      _error = null;
    });
    try {
      final file = await widget.service.download(
        widget.release,
        cancelToken: token,
        onProgress: (p) {
          if (mounted && !token.isCancelled) setState(() => _progress = p);
        },
      );
      // 弹窗已关闭或已取消时，绝不打开安装器。
      if (!mounted || token.isCancelled) return;
      final ok = await widget.service.install(file);
      if (!mounted || token.isCancelled) {
        return;
      }
      if (ok) {
        Navigator.of(context).pop();
      } else {
        setState(() {
          _downloading = false;
          _error = '无法打开安装器，请允许“安装未知应用”后重试';
        });
      }
    } catch (_) {
      if (!mounted || token.isCancelled) return;
      setState(() {
        _downloading = false;
        _error = '下载失败，请检查网络后重试';
      });
    }
  }

  void _cancelDownload() {
    _cancelToken?.cancel();
  }

  @override
  void dispose() {
    _cancelDownload();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notes = widget.release.notes;
    final progress = _progress;
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _cancelDownload();
      },
      child: AlertDialog(
        backgroundColor: AppColors.background,
        title: Text('发现新版本 v${widget.release.version}'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 280),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(notes.isEmpty ? '修复问题并改进体验。' : notes),
                if (_downloading) ...[
                  const SizedBox(height: 16),
                  LinearProgressIndicator(value: progress),
                  const SizedBox(height: 6),
                  Text(
                    progress == null
                        ? '正在下载…'
                        : '正在下载 ${(progress * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.hintText,
                    ),
                  ),
                ],
                if (_error case final error?) ...[
                  const SizedBox(height: 12),
                  Text(error, style: const TextStyle(color: Colors.redAccent)),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              _cancelDownload();
              Navigator.of(context).pop();
            },
            child: const Text('稍后'),
          ),
          FilledButton(
            onPressed: _downloading ? null : _update,
            child: const Text('更新'),
          ),
        ],
      ),
    );
  }
}
