import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'app.dart';
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
    await Firebase.initializeApp();
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
  // Initialize app attestation (per-device HMAC key for request signing)
  await AppAttestation.instance.init();
  WebSocketService.onAuthExpired = () async {
    await AuthState.instance.logout();
    AppRouter.router.go('/onboarding');
  };
  await _initFirebase();
  await AuthState.instance.init();
  await CacheService.instance.init();
  await StickerCache.instance.init();
  await LockService.instance.init();
  if (firebaseAvailable) {
    await NotificationService().init();
  }
  await StoryService.instance.init();
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
}
