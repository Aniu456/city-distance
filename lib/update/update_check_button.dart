import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'update_prompt.dart';
import 'update_service.dart';

/// 工具栏里的“检查更新”按钮；仅安卓显示。
class UpdateCheckButton extends StatefulWidget {
  const UpdateCheckButton({super.key, this.service});

  final UpdateService? service;

  @override
  State<UpdateCheckButton> createState() => _UpdateCheckButtonState();
}

class _UpdateCheckButtonState extends State<UpdateCheckButton> {
  bool _checking = false;

  Future<void> _check() async {
    if (_checking) return;
    setState(() => _checking = true);
    final service = widget.service ?? UpdateService();
    final result = await service.checkNow();
    if (!mounted) return;
    setState(() => _checking = false);
    final release = result.release;
    if (result.status == UpdateCheckStatus.available && release != null) {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => UpdateDialog(release: release, service: service),
      );
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

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: '检查更新',
    onPressed: _checking ? null : _check,
    style: IconButton.styleFrom(
      minimumSize: const Size(40, 40),
      maximumSize: const Size(40, 40),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: EdgeInsets.zero,
      foregroundColor: AppColors.label,
    ),
    icon: _checking
        ? const SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Icon(Icons.system_update_outlined, size: 18),
  );
}
