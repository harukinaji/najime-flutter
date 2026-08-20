import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../data/auth_state.dart';
import '../screens/onboarding/onboarding_screen.dart';
import '../screens/auth/auth_screen.dart';
import '../screens/auth/login_verify_screen.dart';
import '../screens/auth/login_approval_screen.dart';
import '../screens/auth/setup_profile_screen.dart';
import '../screens/home/home_shell.dart';
import '../screens/chats/chats_screen.dart';
import '../screens/chats/desktop_chats_split.dart';
import '../screens/chats/chat_detail_screen.dart';
import '../screens/chats/create_group_screen.dart';
import '../screens/contacts/contacts_screen.dart';
import '../screens/calls/calls_screen.dart';
import '../screens/profile/profile_screen.dart';
import '../screens/profile/edit_profile_screen.dart';
import '../screens/profile/connected_accounts_screen.dart';
import '../screens/profile/privacy_screen.dart';
import '../screens/profile/notifications_screen.dart';
import '../screens/profile/appearance_screen.dart';
import '../screens/profile/folders_screen.dart';
import '../screens/premium/premium_unlock_screen.dart';
import '../screens/profile/lock_settings_screen.dart';
import '../screens/bots/bot_manager_screen.dart';
import '../screens/bots/mini_app_screen.dart';
import '../screens/stories/story_creation_screen.dart';
import '../screens/stories/story_viewer_screen.dart';
import '../stories/storybook_screen.dart';
import '../wallet/wallet_feature.dart';

import '../data/auth_credentials.dart' show AuthCredentials;

class AppRouter {
  AppRouter._();

  static final rootNavigatorKey = GlobalKey<NavigatorState>();

  static final router = GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/',
    redirect: (context, state) {
      final a = AuthState.instance;
      final loc = state.matchedLocation;
      final isPublic =
          loc == '/' ||
          loc == '/onboarding' ||
          loc.startsWith('/auth');

      if (!a.isAuthenticated && !isPublic) {
        return '/onboarding';
      }

      if (a.isAuthenticated && loc == '/') {
        return '/home/chats';
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/auth',
        builder: (context, state) => const AuthScreen(),
        routes: [
          GoRoute(
            path: 'verify',
            builder: (context, state) {
              final extra = state.extra as Map<String, dynamic>?;
              return LoginVerifyScreen(
                username: extra?['username'] as String? ?? '',
                emailHint: extra?['emailHint'] as String? ?? '',
                password: AuthCredentials.password,
                authTicket: AuthCredentials.authTicket,
              );
            },
          ),
          GoRoute(
            path: 'approval',
            builder: (context, state) {
              final extra = state.extra as Map<String, dynamic>?;
              return LoginApprovalScreen(
                username: extra?['username'] as String? ?? '',
                approvalId: extra?['approvalId'] as String? ?? '',
                pollSecret: AuthCredentials.pollSecret ?? '',
                expiresIn: extra?['expiresIn'] as int? ?? 300,
              );
            },
          ),
          GoRoute(
            path: 'setup',
            builder: (context, state) {
              final extra = state.extra as Map<String, dynamic>?;
              return SetupProfileScreen(
                email: extra?['email'] as String? ?? '',
                idToken: extra?['idToken'] as String? ?? '',
                suggestedNickname: extra?['suggestedNickname'] as String? ?? '',
                displayName: extra?['displayName'] as String?,
                avatarUrl: extra?['avatarUrl'] as String?,
              );
            },
          ),
        ],
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) => HomeShell(
          navigationShell: navigationShell,
        ),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home/chats',
                pageBuilder: (context, state) => NoTransitionPage(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final w = MediaQuery.sizeOf(context).width;
                      if (w >= 900) {
                        return const DesktopChatsSplit();
                      }
                      return const ChatsScreen();
                    },
                  ),
                ),
                routes: [
                  GoRoute(
                    path: 'create-group',
                    parentNavigatorKey: rootNavigatorKey,
                    builder: (context, state) => const CreateGroupScreen(),
                  ),
                  GoRoute(
                    path: ':chatId',
                    parentNavigatorKey: rootNavigatorKey,
                    builder: (context, state) {
                      final extras = state.extra as Map<String, dynamic>?;
                      return ChatDetailScreen(
                        chatId: state.pathParameters['chatId']!,
                        contactId: extras?['contactId'] as String?,
                        isGroup: extras?['isGroup'] as bool? ?? false,
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home/contacts',
                pageBuilder: (context, state) => const NoTransitionPage(
                  child: ContactsScreen(),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home/calls',
                pageBuilder: (context, state) => const NoTransitionPage(
                  child: CallsScreen(),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home/profile',
                pageBuilder: (context, state) => const NoTransitionPage(
                  child: ProfileScreen(),
                ),
                routes: [
                  GoRoute(
                    path: 'edit',
                    parentNavigatorKey: rootNavigatorKey,
                    builder: (context, state) => const EditProfileScreen(),
                  ),
                  GoRoute(
                    path: 'connected-accounts',
                    parentNavigatorKey: rootNavigatorKey,
                    builder: (context, state) =>
                        const ConnectedAccountsScreen(),
                  ),
                  GoRoute(
                    path: 'privacy',
                    parentNavigatorKey: rootNavigatorKey,
                    builder: (context, state) => const PrivacyScreen(),
                  ),
                  GoRoute(
                    path: 'notifications',
                    parentNavigatorKey: rootNavigatorKey,
                    builder: (context, state) => const NotificationsScreen(),
                  ),
                  GoRoute(
                    path: 'appearance',
                    parentNavigatorKey: rootNavigatorKey,
                    builder: (context, state) => const AppearanceScreen(),
                  ),
                  GoRoute(
                    path: 'folders',
                    parentNavigatorKey: rootNavigatorKey,
                    builder: (context, state) => const FoldersScreen(),
                  ),
                  GoRoute(
                    path: 'lock',
                    parentNavigatorKey: rootNavigatorKey,
                    builder: (context, state) => const LockSettingsScreen(),
                  ),
                  GoRoute(
                    path: 'bots',
                    parentNavigatorKey: rootNavigatorKey,
                    builder: (context, state) => const BotManagerScreen(),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home/wallet',
                pageBuilder: (context, state) => const NoTransitionPage(
                  child: WalletFeature(),
                ),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/premium-unlock',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const PremiumUnlockScreen(),
      ),
      GoRoute(
        path: '/story/create',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const StoryCreationScreen(),
      ),
      GoRoute(
        path: '/story/view',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return StoryViewerScreen(
            initialUserId: extra?['initialUserId'] as String? ?? '',
            userIds: (extra?['userIds'] as List?)?.cast<String>() ?? [],
          );
        },
      ),
      GoRoute(
        path: '/storybook',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const StorybookScreen(),
      ),
      GoRoute(
        path: '/mini-app',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return MiniAppScreen(
            url: extra?['url'] as String? ?? '',
            title: extra?['title'] as String? ?? 'Mini App',
          );
        },
      ),
      GoRoute(
        path: '/wallet',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const WalletFeature(),
      ),
    ],
  );
}
