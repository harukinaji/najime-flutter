import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';

import 'services/nft_media_handler.dart';

/// The global media handler backing the NFT media session. Initialized lazily
/// when the embedded wallet feature is opened so that the messenger's own
/// startup is not affected.
NftMediaHandler? nftMediaHandler;

Future<void> ensureWalletMedia() async {
  if (nftMediaHandler != null) return;
  try {
    nftMediaHandler = await AudioService.init(
      builder: NftMediaHandler.new,
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'org.najime.wallet.nft_media',
        androidNotificationChannelName: 'NFT медиа',
        androidNotificationOngoing: true,
        androidStopForegroundOnPause: true,
      ),
    );
  } catch (e) {
    debugPrint('[Wallet] AudioService init failed: $e');
  }
}
