import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../data/webrtc_service.dart';
import '../../data/websocket_service.dart';
import '../calls/call_screen.dart';
import '../../models/call.dart';
import '../../theme/app_colors.dart';
import '../../utils/platform.dart';

class HomeShell extends StatefulWidget {
  final StatefulNavigationShell navigationShell;

  const HomeShell({super.key, required this.navigationShell});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell>
    with SingleTickerProviderStateMixin {
  int get _currentIndex => widget.navigationShell.currentIndex;

  OverlayEntry? _groupCallOverlay;

  @override
  void initState() {
    super.initState();
    WebRTCService.onIncomingCall = _onIncomingCall;
    WebSocketService.on('group_call_started', _onGroupCallStarted);
    WebSocketService.on('group_call_ended', _onGroupCallEnded);
  }

  @override
  void dispose() {
    _removeGroupCallOverlay();
    WebSocketService.off('group_call_started', _onGroupCallStarted);
    WebSocketService.off('group_call_ended', _onGroupCallEnded);
    super.dispose();
  }

  void _removeGroupCallOverlay() {
    _groupCallOverlay?.remove();
    _groupCallOverlay = null;
  }

  void _onGroupCallStarted(dynamic data) {
    if (!mounted || data is! Map) return;
    final roomId = data['room_id'] as String?;
    final callerId = data['caller_id'] as String?;
    final callerName = data['caller_name'] as String? ?? 'Unknown';
    final callType = data['call_type'] as String? ?? 'voice';
    final chatName = data['chat_name'] as String? ?? '';
    if (roomId == null || callerId == null) return;

    if (_groupCallOverlay != null) return;

    _groupCallOverlay = OverlayEntry(
      builder: (context) => _GroupCallOverlay(
        roomId: roomId,
        callerId: callerId,
        callerName: callerName,
        callType: callType,
        chatName: chatName,
        onAccept: () {
          _removeGroupCallOverlay();
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => CallScreen(
                contactId: callerId,
                contactName: chatName.isNotEmpty ? chatName : callerName,
                callType: callType == 'video'
                    ? CallType.video
                    : CallType.voice,
                isIncoming: true,
                autoAccept: true,
                useSFU: true,
                roomId: roomId,
              ),
            ),
          );
        },
        onDecline: () {
          _removeGroupCallOverlay();
        },
      ),
    );

    Overlay.of(context).insert(_groupCallOverlay!);
  }

  void _onGroupCallEnded(dynamic data) {
    if (data is! Map) return;
    _removeGroupCallOverlay();
  }

  void _onIncomingCall(IncomingCallData data) {
    if (!mounted) return;

    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Incoming Call',
      transitionDuration: const Duration(milliseconds: 400),
      pageBuilder: (ctx, animation, secondaryAnimation) {
        return _IncomingCallOverlay(data: data);
      },
      transitionBuilder: (ctx, animation, secondaryAnimation, child) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).animate(CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          )),
          child: FadeTransition(
            opacity: animation,
            child: child,
          ),
        );
      },
    );
  }

  void _onTap(int index) {
    widget.navigationShell.goBranch(
      index,
      initialLocation: index == widget.navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isDesktop) {
      return _buildDesktopLayout(context);
    }
    return _buildMobileLayout(context);
  }

  Widget _buildDesktopLayout(BuildContext context) {
    return Scaffold(
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildDesktopNavigationRail(context),
          Expanded(child: widget.navigationShell),
        ],
      ),
    );
  }

  Widget _buildDesktopNavigationRail(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return NavigationRail(
      selectedIndex: _currentIndex,
      onDestinationSelected: _onTap,
      labelType: NavigationRailLabelType.all,
      backgroundColor: cs.surface,
      indicatorColor: cs.primary.withValues(alpha: 0.15),
      leading: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primary, Color(0xFF0F766E)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            padding: const EdgeInsets.all(9),
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
      ),
      destinations: const [
        NavigationRailDestination(
          icon: Icon(Icons.chat_bubble_outline),
          selectedIcon: Icon(Icons.chat_bubble),
          label: Text('Chats'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.people_outline),
          selectedIcon: Icon(Icons.people),
          label: Text('Contacts'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.call_outlined),
          selectedIcon: Icon(Icons.call),
          label: Text('Calls'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.person_outline),
          selectedIcon: Icon(Icons.person),
          label: Text('Profile'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.account_balance_wallet_outlined),
          selectedIcon: Icon(Icons.account_balance_wallet),
          label: Text('Wallet'),
        ),
      ],
    );
  }

  Widget _buildMobileLayout(BuildContext context) {
    return Scaffold(
      body: widget.navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: _onTap,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: 'Chats',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: 'Contacts',
          ),
          NavigationDestination(
            icon: Icon(Icons.call_outlined),
            selectedIcon: Icon(Icons.call),
            label: 'Calls',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_balance_wallet_outlined),
            selectedIcon: Icon(Icons.account_balance_wallet),
            label: 'Wallet',
          ),
        ],
      ),
    );
  }
}

