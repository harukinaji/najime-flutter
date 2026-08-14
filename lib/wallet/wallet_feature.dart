import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/home_screen.dart';
import 'screens/onboarding/onboarding_screen.dart';
import 'screens/splash_screen.dart';
import 'state/app_state.dart';
import 'wallet_media.dart';

/// Embedded Naji Wallet feature entry point.
///
/// Provides the wallet [AppState] and routes between splash, onboarding and
/// the main wallet screen. Media session initialization happens lazily here so
/// the messenger's own startup flow is untouched.
class WalletFeature extends StatefulWidget {
  const WalletFeature({super.key});

  @override
  State<WalletFeature> createState() => _WalletFeatureState();
}

class _WalletFeatureState extends State<WalletFeature> {
  @override
  void initState() {
    super.initState();
    ensureWalletMedia();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState.instance..restoreSession(),
      child: const WalletNavigator(),
    );
  }
}

/// A dedicated navigator for the wallet feature.
///
/// Wallet screens navigate with plain [Navigator.push]/[MaterialPageRoute]
/// calls. Hosting them inside this nested navigator keeps every pushed route
/// underneath the wallet's [ChangeNotifierProvider] so `AppState` stays
/// available to all of them, regardless of the surrounding go_router routes.
class WalletNavigator extends StatelessWidget {
  const WalletNavigator({super.key});

  @override
  Widget build(BuildContext context) {
    return Navigator(
      onGenerateRoute: (settings) {
        if (settings.name == Navigator.defaultRouteName) {
          return MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => const WalletRoot(),
          );
        }
        return null;
      },
    );
  }
}

/// Decides between splash, onboarding, or the main wallet screen.
class WalletRoot extends StatelessWidget {
  const WalletRoot({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (state.loading) return const SplashScreen();
    if (!state.isAuthenticated) return const OnboardingScreen();
    return const HomeScreen();
  }
}
