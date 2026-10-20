import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'update_prompt.dart';

/// 工具栏里的“检查更新”按钮；仅安卓显示，需置于 [UpdatePrompt] 中。
class UpdateCheckButton extends StatefulWidget {
  const UpdateCheckButton({super.key});

  @override
  State<UpdateCheckButton> createState() => _UpdateCheckButtonState();
}

class _UpdateCheckButtonState extends State<UpdateCheckButton> {
  bool _checking = false;

  Future<void> _check() async {
    if (_checking) {
      return;
    }
    setState(() => _checking = true);
    try {
      await UpdatePrompt.checkNow(context);
    } finally {
      if (mounted) {
        setState(() => _checking = false);
      }
    }
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
