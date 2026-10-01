import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'core/di/app_services.dart';
import 'core/network/server_endpoint.dart';
import 'core/theme/app_theme.dart';
import 'core/training_mode.dart';
import 'features/alira/presentation/agent_app.dart';
import 'features/alira/presentation/manager_desk.dart';
import 'features/alira/presentation/photo_desk_stub.dart'
    if (dart.library.html) 'features/alira/presentation/photo_desk.dart';
import 'features/alira/presentation/shop_app.dart';
import 'features/alira/presentation/web_home.dart';
import 'features/auth/presentation/login_screen.dart';
import 'features/dashboard/presentation/desktop_shell.dart';
import 'web_url.dart';

class SalesApp extends StatelessWidget {
  const SalesApp({
    super.key,
  });

  @override
  Widget build(
      BuildContext context,
      ) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'نظام المبيعات',
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
        } else if (kIsWeb && name == '/photos') {
          page = const PhotoDeskPage();
        } else if (kIsWeb && name == '/follow') {
          page = const ManagerDeskPage();
        } else if (kIsWeb) {
          page = const WebHome();
        } else {
          page = const _AuthGate();
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

class _AuthGate extends StatefulWidget {
  const _AuthGate();

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  bool _checkingSession = true;
  bool _loggedIn = false;

  @override
  void initState() {
    super.initState();

    _checkSession();
  }

  // ===========================================================================
  // SESSION CHECK
  // ===========================================================================

  Future<void> _checkSession() async {
    try {
      debugPrint(
        '[AUTH GATE] Checking saved session...',
      );

      if (kSaylerTraining) {
        await AppServices.authRepository.enterLocalOffice();

        if (!mounted) {
          return;
        }

        setState(() {
          _loggedIn = true;
          _checkingSession = false;
        });

        return;
      }

      await ServerEndpoint.instance.ensurePublicOffice();

      final hasSession = await AppServices
          .authRepository
          .activeServerAcceptsSession();

      debugPrint(
        '[AUTH GATE] Saved session exists: $hasSession',
      );

      if (!mounted) {
        return;
      }

      // -----------------------------------------------------------------------
      // مهم:
      //
      // لا ننتظر الـSync هنا.
      //
      // الهدف أن تظهر واجهة البرنامج مباشرة اعتماداً على البيانات المحلية،
      // وبعدها يبدأ الـSync بالخلفية.
      // -----------------------------------------------------------------------

      setState(() {
        _loggedIn = hasSession;
        _checkingSession = false;
      });

      if (hasSession) {
        _startSyncInBackground(
          source: 'saved-session',
        );
      }
    } catch (error, stackTrace) {
      debugPrint(
        '[AUTH GATE] Session check failed: $error',
      );

      debugPrint(
        '[AUTH GATE] StackTrace: $stackTrace',
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _loggedIn = false;
        _checkingSession = false;
      });
    }
  }

  // ===========================================================================
  // BACKGROUND SYNC
  // ===========================================================================

  void _startSyncInBackground({
    required String source,
  }) {
    debugPrint(
      '[AUTH GATE] Starting sync in background...',
    );

    debugPrint(
      '[AUTH GATE] Sync source: $source',
    );

    // -------------------------------------------------------------------------
    // لا نستخدم await.
    //
    // DesktopShell تظهر للمستخدم فوراً،
    // بينما AppServices.startSync() يكمل بالخلفية.
    //
    // unawaited() توضح بشكل صريح أن هذا Future
    // مقصود أن لا ننتظر انتهاءه.
    // -------------------------------------------------------------------------

    unawaited(
      AppServices.startSync().then((_) {
        debugPrint(
          '[AUTH GATE] Background sync started successfully.',
        );
      }).catchError((Object error, StackTrace stackTrace) {
        debugPrint(
          '[AUTH GATE] Background sync failed: $error',
        );

        debugPrint(
          '[AUTH GATE] Background sync StackTrace: $stackTrace',
        );
      }),
    );
  }

  // ===========================================================================
  // LOGIN
  // ===========================================================================

  void _onLoginSuccess() {
    if (!mounted) {
      return;
    }

    // -------------------------------------------------------------------------
    // نظهر DesktopShell أولاً.
    // -------------------------------------------------------------------------

    setState(() {
      _loggedIn = true;
    });

    if (kSaylerTraining) {
      return;
    }

    // -------------------------------------------------------------------------
    // وبعدها نشغل الـSync بالخلفية.
    // -------------------------------------------------------------------------

    _startSyncInBackground(
      source: 'login',
    );
  }

  // ===========================================================================
  // LOGOUT
  // ===========================================================================

  void _onLogout() {
    if (!mounted) {
      return;
    }

    // -------------------------------------------------------------------------
    // ملاحظة:
    //
    // حالياً SyncService يبقى شغال بعد Logout.
    //
    // هذا لا نغيره من app.dart قبل ما نشوف implementation
    // الخاص بـ SyncService و AppServices، حتى ما نخرب lifecycle.
    // لاحقاً نضيف stop صريح إذا كان مدعوم.
    // -------------------------------------------------------------------------

    setState(() {
      _loggedIn = false;
    });
  }

  // ===========================================================================
  // BUILD
  // ===========================================================================

  @override
  Widget build(
      BuildContext context,
      ) {
    if (_checkingSession) {
      return const Scaffold(
        backgroundColor: AppTheme.backgroundColor,
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_loggedIn) {
      return DesktopShell(
        onLogout: _onLogout,
      );
    }

    return LoginScreen(
      onLoginSuccess: _onLoginSuccess,
    );
  }
}