import 'package:flutter/material.dart';

import 'alira_frame.dart';

class WebHome extends StatelessWidget {
  const WebHome({super.key});

  @override
  Widget build(BuildContext context) {
    return AliraPhone(
      child: Column(
        children: [
          const AliraStatusBar(
            title: 'سايلر',
            hint: 'المتجر والمندوب',
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(18),
              children: [
                const SizedBox(height: 12),
                AliraSoftCard(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'مرحباً بك',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'اختر المتجر أو دخول المندوب',
                        style: TextStyle(fontSize: 12, color: AliraColors.muted),
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () => Navigator.of(context).pushNamed('/shop'),
                        child: const Text('المتجر'),
                      ),
                      const SizedBox(height: 10),
                      FilledButton(
                        onPressed: () => Navigator.of(context).pushNamed('/agent'),
                        child: const Text('المندوب'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => Navigator.of(context).pushNamed('/photos'),
                  child: const Text('رفع صور المنتجات والموردين'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pushNamed('/follow'),
                  child: const Text('متابعة مدير النظام'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
