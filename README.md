# NajiMe

Open-source messenger built with Flutter: end-to-end encrypted chats, bots,
stickers, stories and WebRTC voice/video calls.

> **Note:** this repository contains only the **Flutter client**. The server
> components (Go/Python backends, SFU, bot SDKs) live in the `backend` folder
> of the same project workspace and are not part of this repository.

## Features

- **1:1 and group chats** with reactions, replies, forwarding, pinning,
  scheduled messages, editing and deleting
- **End-to-end encrypted chats** (X25519 key exchange + ChaCha20-Poly1305)
- **Auth** via email + password with email verification code, Google Sign-In,
  Apple Sign-In and phone linking
- **Bot platform** — create bots, inline keyboards, mini-apps
- **Stickers** — packs, Lottie (`.tgs`) support, import from Telegram
- **Stories** with view receipts
- **Voice/video calls** — 1:1 and group conferences (WebRTC + SFU + TURN)
- **Push notifications** via Firebase Cloud Messaging
- **Folder organization**, contact sync by phone number, chat lock (biometric)
- **Cross-platform:** Android, iOS, Windows, macOS, Linux, Web

## Tech stack

- [Flutter](https://flutter.dev) / Dart
- `go_router`, `flutter_webrtc`, `firebase_messaging`, `flutter_secure_storage`,
  `crypto` / `cryptography`, `socket_io_client`, `lottie`, `storybook_flutter`

## Getting started

### Prerequisites

- Flutter SDK (stable channel, see `pubspec.yaml` for the Dart SDK constraint)
- A backend instance (see the `backend` folder of this workspace) — or use the
  public development server (default configuration)

### Run

```bash
flutter pub get
flutter run
```

To point the app at your own backend:

```bash
flutter run --dart-define=API_BASE_URL=https://api.your-server.com
```

The same value is used for the WebSocket and media URLs; STUN/TURN hosts are
derived from it. See `lib/config.dart`.

### Build

```bash
# Android
flutter build apk --release

# iOS
flutter build ios --release

# Desktop / Web
flutter build windows --release
flutter build macos --release
flutter build linux --release
flutter build web --release
```

### Tests

```bash
flutter analyze
flutter test
```

## Repository layout

```
frontend/            ← this repository (Flutter app)
  lib/
    config.dart      ← API_BASE_URL configuration
    data/            ← services: api, websocket, webrtc, e2e, notifications …
    screens/         ← UI screens
    widgets/         ← reusable widgets
    router/          ← go_router setup
  test/
```

## Configuration

| Dart define        | Default               | Description                          |
| ------------------ | --------------------- | ------------------------------------ |
| `API_BASE_URL`     | `https://najime.org:5000` | Base URL of the backend API      |

Google OAuth works with the client ID in `lib/data/google_oauth_flow.dart`.
To use your own OAuth app, replace it there and configure the corresponding
secret on your backend.

## Contributing

Contributions are welcome! Please open an issue to discuss significant changes
before submitting a pull request. Keep code style consistent with
`analysis_options.yaml` and make sure `flutter analyze` passes.

## Security

If you find a security vulnerability, please report it privately via
[GitHub Security Advisories](https://github.com/security/advisories) instead of
opening a public issue.

## License

[MIT](LICENSE)