class _GroupCallOverlay extends StatefulWidget {
  final String roomId;
  final String callerId;
  final String callerName;
  final String callType;
  final String chatName;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const _GroupCallOverlay({
    required this.roomId,
    required this.callerId,
    required this.callerName,
    required this.callType,
    required this.chatName,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  State<_GroupCallOverlay> createState() => _GroupCallOverlayState();
}

class _GroupCallOverlayState extends State<_GroupCallOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseAnim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isVideo = widget.callType == 'video';
    final displayName =
        widget.chatName.isNotEmpty ? widget.chatName : widget.callerName;

    return Material(
      color: Colors.black54,
      child: SafeArea(
        child: Column(
          children: [
            const Spacer(flex: 2),
            Stack(
              alignment: Alignment.center,
              children: [
                AnimatedBuilder(
                  animation: _pulseAnim,
                  builder: (context, child) {
                    final scale = 1.0 + _pulseAnim.value * 0.15;
                    final alpha =
                        (0.2 - _pulseAnim.value * 0.12).clamp(0.0, 1.0);
                    return Container(
                      width: 180 * scale,
                      height: 180 * scale,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: (isVideo ? Colors.blue : AppColors.primary)
                            .withValues(alpha: alpha),
                      ),
                    );
                  },
                ),
                Container(
                  width: 130,
                  height: 130,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        AppColors.primary,
                        AppColors.primary.withValues(alpha: 0.6),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.4),
                        blurRadius: 30,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: Center(
                    child: Icon(
                      isVideo ? Icons.videocam : Icons.group,
                      size: 48,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              displayName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              '${widget.callerName} is calling',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isVideo ? Icons.videocam : Icons.phone,
                    size: 16,
                    color: Colors.white.withValues(alpha: 0.6),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Group ${isVideo ? "Video" : "Voice"} Call',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(flex: 3),
            Padding(
              padding: const EdgeInsets.only(bottom: 60),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _IncomingCallButton(
                    icon: Icons.call_end,
                    label: 'Decline',
                    color: Colors.red,
                    size: 72,
                    onTap: widget.onDecline,
                  ),
                  const SizedBox(width: 64),
                  _IncomingCallButton(
                    icon: Icons.call,
                    label: 'Join',
                    color: Colors.green,
                    size: 72,
                    onTap: widget.onAccept,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IncomingCallOverlay extends StatefulWidget {
  final IncomingCallData data;

  const _IncomingCallOverlay({required this.data});

  @override
  State<_IncomingCallOverlay> createState() => _IncomingCallOverlayState();
}

class _IncomingCallOverlayState extends State<_IncomingCallOverlay>
    with TickerProviderStateMixin {
  late AnimationController _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseAnim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final isVideo = data.video;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFF0D1B2A),
            const Color(0xFF000000),
          ],
        ),
      ),
      child: SafeArea(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Column(
            children: [
              const Spacer(flex: 2),
              Stack(
                alignment: Alignment.center,
                children: [
                  AnimatedBuilder(
                    animation: _pulseAnim,
                    builder: (context, child) {
                      final scale = 1.0 + _pulseAnim.value * 0.15;
                      final alpha = (0.2 - _pulseAnim.value * 0.12).clamp(0.0, 1.0);
                      return Container(
                        width: 180 * scale,
                        height: 180 * scale,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: (isVideo ? Colors.blue : AppColors.primary)
                              .withValues(alpha: alpha),
                        ),
                      );
                    },
                  ),
                  Container(
                    width: 130,
                    height: 130,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [
                          AppColors.primary,
                          AppColors.primary.withValues(alpha: 0.6),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.4),
                          blurRadius: 30,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                    child: Center(
                      child: Icon(
                        isVideo ? Icons.videocam : Icons.phone,
                        size: 48,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              Text(
                data.contactName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isVideo ? Icons.videocam : Icons.phone,
                      size: 16,
                      color: Colors.white.withValues(alpha: 0.6),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Incoming ${isVideo ? "Video" : "Voice"} Call',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(flex: 3),
              Padding(
                padding: const EdgeInsets.only(bottom: 60),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _IncomingCallButton(
                      icon: Icons.call_end,
                      label: 'Decline',
                      color: Colors.red,
                      size: 72,
                      onTap: () {
                        Navigator.pop(context);
                        WebRTCService.declineIncomingCall();
                      },
                    ),
                    const SizedBox(width: 64),
                    _IncomingCallButton(
                      icon: Icons.call,
                      label: 'Accept',
                      color: Colors.green,
                      size: 72,
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => CallScreen(
                              contactId: data.contactId,
                              contactName: data.contactName,
                              callType: data.video
                                  ? CallType.video
                                  : CallType.voice,
                              isIncoming: true,
                              autoAccept: true,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IncomingCallButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final double size;
  final VoidCallback onTap;

  const _IncomingCallButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.size,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.2),
              border: Border.all(
                color: color.withValues(alpha: 0.3),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.3),
                  blurRadius: 16,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Icon(icon, color: color, size: size * 0.45),
          ),
          const SizedBox(height: 10),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
