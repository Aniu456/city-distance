import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'app_release.dart';
import 'update_service.dart';

/// 包住首页：启动后静默检查一次更新，有新版本才弹窗。
class UpdatePrompt extends StatefulWidget {
  const UpdatePrompt({super.key, required this.child, this.service});

  final Widget child;
  final UpdateService? service;

  @override
  State<UpdatePrompt> createState() => _UpdatePromptState();
}

class _UpdatePromptState extends State<UpdatePrompt> {
  @override
  void initState() {
    super.initState();
    if (UpdateService.isSupported) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _check());
    }
  }

  Future<void> _check() async {
    final service = widget.service ?? UpdateService();
    final release = await service.check();
    if (release == null || !mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => UpdateDialog(release: release, service: service),
    );
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
