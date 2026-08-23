import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';

const Color _primaryQr = Color(0xFF18A7B5);

class QrProfileCard extends StatelessWidget {
  final String data;
  final String? avatarUrl;
  final String displayName;
  final String username;
  final double size;
  final Color qrColor;
  final Color backgroundColor;
  final Color eyeColor;
  final EdgeInsets padding;

  const QrProfileCard({
    super.key,
    required this.data,
    this.avatarUrl,
    required this.displayName,
    required this.username,
    this.size = 280,
    this.qrColor = _primaryQr,
    this.backgroundColor = Colors.white,
    this.eyeColor = _primaryQr,
    this.padding = const EdgeInsets.all(24),
  });

  @override
  Widget build(BuildContext context) {
    final qrSize = size - padding.horizontal;

    final qrCode = QrCode.fromData(
      data: data,
      errorCorrectLevel: QrErrorCorrectLevel.H,
    );
    final qrImage = QrImage(qrCode);

    return Container(
      width: size,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: _primaryQr.withValues(alpha: 0.12),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: _primaryQr.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: _primaryQr.withValues(alpha: 0.04),
            blurRadius: 40,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              padding.left,
              padding.top,
              padding.right,
              0,
            ),
            child: SvgPicture.asset(
              'assets/images/file.svg',
              width: 44,
              height: 44,
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: EdgeInsets.fromLTRB(padding.left, 0, padding.right, 0),
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: qrSize,
                  height: qrSize,
                  child: PrettyQrView(
                    qrImage: qrImage,
                    decoration: PrettyQrDecoration(
                      // ignore: experimental_member_use
                      shape: PrettyQrShape.custom(
                        PrettyQrSmoothSymbol(color: qrColor),
                        finderPattern: PrettyQrSmoothSymbol(color: eyeColor),
                      ),
                    ),
                  ),
                ),
                if (_avatarProvider != null)
                  _buildAvatar(qrSize)
                else
                  _buildAvatarFallback(qrSize),
              ],
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Column(
              children: [
                Text(
                  displayName,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A1A2E),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  '@$username',
                  style: TextStyle(
                    fontSize: 13,
                    color: const Color(0xFF1A1A2E).withValues(alpha: 0.55),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  ImageProvider? get _avatarProvider {
    if (avatarUrl == null || avatarUrl!.isEmpty) return null;
    if (avatarUrl!.startsWith('data:image')) {
      final base64 = avatarUrl!.split(',').last;
      return MemoryImage(base64Decode(base64));
    }
    return NetworkImage(avatarUrl!);
  }

  Widget _buildAvatar(double qrSize) {
    final size = qrSize * 0.2;
    final radius = size * 0.22;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: backgroundColor, width: 2.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Image(
          image: _avatarProvider!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            color: _primaryQr,
            child: Center(
              child: Text(
                displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: size * 0.4,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAvatarFallback(double qrSize) {
    final size = qrSize * 0.2;
    final radius = size * 0.22;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: backgroundColor, width: 2.5),
        gradient: const LinearGradient(
          colors: [_primaryQr, Color(0xFF4ECDC4)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Center(
        child: Text(
          displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
          style: TextStyle(
            color: Colors.white,
            fontSize: size * 0.4,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class QrProfileScreen extends StatefulWidget {
  final String data;
  final String? avatarUrl;
  final String displayName;
  final String username;
  final Color qrColor;
  final Color eyeColor;

  const QrProfileScreen({
    super.key,
    required this.data,
    this.avatarUrl,
    required this.displayName,
    required this.username,
    this.qrColor = _primaryQr,
    this.eyeColor = _primaryQr,
  });

  static void show(
    BuildContext context, {
    required String data,
    String? avatarUrl,
    required String displayName,
    required String username,
    Color qrColor = _primaryQr,
    Color eyeColor = _primaryQr,
  }) {
    Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: true,
        barrierColor: Colors.black,
        barrierLabel: '',
        pageBuilder: (ctx, animation, secondary) => QrProfileScreen(
          data: data,
          avatarUrl: avatarUrl,
          displayName: displayName,
          username: username,
          qrColor: qrColor,
          eyeColor: eyeColor,
        ),
        transitionsBuilder: (ctx, animation, secondary, child) {
          return FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.92, end: 1.0).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
              ),
              child: child,
            ),
          );
        },
        transitionDuration: const Duration(milliseconds: 350),
      ),
    );
  }

  @override
  State<QrProfileScreen> createState() => _QrProfileScreenState();
}

class _QrProfileScreenState extends State<QrProfileScreen> {
  bool _controlsVisible = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _controlsVisible = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF0D2137), Color(0xFF1A3A4A), Color(0xFF0F2A38)],
            ),
          ),
          child: SafeArea(
            child: Stack(
              children: [
                Positioned(
                  top: -80,
                  right: -60,
                  child: Container(
                    width: 200,
                    height: 200,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _primaryQr.withValues(alpha: 0.08),
                    ),
                  ),
                ),
                Positioned(
                  bottom: -40,
                  left: -40,
                  child: Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _primaryQr.withValues(alpha: 0.06),
                    ),
                  ),
                ),
                Positioned(
                  top: 8,
                  left: 8,
                  child: AnimatedOpacity(
                    opacity: _controlsVisible ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 400),
                    child: IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.arrow_back,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                    ),
                  ),
                ),
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      QrProfileCard(
                        data: widget.data,
                        avatarUrl: widget.avatarUrl,
                        displayName: widget.displayName,
                        username: widget.username,
                        qrColor: widget.qrColor,
                        eyeColor: widget.eyeColor,
                      ),
                      const SizedBox(height: 24),
                      AnimatedOpacity(
                        opacity: _controlsVisible ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 600),
                        child: Text(
                          'Scan to view profile',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.white.withValues(alpha: 0.6),
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                      const SizedBox(height: 28),
                      AnimatedOpacity(
                        opacity: _controlsVisible ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 700),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _ActionButton(
                              icon: Icons.file_download_outlined,
                              label: 'Save',
                              onTap: () {},
                            ),
                            const SizedBox(width: 16),
                            _ActionButton(
                              icon: Icons.share_outlined,
                              label: 'Share',
                              onTap: () {},
                            ),
                          ],
                        ),
                      ),
                    ],
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

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: 100,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: Column(
            children: [
              Icon(icon, color: Colors.white, size: 24),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withValues(alpha: 0.8),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
