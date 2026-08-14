import 'package:flutter/material.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';
import 'data/websocket_service.dart';
import 'data/auth_state.dart';
import 'data/lock_service.dart';
import 'screens/auth/lock_screen.dart';

class NajiMeApp extends StatefulWidget {
  const NajiMeApp({super.key});

  static void setThemeMode(BuildContext context, ThemeMode mode) {
    final state = context.findAncestorStateOfType<_NajiMeAppState>();
    state?.setThemeMode(mode);
  }

  @override
  State<NajiMeApp> createState() => _NajiMeAppState();
}

class _NajiMeAppState extends State<NajiMeApp> with WidgetsBindingObserver {
  ThemeMode _themeMode = ThemeMode.system;
  bool _isLocked = false;

  void setThemeMode(ThemeMode mode) {
    setState(() {
      _themeMode = mode;
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (LockService.instance.isEnabled && AuthState.instance.isAuthenticated) {
      _isLocked = true;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint('[App] Resumed, checking WS connection...');
      if (AuthState.instance.isAuthenticated && !WebSocketService.isConnected) {
        debugPrint('[App] WS not connected, reconnecting...');
        WebSocketService.reconnect();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'NajiMe',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme(),
      darkTheme: AppTheme.darkTheme(),
      themeMode: _themeMode,
      routerConfig: AppRouter.router,
      builder: (context, child) {
        return Stack(
          children: [
            child ?? const SizedBox.shrink(),
            if (_isLocked)
              Positioned.fill(
                child: Material(
                  color: Colors.black,
                  child: LockScreen(
                    onUnlocked: () {
                      debugPrint('[App] onUnlocked called, setting _isLocked = false');
                      setState(() => _isLocked = false);
                    },
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
