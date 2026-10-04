import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../data/api_service.dart';
import '../../data/auth_state.dart';
import '../../data/google_oauth_flow.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/platform.dart';
import '../../widgets/auth_buttons.dart';
import '../../data/auth_credentials.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeGoogle;
  late final Animation<double> _fadeEmail;

  bool _isRegister = false;
  bool _googleLoading = false;
  bool _emailLoading = false;
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  static final _googleSignIn = GoogleSignIn(
    scopes: ['email'],
    // Android obtains its OAuth client from google-services.json. Passing the
    // Android client ID here overrides plugin discovery and can produce
    // ApiException 10 on release builds. The web client is used only as the
    // ID-token audience consumed by the backend.
    serverClientId:
        '18846067823-8g31lqvrvnkcbitnau6ga8kuad783as9.apps.googleusercontent.com',
  );

  void _navigateToHome() {
    context.go('/home/chats');
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() => _googleLoading = true);

    String? idToken;
    String? email;
    String? displayName;
    String? photoUrl;

    try {
      if (isDesktop) {
        final result = await GoogleOAuthFlow.signIn();
        if (result == null) {
          if (!mounted) return;
          setState(() => _googleLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                AppLocalizations.of(context).translate('auth.googleCancelled'),
              ),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
          return;
        }
        idToken = result.idToken;
        email = result.email;
        displayName = result.displayName;
        photoUrl = result.photoUrl;
      } else {
        final googleUser = await _googleSignIn.signIn();
        if (googleUser == null) {
          if (!mounted) return;
          setState(() => _googleLoading = false);
          return;
        }

        final auth = await googleUser.authentication;
        idToken = auth.idToken;
        email = googleUser.email;
        displayName = googleUser.displayName;
        photoUrl = googleUser.photoUrl;
      }

      if (idToken == null) {
        if (!mounted) return;
        setState(() => _googleLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context).translate('auth.googleFailedToken'),
            ),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
        return;
      }

      final result = await ApiService.loginWithGoogle(idToken, email: email);

      if (!mounted) return;
      setState(() => _googleLoading = false);

      if (result.success) {
        AuthState.instance.saveSession(
          token: result.token ?? '',
          username: result.username ?? '',
          displayName: result.displayName ?? displayName,
          email: result.email ?? email,
          bio: result.bio,
          avatarUrl: result.avatarUrl ?? photoUrl,
        );
        _navigateToHome();
      } else if (result.needsRegistration) {
        final regEmail = result.email ?? email;
        final localPart = (regEmail ?? '').split('@').first;
        final prefix = localPart.replaceAll(RegExp(r'[\d]+$'), '');
        final suggested = prefix.isNotEmpty ? prefix : localPart;
        if (!mounted) return;
        context.push(
          '/auth/setup',
          extra: {
            'email': regEmail,
            'idToken': idToken,
            'suggestedNickname': suggested,
            'displayName': displayName ?? suggested,
            'avatarUrl': photoUrl,
          },
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.message ??
                  AppLocalizations.of(
                    context,
                  ).translate('auth.googleSignInFailed'),
            ),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Auth] Google Sign-In failed: $e');
      if (!mounted) return;
      setState(() => _googleLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${AppLocalizations.of(context).translate('auth.googleSignInFailed')}: $e',
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _handleSignIn() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) return;

    setState(() => _emailLoading = true);

    final result = await AuthState.instance.login(email, password);

    if (!mounted) return;
    setState(() => _emailLoading = false);

    if (result.success) {
      context.go('/home/chats');
    } else if (result.require2fa && result.emailHint != null) {
      AuthCredentials.password = password;
      AuthCredentials.authTicket = result.authTicket;
      context.push(
        '/auth/verify',
        extra: {'username': result.username, 'emailHint': result.emailHint},
      );
    } else if (result.require2fa && result.authMethod == 'mobile_approval') {
      AuthCredentials.pollSecret = result.pollSecret;
      context.push(
        '/auth/approval',
        extra: {
          'username': result.username,
          'approvalId': result.approvalId,
          'expiresIn': result.expiresIn ?? 300,
        },
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.message ??
                AppLocalizations.of(context).translate('auth.loginFailed'),
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _handleDemoSignIn() async {
    await AuthState.instance.startDemoSession();
    if (mounted) context.go('/home/chats');
  }

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _fadeGoogle = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
    );
    _fadeEmail = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.3, 0.8, curve: Curves.easeOut),
    );

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      body: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(cs),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 32),
                  FadeTransition(
                    opacity: _fadeEmail,
                    child: _buildEmailForm(cs),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
            _buildBottomBlock(cs),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBlock(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.fromLTRB(32, 20, 32, 32),
      decoration: BoxDecoration(
        color: cs.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FadeTransition(
            opacity: _fadeGoogle,
            child: GoogleSignInButton(
              onPressed: _googleLoading ? null : _handleGoogleSignIn,
              loading: _googleLoading,
            ),
          ),
          const SizedBox(height: 12),
          _buildDivider(cs),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _emailLoading || _googleLoading
                  ? null
                  : _handleDemoSignIn,
              icon: const Icon(Icons.science_outlined),
              label: const Text('Войти под тестовым аккаунтом'),
              style: OutlinedButton.styleFrom(
                foregroundColor: cs.primary,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Моковые данные, кошелёк создаётся отдельно вами',
            textAlign: TextAlign.center,
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
          ),
          const SizedBox(height: 16),
          _buildTermsText(cs),
        ],
      ),
    );
  }

  Widget _buildEmailForm(ColorScheme cs) {
    return Column(
      children: [
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(
            hintText: AppLocalizations.of(context).translate('auth.email'),
            prefixIcon: Icon(Icons.email_outlined, color: cs.onSurfaceVariant),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _passwordController,
          obscureText: _obscurePassword,
          decoration: InputDecoration(
            hintText: AppLocalizations.of(context).translate('auth.password'),
            prefixIcon: Icon(Icons.lock_outline, color: cs.onSurfaceVariant),
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword ? Icons.visibility_off : Icons.visibility,
                color: cs.onSurfaceVariant,
              ),
              onPressed: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () {},
            child: Text(
              AppLocalizations.of(context).translate('auth.forgotPassword'),
              style: TextStyle(color: cs.primary, fontSize: 13),
            ),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _emailLoading ? null : _handleSignIn,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF18A7B5),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _emailLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    _isRegister
                        ? AppLocalizations.of(
                            context,
                          ).translate('auth.createAccount')
                        : AppLocalizations.of(context).translate('auth.signIn'),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => setState(() => _isRegister = !_isRegister),
          child: Text(
            _isRegister
                ? AppLocalizations.of(
                    context,
                  ).translate('auth.alreadyHaveAccount')
                : AppLocalizations.of(
                    context,
                  ).translate('auth.dontHaveAccount'),
            style: TextStyle(color: cs.primary, fontSize: 13),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(ColorScheme cs) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 40,
        bottom: 48,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [cs.primary, cs.primary.withValues(alpha: 0.7)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Padding(
              padding: const EdgeInsets.all(5),
              child: SvgPicture.asset(
                'assets/images/file.svg',
                fit: BoxFit.contain,
                colorFilter: const ColorFilter.mode(
                  Colors.white,
                  BlendMode.srcIn,
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'NajiMe',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            AppLocalizations.of(context).translate('auth.signInToContinue'),
            style: TextStyle(
              fontSize: 16,
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider(ColorScheme cs) {
    return Row(
      children: [
        Expanded(child: Divider(color: cs.outlineVariant)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            AppLocalizations.of(context).translate('auth.or'),
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(child: Divider(color: cs.outlineVariant)),
      ],
    );
  }

  Widget _buildTermsText(ColorScheme cs) {
    final l10n = AppLocalizations.of(context);
    return Text.rich(
      TextSpan(
        text: l10n.translate('auth.termsPrefix'),
        style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
        children: [
          TextSpan(
            text: l10n.translate('auth.termsOfService'),
            style: TextStyle(color: cs.primary, fontWeight: FontWeight.w500),
          ),
          TextSpan(text: l10n.translate('auth.and')),
          TextSpan(
            text: l10n.translate('auth.privacyPolicy'),
            style: TextStyle(color: cs.primary, fontWeight: FontWeight.w500),
          ),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }
}
