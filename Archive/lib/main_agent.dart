import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'features/alira/presentation/agent_app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AgentApkApp());
}

class AgentApkApp extends StatelessWidget {
  const AgentApkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'مندوب سايلر',
      locale: const Locale('ar'),
      theme: AppTheme.lightTheme,
      home: const Directionality(
        textDirection: TextDirection.rtl,
        child: AliraAgentApp(),
      ),
    );
  }
}
