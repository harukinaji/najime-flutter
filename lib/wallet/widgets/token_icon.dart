import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';

/// Displays a token's icon loaded from its on-chain metadata image.
///
/// Falls back to a colored circle with the token's first letter while loading
/// or when no image is available.
class TokenIcon extends StatefulWidget {
  const TokenIcon({
    super.key,
    required this.mint,
    required this.symbol,
    this.size = 32,
  });

  final String mint;
  final String symbol;
  final double size;

  @override
  State<TokenIcon> createState() => _TokenIconState();
}

class _TokenIconState extends State<TokenIcon> {
  Future<String?>? _imageFuture;

  @override
  void initState() {
    super.initState();
    _imageFuture = context.read<AppState>().solana.getTokenImage(widget.mint);
  }

  @override
  void didUpdateWidget(TokenIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mint != widget.mint) {
      _imageFuture = context.read<AppState>().solana.getTokenImage(widget.mint);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _imageFuture,
      builder: (context, snapshot) {
        final url = snapshot.data;
        if (url == null || url.isEmpty) {
          return _letterAvatar(context);
        }
        return ClipOval(
          child: Image.network(
            url,
            width: widget.size,
            height: widget.size,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => _letterAvatar(context),
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              return SizedBox(
                width: widget.size,
                height: widget.size,
                child: Center(
                  child: SizedBox(
                    width: widget.size * 0.5,
                    height: widget.size * 0.5,
                    child: const CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _letterAvatar(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final letter = widget.symbol.isEmpty ? '?' : widget.symbol.substring(0, 1);
    return Container(
      width: widget.size,
      height: widget.size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: primary.withValues(alpha: 0.2),
        shape: BoxShape.circle,
      ),
      child: Text(
        letter,
        style: TextStyle(
          color: primary,
          fontWeight: FontWeight.bold,
          fontSize: widget.size * 0.5,
        ),
      ),
    );
  }
}