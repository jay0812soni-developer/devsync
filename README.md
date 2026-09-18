# DevSync (Frontend)

DevSync is a developer-tailored, WhatsApp-like communication and file-sharing tool designed around an **account-per-device model**. Each device generates its own sovereign cryptographic identity (Ed25519 + X25519), enabling direct high-speed P2P LAN transfers with seamless fallback to a zero-retention Vercel relay.

## Features
- **Account-per-Device**: Zero phone number/email login; device keys stored in secure storage.
- **Developer UX**: Syntax-highlighted code snippets, one-tap copy, dark mode default.
- **Local Storage Organization**: Automatically categorizes received files into `DevSync/Code`, `Documents`, `Images`, `Media`, and `Archives`.
- **Hybrid Networking**: Direct LAN transfer via embedded shelf HTTP server + UDP discovery, with Vercel SSE relay fallback.
- **End-to-End Encryption**: AES-256-GCM message encryption and Ed25519 payload signatures.

## Running Locally

```bash
# Get dependencies
flutter pub get

# Run on Desktop (Windows, macOS, Linux)
flutter run -d windows

# Run on Web
flutter run -d chrome
```

## Vercel Deployment

This repository is pre-configured for Vercel deployment via `vercel.json` and `scripts/vercel-build.sh`.

### Option A: Connect Repository to Vercel (Automatic)
1. Import `jay0812soni-developer/devsync` into [Vercel](https://vercel.com).
2. Framework Preset: **Other**.
3. Build Command: `bash scripts/vercel-build.sh` (already in `vercel.json`).
4. Output Directory: `build/web` (already in `vercel.json`).
5. Deploy!

### Option B: Deploy via GitHub Actions
Add your `VERCEL_TOKEN`, `VERCEL_ORG_ID`, and `VERCEL_PROJECT_ID` as repository secrets. Any push to `main` will automatically build Flutter Web and deploy to Vercel.
