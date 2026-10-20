import 'package:flutter/material.dart';

import 'pages/map_page.dart';
import 'theme/app_colors.dart';

void main() {
  runApp(const ChinaMapApp());
}

class ChinaMapApp extends StatelessWidget {
  const ChinaMapApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '城向',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          primary: AppColors.primary,
          surface: AppColors.background,
        ),
        scaffoldBackgroundColor: AppColors.background,
        useMaterial3: true,
      ),
      home: const MapPage(),
    );
  }
}
