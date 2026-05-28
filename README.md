# Hercules

Hercules is a SwiftUI + SwiftData fitness tracking app for macOS and iOS. It tracks body measurements, food intake, macros, workouts, calendar-based calorie balance, recipes, and AI-assisted coaching.

## Features

- Body measurement and trend tracking
- Daily food logging with calories, protein, carbs, and fat
- Calendar view for daily intake and goal pacing
- Workout templates, workout logs, and program archive support
- Recipe library with macro metadata
- AI coaching context built from local app data
- Local backup and optional vault/iCloud-style sync helpers

## Requirements

- macOS with Xcode
- SwiftUI/SwiftData-capable Apple SDK
- Optional: Codex CLI login or an OpenRouter API key for AI features

## Build

Open `BodyTrack.xcodeproj` in Xcode and run one of the schemes:

- `BodyTrack` for macOS
- `HerculesMobile` for iOS

The repository intentionally leaves the Apple development team blank. To run a signed macOS build from Xcode, select your own team in Signing & Capabilities. For a source-only command-line check, disable signing as shown below.

Command-line macOS build:

```sh
xcodebuild -project BodyTrack.xcodeproj -scheme BodyTrack -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
```

Command-line iOS Simulator build:

```sh
xcodebuild -project BodyTrack.xcodeproj -scheme HerculesMobile -configuration Debug -destination 'generic/platform=iOS Simulator' build
```

## AI Keys And Local Data

API keys and tokens are not stored in the repository. Hercules reads AI credentials from local user storage such as Keychain, UserDefaults migration paths, or local Codex auth files. App databases, backups, DMGs, signing files, and local agent settings are ignored by `.gitignore`.

## Notes

This app is a personal fitness tool and not medical advice. Nutrition and training recommendations should be treated as informational and adjusted with professional guidance when needed.
