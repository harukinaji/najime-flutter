# NajiMe

Open-source, end-to-end encrypted messenger with bots, stickers, stories, WebRTC voice/video calls, and an embedded Solana wallet. Built with Flutter for Android, iOS, Windows, macOS and Linux.

> **Note:** this repository contains only the **Flutter client**. The backend (Go server, SFU, bot SDKs) lives in the `backend/` folder of the project workspace.

---

## Features

### Messaging

- **1:1 and group chats** with real-time WebSocket delivery
- **Message types:** text, image, file, voice, sticker, invoice, check
- **Reactions** — add/remove emoji reactions, real-time sync across participants
- **Reply** — inline reply with quoted context
- **Forward** — cross-chat forwarding with original sender attribution
- **Pin/Unpin** — pin important messages to a chat
- **Edit / Delete** — modify or remove sent messages
- **Scheduled messages** — future-dated delivery with cancel support
- **Message search** — cross-chat full-text search
- **Delivery receipts** — sending → sent → delivered → read status tracking
- **Chat folders** — custom organization of chats into named groups
- **Chat muting** — per-chat notification suppression
- **Desktop split view** — side-by-side chat list and conversation at ≥900px width

### Voice & Video Calls

- **1:1 calls** — voice and video via WebRTC peer connections
- **Group conferences** — multi-participant calls with server-side SFU (Selective Forwarding Unit)
- **Mid-call invite** — add participants to an ongoing call
- **Call history** — full log of incoming/outgoing/missed calls with duration
- **STUN/TURN** — self-hosted STUN server, TURN with time-limited credentials
- **Signaling** — WebSocket-based offer/answer/ICE candidate exchange

### End-to-End Encryption

| Layer | Technology |
|---|---|
| Messaging | X25519 ECDH key exchange + XChaCha20-Poly1305 AEAD |
| Media frames | XChaCha20-Poly1305 with per-peer key rotation (every 500 frames) |
| Wallet deep links | NaCl crypto_box (X25519 + XSalsa20-Poly1305) |
| Passwords | PBKDF2-SHA256 (600,000 iterations, random 16-byte salt) |
| Cache | AES-256-SIC (CTR mode) encrypted chat list and images |
| Transport | TLS 1.2+, certificate pinning (SHA-256 fingerprint), WSS |
| Request signing | HMAC-SHA256 per-device attestation (Android Keystore / iOS Keychain) |
| App lock | HMAC-SHA256 salted PIN hash + biometric (fingerprint/face) |
| Anti-replay | Unique nonce (16 bytes) + Unix timestamp (±60s window) per request |

- **Protected chats** — per-chat X25519 session keys with proper forward secrecy
- **Key rotation** — automatic key refresh on SFU media streams
- **Certificate pinning** — compile-time SHA-256 fingerprint enforcement

### Authentication

- **Username/password** login
- **Google Sign-In** — OAuth2 PKCE flow with local HTTP callback
- **Apple Sign-In** — identity token verification
- **Phone verification** — Firebase Auth SMS code
- **Two-factor auth** — email code verification, device approval polling
- **Auto-reconnect** — exponential backoff WebSocket reconnection (1s → 30s)

### Bots & Mini Apps

- **Bot creation** — username, display name, description, avatar, start button
- **Inline keyboards** — callback data, URL links, send_message actions
- **Mini Apps** — in-app WebView hosting for bot web apps
- **JavaScript bridge** (`NajiBridge`) exposed to mini apps:
  - `naji.getUser()` / `naji.getContact()` / `naji.getChats()`
  - `naji.sendMessage()` — send messages from mini app
  - `naji.getWallet()` / `naji.signTransaction()` — wallet access
  - `naji.getStickers()` — sticker pack access
  - `naji.createRoom()` / `naji.joinRoom()` — multiplayer room management
  - `naji.sendGameEvent()` — real-time game events via data channels
  - `naji.vibrate()` / `naji.scanQR()` / `naji.playSound()` — device APIs
- **Security** — HTTPS-only, URL allowlist, no localhost/private IP access

### Stickers

- **Sticker packs** — create, install, uninstall custom packs
- **Types:** static images, Lottie animations (`.tgs`), video stickers (`.webm`/`.mp4`)
- **Sticker picker** — inline widget in chat input
- **Caching** — memory + file cache with batch preloading for smooth picker
- **Storybook** — component development and visual testing via `storybook_flutter`

### Stories

- **Image and video stories** — capture from camera or gallery
- **Captions** — optional text overlay
- **24-hour expiry** — automatic expiration
- **Viewer tracking** — list of viewers with read receipts
- **Story viewer** — fullscreen playback with user navigation

### Embedded Solana Wallet

#### Core
- **BIP39 mnemonic** — 12-word generation and import
- **Ed25519 HD keys** — hierarchical deterministic key derivation
- **Private key import** — base58 32-byte or 64-byte keypair
- **Secure storage** — seed phrase and private key in `flutter_secure_storage`
- **Balance queries** — SOL lamports + SPL token balances

