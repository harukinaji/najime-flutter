import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../data/api_service.dart';

class BotManagerScreen extends StatefulWidget {
  const BotManagerScreen({super.key});

  @override
  State<BotManagerScreen> createState() => _BotManagerScreenState();
}

class _BotManagerScreenState extends State<BotManagerScreen> {
  List<Map<String, dynamic>> _bots = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadBots();
  }

  Future<void> _loadBots() async {
    setState(() => _loading = true);
    final bots = await ApiService.getMyBots();
    if (!mounted) return;
    setState(() {
      _bots = bots;
      _loading = false;
    });
  }

  void _showCreateBotSheet() {
    final usernameCtrl = TextEditingController();
    final displayNameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final startBtnCtrl = TextEditingController(text: 'Start');
    final startCmdCtrl = TextEditingController(text: '/start');
    final miniAppUrlCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool creating = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: cs.onSurfaceVariant.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Create Bot',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Your bot will be searchable by other users',
                      style: TextStyle(
                        fontSize: 13,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: usernameCtrl,
                      decoration: InputDecoration(
                        labelText: 'Bot username',
                        prefixText: '@',
                        hintText: 'my_bot',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      validator: (v) {
                        final val = (v ?? '').trim();
                        if (val.isEmpty) return 'Username is required';
                        if (val.length < 3) return 'Min 3 characters';
                        if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(val)) {
                          return 'Only letters, numbers, underscores';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: displayNameCtrl,
                      decoration: InputDecoration(
                        labelText: 'Display name',
                        hintText: 'My Awesome Bot',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      validator: (v) {
                        if ((v ?? '').trim().isEmpty) return 'Name is required';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: descCtrl,
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: 'Description (optional)',
                        hintText: 'What does this bot do?',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Start Button',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: startBtnCtrl,
                      decoration: InputDecoration(
                        labelText: 'Button text',
                        hintText: 'Start',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: startCmdCtrl,
                      decoration: InputDecoration(
                        labelText: 'Command',
                        hintText: '/start',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Mini App (optional)',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: miniAppUrlCtrl,
                      decoration: InputDecoration(
                        labelText: 'Mini App URL',
                        hintText: 'https://example.com/app',
                        prefixIcon: const Icon(Icons.open_in_browser, size: 20),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      validator: (v) {
                        if ((v ?? '').trim().isNotEmpty) {
                          final url = v!.trim();
                          if (!url.startsWith('http://') &&
                              !url.startsWith('https://')) {
                            return 'URL must start with http:// or https://';
                          }
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: FilledButton(
                        onPressed: creating
                            ? null
                            : () async {
                                if (!formKey.currentState!.validate()) return;
                                setSheetState(() => creating = true);
                                final bot = await ApiService.createBot(
                                  username: usernameCtrl.text.trim(),
                                  displayName: displayNameCtrl.text.trim(),
                                  description: descCtrl.text.trim(),
                                  startButtonText:
                                      startBtnCtrl.text.trim().isNotEmpty
                                      ? startBtnCtrl.text.trim()
                                      : 'Start',
                                  startCommand:
                                      startCmdCtrl.text.trim().isNotEmpty
                                      ? startCmdCtrl.text.trim()
                                      : '/start',
                                  miniAppUrl: miniAppUrlCtrl.text.trim(),
                                );
                                setSheetState(() => creating = false);
                                if (!mounted) return;
                                if (bot != null) {
                                  Navigator.pop(ctx);
                                  _loadBots();
                                  _showBotTokenDialog(bot);
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Failed to create bot. Username may be taken.',
                                      ),
                                    ),
                                  );
                                }
                              },
                        child: creating
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Create Bot'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showBotTokenDialog(Map<String, dynamic> bot) {
    final token = bot['token'] as String? ?? '';
    final cs = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Bot Created'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Save this token — it won\'t be shown again in full.',
              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                token,
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: 'monospace',
                  color: cs.onSurface,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  void _showBotDetails(Map<String, dynamic> bot) {
    final cs = Theme.of(context).colorScheme;
    final token = bot['token'] as String? ?? '';
    final shortToken = token.length > 20
        ? '${token.substring(0, 12)}...${token.substring(token.length - 6)}'
        : token;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final isActive = bot['is_active'] == true;
            return Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: cs.onSurfaceVariant.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  CircleAvatar(
                    radius: 36,
                    backgroundColor: cs.primaryContainer,
                    backgroundImage: NetworkImage(bot['avatar_url'] ?? ''),
                    onBackgroundImageError: (_, __) {},
                    child:
                        bot['avatar_url'] == null ||
                            (bot['avatar_url'] as String).isEmpty
                        ? Icon(
                            Icons.smart_toy,
                            size: 36,
                            color: cs.onPrimaryContainer,
                          )
                        : null,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    bot['display_name'] ?? '',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                    ),
                  ),
                  Text(
                    '@${bot['username'] ?? ''}',
                    style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant),
                  ),
                  if (bot['description'] != null &&
                      (bot['description'] as String).isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      bot['description'],
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  // Token display
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            shortToken,
                            style: TextStyle(
                              fontSize: 12,
                              fontFamily: 'monospace',
                              color: cs.onSurface,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.copy, size: 18, color: cs.primary),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: token));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Token copied')),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Active toggle
                  SwitchListTile(
                    title: const Text('Active'),
                    subtitle: Text(
                      isActive ? 'Bot is searchable' : 'Bot is hidden',
                    ),
                    value: isActive,
                    onChanged: (val) async {
                      final ok = await ApiService.updateBot(
                        bot['id'],
                        isActive: val,
                      );
                      if (ok && mounted) {
                        setState(() {
                          bot['is_active'] = val;
                        });
                        setSheetState(() {});
                        _loadBots();
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  // Start button settings
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Start Button',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: _editableField(
                                cs,
                                'Button text',
                                bot['start_button_text'] ?? 'Start',
                                (val) async {
                                  final ok = await ApiService.updateBot(
                                    bot['id'],
                                    startButtonText: val,
                                  );
                                  if (ok) {
                                    setState(
                                      () => bot['start_button_text'] = val,
                                    );
                                    setSheetState(() {});
                                    _loadBots();
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _editableField(
                                cs,
                                'Command',
                                bot['start_command'] ?? '/start',
                                (val) async {
                                  final ok = await ApiService.updateBot(
                                    bot['id'],
                                    startCommand: val,
                                  );
                                  if (ok) {
                                    setState(() => bot['start_command'] = val);
                                    setSheetState(() {});
                                    _loadBots();
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Mini App URL
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.open_in_browser,
                              size: 16,
                              color: cs.primary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Mini App',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        _editableField(
                          cs,
                          'Mini App URL',
                          (bot['mini_app_url'] as String?)?.isNotEmpty == true
                              ? bot['mini_app_url'] as String
                              : 'Not set',
                          (val) async {
                            final ok = await ApiService.updateBot(
                              bot['id'],
                              miniAppUrl: val,
                            );
                            if (ok) {
                              setState(() => bot['mini_app_url'] = val);
                              setSheetState(() {});
                              _loadBots();
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Regenerate token
                  ListTile(
                    leading: Icon(Icons.key, color: cs.primary),
                    title: const Text('Regenerate Token'),
                    subtitle: const Text(
                      'Old token will stop working immediately',
                    ),
                    onTap: () async {
                      final newToken = await ApiService.regenerateBotToken(
                        bot['id'],
                      );
                      if (newToken != null && mounted) {
                        setState(() {
                          bot['token'] = newToken;
                        });
                        setSheetState(() {});
                        Navigator.pop(ctx);
                        _showBotTokenDialog(bot);
                      }
                    },
                  ),
                  // Delete bot
                  ListTile(
                    leading: Icon(Icons.delete_outline, color: cs.error),
                    title: Text(
                      'Delete Bot',
                      style: TextStyle(color: cs.error),
                    ),
                    onTap: () async {
                      final confirm = await showDialog<bool>(
                        context: ctx,
                        builder: (dctx) => AlertDialog(
                          title: const Text('Delete Bot?'),
                          content: Text(
                            'This will permanently delete @${bot['username']}. This cannot be undone.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(dctx, false),
                              child: const Text('Cancel'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(dctx, true),
                              child: Text(
                                'Delete',
                                style: TextStyle(color: cs.error),
                              ),
                            ),
                          ],
                        ),
                      );
                      if (confirm == true) {
                        final ok = await ApiService.deleteBot(bot['id']);
                        if (ok && mounted) {
                          Navigator.pop(ctx);
                          _loadBots();
                        }
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Close'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _editableField(
    ColorScheme cs,
    String label,
    String value,
    Function(String) onSave,
  ) {
    return InkWell(
      onTap: () {
        final ctrl = TextEditingController(text: value);
        showDialog(
          context: context,
          builder: (dctx) => AlertDialog(
            title: Text('Edit $label'),
            content: TextField(
              controller: ctrl,
              decoration: InputDecoration(
                hintText: label,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dctx),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(dctx);
                  onSave(ctrl.text.trim());
                },
                child: const Text('Save'),
              ),
            ],
          ),
        );
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: cs.outlineVariant),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: cs.onSurface,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('My Bots'), backgroundColor: cs.surface),
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreateBotSheet,
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _bots.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.smart_toy_outlined,
                    size: 64,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No bots yet',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tap + to create your first bot',
                    style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _bots.length,
              itemBuilder: (context, index) {
                final bot = _bots[index];
                final isActive = bot['is_active'] == true;
                return ListTile(
                  onTap: () => _showBotDetails(bot),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  leading: CircleAvatar(
                    radius: 24,
                    backgroundColor: cs.primaryContainer,
                    backgroundImage: NetworkImage(bot['avatar_url'] ?? ''),
                    onBackgroundImageError: (_, __) {},
                    child:
                        bot['avatar_url'] == null ||
                            (bot['avatar_url'] as String).isEmpty
                        ? Icon(
                            Icons.smart_toy,
                            size: 24,
                            color: cs.onPrimaryContainer,
                          )
                        : null,
                  ),
                  title: Row(
                    children: [
                      Flexible(
                        child: Text(
                          bot['display_name'] ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: cs.onSurface,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: cs.primaryContainer,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'bot',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: cs.onPrimaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                  subtitle: Text(
                    '@${bot['username'] ?? ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                  ),
                  trailing: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: isActive ? const Color(0xFF22C55E) : cs.error,
                      shape: BoxShape.circle,
                    ),
                  ),
                );
              },
            ),
    );
  }
}
