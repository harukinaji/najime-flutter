# Security Policy

If you believe you have found a security vulnerability in NajiMe, please report it
responsibly. We take security seriously and appreciate coordinated disclosure.

## Reporting a Vulnerability

**Please do NOT open a public issue for security problems.**

Report vulnerabilities privately via GitHub Security Advisories:

- <https://github.com/harukinaji/najime-flutter/security/advisories/new>

Alternatively, email the maintainers at **catcomp83@gmail.com** (or the address
listed in the repository metadata). Include:

- A summary of the issue and its impact.
- Steps to reproduce (a small PoC, affected endpoint / screen / API is ideal).
- Affected versions and platforms (Android / iOS / Windows / macOS / Linux).
- Any suggested fix, if you have one.

You should receive an acknowledgment within **48 hours**, and we'll keep you
informed as we triage and fix the issue. We ask you to keep the disclosure
private until a fix is released.

### Our commitment

- We will acknowledge valid reports promptly.
- We will work toward a fix before public disclosure.
- We will credit researchers (if requested) in the release notes / advisories.
- We will not pursue legal action against researchers acting in good faith and
  following this policy.

## Scope

### In scope

- The Flutter client in this repository (`frontend/`): `lib/`, platform code.
- Client-side cryptographic handling, key/session storage, and wallet operations.
- Local data storage (secure storage, cache), lock/PIN, attestation signing.
- Any bundled native plugin code under `plugins/`.

### Out of scope

- The **backend / server** (Go, Python, SFU, bot SDKs) lives in a separate
  workspace folder (`backend/`) and is NOT part of this repository. Issues in
  backend logic should be reported through the repository that hosts it.
- The **web client** (`website/`) — separate project.
- Known, intentional behaviors documented in the README (e.g., Solana **devnet**
  only, alpha status).
- Issues caused by third-party plugin vulnerabilities already tracked upstream.

> ⚠️ **This is early-alpha software. The embedded Solana wallet is Devnet-only.**
> Do **not** store real funds or use production mainnet keys with this app.

## What to include (reporting checklist)

- [ ] Affected component / file path
- [ ] Impact (privilege escalation, data exposure, crash, funds loss, …)
- [ ] Steps to reproduce
- [ ] Suggested fix (optional)
- [ ] Severity estimate (your assessment is fine — we'll re-evaluate)

## Security features in place

For context, the client implements defense-in-depth (see README for details):

- **Transport**: TLS 1.2+ with SHA-256 certificate pinning; WSS for WebSockets.
- **Application key**: every request carries `X-App-Key` (backend-enforced for
  non-browser clients) alongside the account session token.
- **Request attestation**: per-device HMAC-SHA256 signing with nonce + timestamp
  anti-replay; keys in Android Keystore / iOS Keychain.
- **Wallet**: seed phrases/private keys in `flutter_secure_storage`; NaCl
  crypto_box for Phantom/Solflare deep-link signing; transaction confirmation
  dialogs with instruction analysis.
- **Passwords**: PBKDF2-SHA256 (600k iterations, random salt + per-install pepper);
  constant-time comparison.
- **Cache** encrypted at rest (AES).
- **App lock**: PIN (PBKDF2 + pepper) and biometrics with persisted rate limiting.

### CI/CD security gates

- Secret scanning (gitleaks) and SARIF-based code scanning on every PR.
- `flutter analyze` + `dart format` enforced.
- Dependency review on PRs; Dependabot for dependency updates.
- Release publishing requires a manual approval (protected `production`
  environment) plus branch protection (PR + required status checks) on `main`.

## Disclosure policy

We follow a **coordinated disclosure** timeline:

1. Report received and acknowledged (≤ 48h).
2. Maintainers triage and develop a fix.
3. Fix is merged and a release is tagged.
4. Advisory is published (we will credit you unless you prefer otherwise).

We do not currently operate a dedicated bug-bounty payout programme; rewards are
at the maintainers' discretion.