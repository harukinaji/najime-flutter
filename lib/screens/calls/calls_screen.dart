import 'dart:convert';
import 'package:flutter/material.dart';

import '../../data/api_service.dart';
import '../../models/call.dart';
import 'call_screen.dart';

class CallsScreen extends StatefulWidget {
  const CallsScreen({super.key});

  @override
  State<CallsScreen> createState() => _CallsScreenState();
}

class _CallsScreenState extends State<CallsScreen> {
  List<CallModel> _calls = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadCalls();
  }

  Future<void> _loadCalls() async {
    if (!mounted) return;
    setState(() => _loading = true);
    final raw = await ApiService.getCalls();
    if (!mounted) return;
    _calls = raw.map((c) {
      CallType type = CallType.voice;
      if (c['type'] == 'video') type = CallType.video;

      CallStatus status = CallStatus.answered;
      switch (c['status']) {
        case 'missed':
          status = CallStatus.missed;
          break;
        case 'incoming':
          status = CallStatus.incoming;
          break;
        case 'outgoing':
          status = CallStatus.outgoing;
          break;
        case 'answered':
          status = CallStatus.answered;
          break;
      }

      Duration? duration;
      if (c['duration_seconds'] != null) {
        duration = Duration(seconds: (c['duration_seconds'] as num).toInt());
      }

      return CallModel(
        id: c['id'] as String,
        contactId: c['contact_id'] as String,
        contactName: c['contact_name'] as String? ?? '',
        contactAvatar: c['contact_avatar'] as String?,
        type: type,
        status: status,
        timestamp: DateTime.parse(c['timestamp'] as String),
        duration: duration,
      );
    }).toList();
    _loading = false;
    setState(() {});
  }

  String _formatTimestamp(DateTime timestamp) {
    final diff = DateTime.now().difference(timestamp);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  String _formatDuration(Duration d) {
    if (d.inHours > 0) {
      return '${d.inHours}h ${d.inMinutes % 60}m';
    }
    return '${d.inMinutes}m ${d.inSeconds % 60}s';
  }

  String _dateSection(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final callDate = DateTime(date.year, date.month, date.day);
    final diff = today.difference(callDate).inDays;

    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (diff < 7) return 'This Week';
    if (diff < 30) return 'This Month';
    return 'Older';
  }

  Color _statusColor(CallStatus status, ColorScheme cs) {
    switch (status) {
      case CallStatus.missed:
        return cs.error;
      case CallStatus.answered:
      case CallStatus.incoming:
      case CallStatus.outgoing:
        return const Color(0xFF22C55E);
    }
  }

  IconData _statusIcon(CallStatus status) {
    switch (status) {
      case CallStatus.missed:
        return Icons.call_missed;
      case CallStatus.incoming:
        return Icons.call_received;
      case CallStatus.outgoing:
        return Icons.call_made;
      case CallStatus.answered:
        return Icons.check_circle_outline;
    }
  }

  String _statusLabel(CallStatus status) {
    switch (status) {
      case CallStatus.missed:
        return 'Missed';
      case CallStatus.incoming:
        return 'Incoming';
      case CallStatus.outgoing:
        return 'Outgoing';
      case CallStatus.answered:
        return 'Answered';
    }
  }

  Widget _buildSectionHeader(String title, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: cs.onSurfaceVariant,
          letterSpacing: -0.3,
        ),
      ),
    );
  }

  Widget _buildCallAvatar(CallModel call, ColorScheme cs) {
    final size = 52.0;
    if (call.contactAvatar != null && call.contactAvatar!.isNotEmpty) {
      if (call.contactAvatar!.startsWith('data:image')) {
        try {
          final base64Data = call.contactAvatar!.split(',').last;
          final bytes = base64.decode(base64Data);
          return ClipOval(
            child: Image.memory(
              bytes,
              width: size,
              height: size,
              fit: BoxFit.cover,
            ),
          );
        } catch (_) {}
      } else {
        return ClipOval(
          child: Image.network(
            call.contactAvatar!,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => _buildInitialAvatar(call, cs),
          ),
        );
      }
    }
    return _buildInitialAvatar(call, cs);
  }

  Widget _buildInitialAvatar(CallModel call, ColorScheme cs) {
    final initials = call.contactName.isNotEmpty
        ? call.contactName[0].toUpperCase()
        : '?';
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [cs.primary, cs.primary.withValues(alpha: 0.7)],
        ),
      ),
      child: Center(
        child: Text(
          initials,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Calls')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _calls.isEmpty
          ? _buildEmptyState(cs)
          : RefreshIndicator(
              onRefresh: _loadCalls,
              child: _buildGroupedList(cs),
            ),
    );
  }

  Widget _buildGroupedList(ColorScheme cs) {
    final grouped = <String, List<CallModel>>{};
    for (final call in _calls) {
      final section = _dateSection(call.timestamp);
      grouped.putIfAbsent(section, () => []).add(call);
    }

    final sectionOrder = [
      'Today',
      'Yesterday',
      'This Week',
      'This Month',
      'Older',
    ];

    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        for (final section in sectionOrder)
          if (grouped.containsKey(section)) ...[
            _buildSectionHeader(section, cs),
            for (final call in grouped[section]!) _buildCallCard(call, cs),
          ],
      ],
    );
  }

  Widget _buildCallCard(CallModel call, ColorScheme cs) {
    final isMissed = call.status == CallStatus.missed;
    final statusCol = _statusColor(call.status, cs);
    final isVideo = call.type == CallType.video;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Material(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => CallScreen(
                contactId: call.contactId,
                contactName: call.contactName,
                contactAvatar: call.contactAvatar,
                callType: call.type,
              ),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                _buildCallAvatar(call, cs),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              call.contactName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: isMissed ? cs.error : cs.onSurface,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: isVideo
                                  ? cs.primary.withValues(alpha: 0.12)
                                  : cs.primary.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isVideo ? Icons.videocam : Icons.phone,
                                  size: 12,
                                  color: cs.primary,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  isVideo ? 'Video' : 'Voice',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: cs.primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            _statusIcon(call.status),
                            size: 14,
                            color: statusCol,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _statusLabel(call.status),
                            style: TextStyle(
                              fontSize: 12,
                              color: statusCol,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          if (call.duration != null) ...[
                            const SizedBox(width: 6),
                            Container(
                              width: 3,
                              height: 3,
                              decoration: BoxDecoration(
                                color: cs.onSurfaceVariant,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Icon(
                              Icons.timer_outlined,
                              size: 12,
                              color: cs.onSurfaceVariant,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              _formatDuration(call.duration!),
                              style: TextStyle(
                                fontSize: 12,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _formatTimestamp(call.timestamp),
                  style: TextStyle(
                    fontSize: 11,
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(ColorScheme cs) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: cs.primary.withValues(alpha: 0.08),
            ),
            child: Icon(
              Icons.phone_outlined,
              size: 44,
              color: cs.primary.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'No calls yet',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Start a call from your contacts',
            style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
