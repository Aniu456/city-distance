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
      builder: (_) => _UpdateDialog(release: release, service: service),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog({required this.release, required this.service});

  final AppRelease release;
  final UpdateService service;

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  bool _downloading = false;
  double? _progress;
  String? _error;

  Future<void> _update() async {
    setState(() {
      _downloading = true;
      _progress = null;
      _error = null;
    });
    try {
      final file = await widget.service.download(
        widget.release,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      final ok = await widget.service.install(file);
      if (!mounted) return;
      if (ok) {
        Navigator.of(context).pop();
      } else {
        setState(() {
          _downloading = false;
          _error = '无法打开安装器，请允许“安装未知应用”后重试';
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _error = '下载失败，请检查网络后重试';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final notes = widget.release.notes;
    final progress = _progress;
    return AlertDialog(
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
          onPressed: _downloading ? null : () => Navigator.of(context).pop(),
          child: const Text('稍后'),
        ),
        FilledButton(
          onPressed: _downloading ? null : _update,
          child: const Text('更新'),
        ),
      ],
    );
  }
}