#### Token Support
- **SOL** — native token transfers
- **SPL Tokens** — standard Token Program transfers
- **Token-2022** — Token-2022 Program (PYUSD, etc.)
- **Token metadata** — Metaplex on-chain metadata + Token-2022 extension parsing
- **NFT detection** — 0-decimal supply=1 tokens with Metaplex metadata
- **Custom tokens** — user-added token tracking

#### Transactions
- **SOL and SPL transfers** — with automatic ATA creation
- **Transaction history** — signature list with parsed details
- **Airdrop** — devnet SOL faucet requests

#### Staking
- **SOL staking** — native stake program with delegated validators
- **Validator selection** — active vote accounts listing
- **Minimum delegation** — 1 SOL enforcement

#### DEX Swap (Raydium)
- **Raydium CPMM** — constant product market maker pools
- **Swap quoting** — exact input with slippage protection, price impact calculation
- **Fee breakdown** — trade, protocol, fund, and creator fees
- **wSOL wrapping** — automatic native SOL wrapping

#### Solana Pay
- **QR code payments** — `solana:` URI parsing and execution
- **SPL token payments** — custom token transfers
- **Reference tracking** — on-chain reference key inclusion

#### Check/Escrow System
- **On-chain checks** — Solana program for escrowed SOL transfers
- **Create/Redeem** — fund PDA, claim escrowed funds
- **Anchor discriminators** — instruction identification via 8-byte discriminators

#### External Wallet Integration
- **Phantom / Solflare** — deep-link `ul/v1/connect` protocol
- **NaCl crypto_box** — X25519 + XSalsa20-Poly1305 E2E encryption for wallet communication
- **Session persistence** — secure storage of keys, session token, address
- **Sign message / Sign & send** — `solana_signMessage`, `solana_signAndSendTransaction`

### Notifications

- **Firebase Cloud Messaging** — push notification delivery
- **FCM token registration** — per-device token with automatic refresh
- **Background handler** — delivery receipt on background message
- **Native quick-reply** — Android inline reply via MethodChannel
- **Per-type control** — message, group message, call notification toggles

### Contacts

- **Device contacts** — read via `flutter_contacts` with permission handling
- **NajiMe detection** — phone number matching against registered users
- **Contact caching** — in-memory cache with local search
- **Phone normalization** — international format standardization

### Premium Features

- **Pay-to-unlock content** — blur overlay on locked messages
- **Crypto payments** — SOL or custom token payment
- **Animated unlock** — blur dissolve animation on successful payment
- **Invoice messages** — structured payment requests with status tracking
- **Check messages** — escrow-based money transfer via Solana program

### Settings & Profile

- **Edit profile** — display name, bio, avatar upload
- **QR profile card** — shareable `najime://profile/{username}` QR code
- **Connected accounts** — link/unlink Google, phone, wallet
- **Privacy settings** — account and password management
- **Notification settings** — granular per-type audio/haptic control
- **Appearance** — light/dark/system theme with brand color (`#18A7B5`)
- **Chat folders** — create, rename, delete, assign chats
- **App lock** — PIN (4-8 digits), biometric, or combined; rate limiting (30s after 5 failures, 5min after 10)
- **Lock on resume** — auto-lock when app is backgrounded

### P2P Multiplayer

- **WebSocket signaling** — room creation, join, matchmaking
- **WebRTC data channels** — ordered reliable `naji` channel for game state
- **Mesh networking** — full mesh topology with per-peer connections
- **Voice mesh** — dynamic audio track management across peers
- **Latency measurement** — ping/pong with RTT tracking
- **Game events** — custom event broadcasting via data channels

---

## Tech Stack

| Layer | Technology |
|---|---|
| Framework | Flutter / Dart |
| Routing | `go_router` with `StatefulShellRoute` for tab navigation |
| State | `Provider` (wallet), `AuthState` singleton, service singletons |
| Networking | `http`, `socket_io_client`, `web_socket` |
| Encryption | `cryptography` (X25519, XChaCha20-Poly1305), `crypto` (HMAC, SHA-256), `pinenacl` (NaCl) |
| WebRTC | `flutter_webrtc` (peer connections, media streams) |
| Firebase | `firebase_core`, `firebase_auth`, `firebase_messaging` |
| Wallet | `solana`, `bip39`, `ed25519_hd_key`, `decimal` |
| Storage | `flutter_secure_storage`, `shared_preferences`, `flutter_cache_manager` |
| Media | `just_audio`, `audio_service`, `record`, `video_player`, `lottie` |
| UI | `flutter_svg`, `pretty_qr_code`, `qr_flutter`, `mobile_scanner` |
| Testing | `storybook_flutter` |

---

## Supported Platforms

| Platform | Status | Notes |
|---|---|---|
| Android | Primary | FCM, native attestation, quick-reply, audio service |
| iOS | Primary | Keychain attestation, Apple Sign-In, scene support |
| Windows | Supported | WebView for mini apps |
| macOS | Supported | — |
| Linux | Supported | — |

---

## Getting Started

### Prerequisites

- Flutter SDK (stable channel, `^3.12.2`)
- A backend instance (see `backend/` folder) — or use the public dev server (default)

### Run

```bash
flutter pub get
flutter run
```

