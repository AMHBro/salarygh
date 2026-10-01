import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

class WebHome extends StatelessWidget {
  const WebHome({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'سايلر',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                const Text(
                  'صفحات الويب',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.secondaryTextColor),
                ),
                const SizedBox(height: 28),
                FilledButton(
                  onPressed: () => Navigator.of(context).pushNamed('/shop'),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('المتجر'),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => Navigator.of(context).pushNamed('/agent'),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('المندوبين'),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pushNamed('/photos'),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('رفع صور المنتجات والموردين'),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pushNamed('/follow'),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('متابعة مدير النظام'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
