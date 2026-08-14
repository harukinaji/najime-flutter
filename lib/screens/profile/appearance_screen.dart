import 'package:flutter/material.dart';

import '../../app.dart';

class AppearanceScreen extends StatefulWidget {
  const AppearanceScreen({super.key});

  @override
  State<AppearanceScreen> createState() => _AppearanceScreenState();
}

class _AppearanceScreenState extends State<AppearanceScreen> {
  String _theme = 'system';
  String _fontSize = 'default';

  void _onThemeChanged(String? value) {
    if (value == null) return;
    setState(() => _theme = value);
    switch (value) {
      case 'light':
        NajiMeApp.setThemeMode(context, ThemeMode.light);
      case 'dark':
        NajiMeApp.setThemeMode(context, ThemeMode.dark);
      case 'system':
        NajiMeApp.setThemeMode(context, ThemeMode.system);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Appearance')),
      body: ListView(
        children: [
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Theme',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _ThemeOption(
                      icon: Icons.light_mode_outlined,
                      label: 'Light',
                      value: 'light',
                      groupValue: _theme,
                      onChanged: _onThemeChanged,
                    ),
                    _ThemeOption(
                      icon: Icons.dark_mode_outlined,
                      label: 'Dark',
                      value: 'dark',
                      groupValue: _theme,
                      onChanged: _onThemeChanged,
                    ),
                    _ThemeOption(
                      icon: Icons.phone_android,
                      label: 'System',
                      value: 'system',
                      groupValue: _theme,
                      onChanged: _onThemeChanged,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Brand Color',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _colorDot(cs.primary, cs),
                        _colorDot(cs.secondary, cs),
                        _colorDot(cs.tertiary, cs),
                        _colorDot(cs.primaryContainer, cs),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      height: 48,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [cs.primary, cs.primary.withValues(alpha: 0.7)],
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Center(
                        child: Text(
                          'NajiMe',
                          style: TextStyle(
                            color: cs.onPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Font Size',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _FontSizeOption(
                      label: 'Small',
                      fontSize: 13,
                      value: 'small',
                      groupValue: _fontSize,
                      onChanged: (v) {
                        if (v != null) setState(() => _fontSize = v);
                      },
                    ),
                    _FontSizeOption(
                      label: 'Default',
                      fontSize: 15,
                      value: 'default',
                      groupValue: _fontSize,
                      onChanged: (v) {
                        if (v != null) setState(() => _fontSize = v);
                      },
                    ),
                    _FontSizeOption(
                      label: 'Large',
                      fontSize: 17,
                      value: 'large',
                      groupValue: _fontSize,
                      onChanged: (v) {
                        if (v != null) setState(() => _fontSize = v);
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _colorDot(Color color, ColorScheme cs) {
    return Container(
      width: 36,
      height: 36,
      margin: const EdgeInsets.only(right: 8),
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: cs.outlineVariant, width: 2),
      ),
    );
  }
}

class _ThemeOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String groupValue;
  final ValueChanged<String?> onChanged;

  const _ThemeOption({
    required this.icon,
    required this.label,
    required this.value,
    required this.groupValue,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return RadioListTile<String>(
      value: value,
      groupValue: groupValue,
      onChanged: onChanged,
      activeColor: cs.primary,
      contentPadding: EdgeInsets.zero,
      title: Row(
        children: [
          Icon(icon, size: 20, color: cs.onSurfaceVariant),
          const SizedBox(width: 12),
          Text(label, style: TextStyle(fontSize: 15, color: cs.onSurface)),
        ],
      ),
    );
  }
}

class _FontSizeOption extends StatelessWidget {
  final String label;
  final double fontSize;
  final String value;
  final String groupValue;
  final ValueChanged<String?> onChanged;

  const _FontSizeOption({
    required this.label,
    required this.fontSize,
    required this.value,
    required this.groupValue,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return RadioListTile<String>(
      value: value,
      groupValue: groupValue,
      onChanged: onChanged,
      activeColor: cs.primary,
      contentPadding: EdgeInsets.zero,
      title: Text(
        label,
        style: TextStyle(fontSize: fontSize, color: cs.onSurface),
      ),
    );
  }
}
