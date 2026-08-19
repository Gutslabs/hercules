# Hercules

Hercules is a SwiftUI + SwiftData fitness tracking app for macOS and iOS. It tracks body measurements, food intake, macros, workouts, calendar-based calorie balance, recipes, and AI-assisted coaching.

## Features

- Body measurement and trend tracking
- Daily food logging with calories, protein, carbs, and fat
- Calendar view for daily intake and goal pacing
- Workout templates, workout logs, and program archive support
- Recipe library with macro metadata
- AI coaching context built from local app data
- Native CloudKit sync between macOS and iOS
- Apple Health step and walking-distance import on iPhone

## Requirements

- macOS with Xcode
- SwiftUI/SwiftData-capable Apple SDK
- Optional: Codex CLI login or an OpenRouter API key for AI features

## Build

Open `Hercules.xcodeproj` in Xcode and run one of the schemes:

- `Hercules` for macOS
- `HerculesMobile` for iOS

CloudKit requires a real signed build. The project is configured for the Hercules Apple Developer team; if you fork it, select your own team and iCloud container in Signing & Capabilities.

Signed macOS development build and install:

```sh
./scripts/mac-build-install.sh Debug
```

Debug builds use the CloudKit Development environment. Release/CI builds use Production and must carry a distribution certificate plus a provisioning profile; the DMG workflow refuses to publish an unsigned app.

Command-line iOS Simulator build:

```sh
xcodebuild -project Hercules.xcodeproj -scheme HerculesMobile -configuration Debug -destination 'generic/platform=iOS Simulator' build
```

## AI Keys And Local Data

API keys and tokens are not stored in the repository. Hercules reads AI credentials from local user storage such as Keychain, UserDefaults migration paths, or local Codex auth files. App databases, backups, DMGs, signing files, and local agent settings are ignored by `.gitignore`.

## iPhone AI Over Tailscale

The iOS app never needs a Codex login, OpenRouter key, or gateway key. Its AI chat and food estimator requests go to the Mac app over Tailscale HTTPS; the Mac uses its currently selected Hercules AI provider and enriches chat with the local Hercules data snapshot.

The Mac server binds only to `127.0.0.1:8765`. Tailscale Serve exposes it at `/hercules-ai`, and every remote request is checked against the Tailscale user allowlist in `~/Library/Application Support/Hercules/remote-ai.plist`.

After installing the signed Mac app, configure the route once:

```sh
chmod +x scripts/tailscale-cli.sh scripts/configure-remote-ai.sh
./scripts/mac-build-install.sh Debug
./scripts/configure-remote-ai.sh
```

Both devices must be logged into the permitted tailnet. Hercules launches at login and is silently checked once a minute so the endpoint recovers after an app exit or crash. The configuration script adds only `/hercules-ai`; it deliberately preserves other Tailscale Serve handlers such as the MintOps/Robinhood root route.

## Notes

This app is a personal fitness tool and not medical advice. Nutrition and training recommendations should be treated as informational and adjusted with professional guidance when needed.