### Custom Backend

```bash
flutter run --dart-define=API_BASE_URL=https://api.your-server.com
```

This sets the API, WebSocket and STUN/TURN host. See `lib/config.dart`.

### Build

```bash
# Android
flutter build apk --release

# iOS
flutter build ios --release

# Windows
flutter build windows --release

# macOS
flutter build macos --release

# Linux
flutter build linux --release
```

### Tests

```bash
flutter analyze --no-fatal-warnings --no-fatal-infos
flutter test
```

---

## Configuration

| Dart define | Default | Description |
|---|---|---|
| `API_BASE_URL` | `https://najime.org:5000` | Backend API base URL |

### Environment Variables (`.env`)

| Variable | Description |
|---|---|
| `WALLETCONNECT_PROJECT_ID` | WalletConnect / Reown project ID for Phantom/Solflare integration |

### OAuth

Google OAuth client ID is configured in `lib/data/google_oauth_flow.dart`. To use your own OAuth app, replace it there and configure the corresponding secret on your backend.

---

## Repository Layout

```
frontend/
  lib/
    config.dart              ← API_BASE_URL, WebSocket, STUN/TURN configuration
    main.dart                ← entry point, Firebase + service initialization
    app.dart                 ← MaterialApp, theme, router
    data/                    ← services
      api_service.dart       ← REST API client (2400+ lines)
      auth_state.dart        ← session management, login/logout
      websocket_service.dart ← Socket.IO + raw WebSocket
      webrtc_service.dart    ← WebRTC peer connections, 1:1 calls
      sfu_service.dart       ← SFU group call orchestration
      e2e_encryption.dart    ← X25519 + XChaCha20-Poly1305 E2E
      protected_chat_service.dart ← per-chat encryption sessions
      notification_service.dart   ← FCM push notifications
      cache_service.dart     ← AES-256-SIC encrypted cache
      lock_service.dart      ← PIN/biometric app lock
      sticker_cache.dart     ← sticker memory + file cache
      story_service.dart     ← story CRUD
      contacts_service.dart  ← device contact sync
      secure_http_client.dart ← certificate pinning
      app_attestation.dart   ← per-device HMAC request signing
      password_crypto.dart   ← PBKDF2-SHA256 password hashing
      token_cipher.dart      ← token encryption via native keystore
      voice_recording_service.dart ← AAC-LC voice recording
      p2p_room_service.dart  ← multiplayer room signaling
      chat_read_service.dart ← read receipt tracking
    models/                  ← data models (Chat, Message, User, Story, etc.)
    screens/                 ← UI screens
      auth/                  ← login, register, lock screen, 2FA
      chats/                 ← chat list, detail, create group, forward
      calls/                 ← call screen, call history
      contacts/              ← contact list
      bots/                  ← bot manager, mini app WebView
      stickers/              ← sticker pack management
      stories/               ← story creation, viewer
      profile/               ← profile, settings, privacy, appearance
      premium/               ← premium unlock, pay-to-unlock
      multiplayer/           ← P2P room screen
    wallet/                  ← Solana wallet
      services/              ← solana, raydium, staking, WalletConnect, escrow
      screens/               ← wallet home, send, receive, swap, history, NFTs
      models/                ← token, NFT, transaction models
      state/                 ← wallet state management (Provider)
    widgets/                 ← reusable UI components
    stories/                 ← storybook stories for component development
    theme/                   ← colors, typography, Material theme
    router/                  ← GoRouter setup with shell routes
    utils/                   ← platform detection, desktop layout helpers
  test/                      ← widget and unit tests
  android/                   ← Android platform project
  ios/                       ← iOS platform project
  windows/                   ← Windows platform project
  macos/                     ← macOS platform project
  linux/                     ← Linux platform project
  assets/                    ← images, SVGs
```

---

## Security

NajiMe implements defense-in-depth security across multiple layers:

- **Transport encryption** — TLS 1.2+ with SHA-256 certificate pinning; WSS for WebSockets
- **Request attestation** — every API request is signed with a per-device HMAC-SHA256 key stored in Android Keystore / iOS Keychain, with nonce + timestamp anti-replay
- **End-to-end encryption** — X25519 ECDH key agreement + XChaCha20-Poly1305 AEAD for messages; automatic key rotation on media streams
- **Wallet security** — NaCl crypto_box for deep-link signing; seed phrases in secure storage; Android Keystore encryption for session tokens
- **Password hashing** — PBKDF2-SHA256 with 600,000 iterations and random salt; constant-time comparison to prevent timing attacks
- **Cache encryption** — all cached chat data and images encrypted at rest with AES-256-SIC
- **App lock** — PIN (HMAC-SHA256 hashed) + biometric with rate limiting (30s lockout after 5 failures, 5min after 10)

If you find a security vulnerability, please report it via [GitHub Security Advisories](https://github.com/security/advisories).

---

## Contributing

Contributions are welcome! Please open an issue to discuss significant changes before submitting a pull request. Keep code style consistent with `analysis_options.yaml` and ensure `flutter analyze` passes.

---

## License

[MIT](LICENSE)
