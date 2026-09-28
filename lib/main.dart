import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'app.dart';
import 'l10n/app_localizations.dart';
import 'data/app_attestation.dart';
import 'data/auth_state.dart';
import 'data/cache_service.dart';
import 'data/lock_service.dart';
import 'data/notification_service.dart';
import 'data/sticker_cache.dart';
import 'data/story_service.dart';
import 'data/websocket_service.dart';
import 'router/app_router.dart';
import 'wallet/services/deep_link_service.dart';
import 'wallet/state/app_state.dart';

bool firebaseAvailable = false;

Future<void> _initFirebase() async {
  try {
    await Firebase.initializeApp().timeout(const Duration(seconds: 2));
    firebaseAvailable = true;
    setupBackgroundMessaging();
    debugPrint('[Firebase] Initialized successfully');
  } catch (e) {
    firebaseAvailable = false;
    debugPrint('[Firebase] Skipped (not configured on this platform): $e');
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(isOptional: true);
  // Attestation is initialized lazily before its first authenticated request;
  // Android Keystore access must not delay the first frame.
  WebSocketService.onAuthExpired = () async {
    await AuthState.instance.logout();
    AppRouter.router.go('/onboarding');
  };
  // These are independent local stores. Running them together removes the
  // cumulative secure-storage/filesystem delay on cold start.
  await Future.wait<void>([
    AuthState.instance.init(),
    LockService.instance.init(),
  ]);
  // Disk caches are initialized lazily after the first frame. CacheService
  // operations await its own readiness, so offline reads remain consistent.
  unawaited(CacheService.instance.init());
  unawaited(StickerCache.instance.init());
  AppState.instance.restoreSession();
  WalletDeepLinks.instance.init();
  final a = AuthState.instance;
  if (a.isAuthenticated) {
    StoryService.instance.setCurrentUser(
      id: a.username ?? '',
      name: a.displayName ?? a.username ?? '',
      avatarUrl: a.avatarUrl,
    );
  }
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );
  runApp(const NajiMeApp());
  // Start Firebase only after the first frame. On some Android builds FCM
  // creates a secondary Flutter engine and stalls rasterization for seconds.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(Future<void>.delayed(const Duration(seconds: 5), _initFirebase).then((_) {
      if (firebaseAvailable) unawaited(NotificationService().init());
    }));
  });
}
