import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/nft.dart';
import '../state/app_state.dart';
import 'nft_detail_screen.dart';

class NftScreen extends StatefulWidget {
  const NftScreen({super.key});

  @override
  State<NftScreen> createState() => _NftScreenState();
}

class _NftScreenState extends State<NftScreen> {
  List<Nft>? _nfts;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final wallet = context.read<AppState>().wallet;
    if (wallet == null) return;
    final nfts = await context.read<AppState>().solana.getNfts(wallet.address);
    if (mounted) {
      setState(() {
        _nfts = nfts;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('NFT collection')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _nfts!.isEmpty
            ? ListView(
                children: [
                  const SizedBox(height: 120),
                  Icon(
                    Icons.image_not_supported_outlined,
                    size: 56,
                    color: cs.onSurfaceVariant,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No NFTs yet',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                ],
              )
            : LayoutBuilder(
                builder: (context, constraints) {
                  // Responsive columns: 2 on phones, more on desktop.
                  final width = constraints.maxWidth;
                  final columns = width >= 1400
                      ? 5
                      : width >= 1100
                      ? 4
                      : width >= 700
                      ? 3
                      : 2;

                  // On very wide screens cap the grid width so cards stay
                  // a reasonable size, then center the grid.
                  final maxWidth = width >= 1400 ? 1200.0 : width;

                  return Align(
                    alignment: Alignment.topCenter,
                    child: SizedBox(
                      width: maxWidth,
                      child: GridView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          mainAxisSpacing: 16,
                          crossAxisSpacing: 16,
                          childAspectRatio: 0.78,
                        ),
                        padding: const EdgeInsets.all(16),
                        itemCount: _nfts!.length,
                        itemBuilder: (context, index) =>
                            _NftCard(nft: _nfts![index]),
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class _NftCard extends StatelessWidget {
  const _NftCard({required this.nft});

  final Nft nft;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => NftDetailScreen(nft: nft)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: NftImage(nft: nft)),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    nft.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (nft.symbol.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      nft.symbol,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Loads an NFT image with a placeholder while loading and on error.
class NftImage extends StatelessWidget {
  const NftImage({super.key, required this.nft, this.fit = BoxFit.cover});

  final Nft nft;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final image = nft.imageUrl;
    if (image.isEmpty) return const _Placeholder();
    return Image.network(
      image,
      fit: fit,
      width: double.infinity,
      height: double.infinity,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return const _Placeholder(showSpinner: true);
      },
      errorBuilder: (_, _, _) => const _Placeholder(),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({this.showSpinner = false});

  final bool showSpinner;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: cs.surfaceContainerHighest,
      child: Center(
        child: showSpinner
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(Icons.image, color: cs.onSurfaceVariant, size: 32),
      ),
    );
  }
}
