import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'features/alira/presentation/agent_app.dart';
import 'features/alira/presentation/manager_desk.dart';
import 'features/alira/presentation/photo_desk.dart';
import 'features/alira/presentation/shop_app.dart';
import 'features/alira/presentation/web_home.dart';
import 'web_url.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  configureAppUrl();
  runApp(const WebPagesApp());
}

class WebPagesApp extends StatelessWidget {
  const WebPagesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'سايلر',
      locale: const Locale('ar'),
      theme: AppTheme.lightTheme,
      initialRoute: startRoute(),
      onGenerateRoute: (settings) {
        final name = settings.name ?? '/';
        final Widget page;
        if (name == '/shop') {
          page = const AliraShopApp();
        } else if (name == '/agent') {
          page = const AliraAgentApp();
        } else if (name == '/photos') {
          page = const PhotoDeskPage();
        } else if (name == '/follow') {
          page = const ManagerDeskPage();
        } else {
          page = const WebHome();
        }
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (context) => Directionality(
            textDirection: TextDirection.rtl,
            child: page,
          ),
        );
      },
    );
  }
}
