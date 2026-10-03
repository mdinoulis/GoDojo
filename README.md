# Go Study – play and learn Go with KataGo

Flutter app (Windows desktop for development, Android, iOS) with KataGo running
**on the device**. No server, no network calls.

| Folder | What |
|---|---|
| `packages/go_core` | Pure Dart rules engine: board, ko/superko, rulesets, handicap, game record with undo/redo, SGF, scoring (seki, bent four, unfinished-border detection), move classifier |
| `packages/katago_engine` | Engine API (`GoEngine`) + KataGo JSON analysis-engine client, bot levels 20k–9d + full strength (human-SL net) |
| `app` | Flutter UI |
| `engine` | KataGo configs, Android cross-compile script, iOS in-process bridge |

## Setup (Windows PC)
Binaries and networks are not committed; download them as in Phase 0:
- `engine/windows/` – KataGo 1.18.1 OpenCL build (`engine/windows-cpu/` – Eigen AVX2 build)
- `engine/models/` – `kata1-b18c384nbt-s9996604416-d4316597426.bin.gz`,
  `b18c384nbt-humanv0.bin.gz`, `kata1-b15c192-s1672170752-d466197061.txt.gz`

Tools used: Flutter 3.47 (`D:\tools\flutter`), JDK 21 (`D:\tools\jdk-21…`),
Android SDK 36 + NDK 27.0.12077973.

## Run
- Desktop: `cd app && flutter run -d windows` (finds `engine/` automatically)
- Android: `engine/android/build.sh` (cross-compiles KataGo, bundles networks), then
  `cd app && flutter build apk --release` (~160 MB with both networks)
- iOS: see `engine/ios/README.md` (needs a Mac / macOS CI)

## Tests
- `packages/go_core`: `dart test`
- `packages/katago_engine`: `dart test` (uses the real engine if installed)
- `app`: `flutter test` and `flutter test integration_test -d windows`
  (full games against the real engine; set `GOSTUDY_SHOTS=<dir>` for screenshots)
