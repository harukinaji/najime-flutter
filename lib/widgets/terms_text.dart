import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class TermsText extends StatelessWidget {
  final String prefix;
  final String termsLabel;
  final String termsUrl;
  final String andText;
  final String privacyLabel;
  final String privacyUrl;

  const TermsText({
    super.key,
    required this.prefix,
    required this.termsLabel,
    required this.termsUrl,
    required this.andText,
    required this.privacyLabel,
    required this.privacyUrl,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return RichText(
      textAlign: TextAlign.center,
      text: TextSpan(
        style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
        children: [
          TextSpan(text: prefix),
          TextSpan(
            text: termsLabel,
            style: TextStyle(
              color: cs.primary,
              decoration: TextDecoration.underline,
            ),
            recognizer:
                _TapRecognizer()..onTap = () => _launchUrl(termsUrl),
          ),
          TextSpan(text: andText),
          TextSpan(
            text: privacyLabel,
            style: TextStyle(
              color: cs.primary,
              decoration: TextDecoration.underline,
            ),
            recognizer:
                _TapRecognizer()..onTap = () => _launchUrl(privacyUrl),
          ),
        ],
      ),
    );
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

class _TapRecognizer extends TapGestureRecognizer {
  // Helper to keep the callback accessible.
}
