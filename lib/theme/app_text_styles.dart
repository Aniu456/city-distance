import 'package:flutter/painting.dart';

import 'app_colors.dart';

abstract final class AppTextStyles {
  static const title = TextStyle(fontSize: 21, fontWeight: FontWeight.w700);
  static const hint = TextStyle(fontSize: 12, color: AppColors.hintText);
}
