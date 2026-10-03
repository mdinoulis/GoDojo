# KataGo on iOS (in-process, Metal backend)

iOS apps cannot launch subprocesses, so KataGo is linked into the app and run on
a background thread. `katago_bridge.cpp` redirects KataGo's stdin/stdout/stderr
to in-memory line queues; the Dart side (`app/lib/ffi_transport.dart`) talks to
it through `dart:ffi` using exactly the same JSON analysis protocol as on
Windows/Android.

> Status: the bridge itself is tested - linked with KataGo 1.18.1 (Eigen
> backend) into a test driver (`bridge_test/driver.cpp`, built by hand from the
> Android x86_64 objects) and run on an Android emulator: it starts in-process,
> reports "ready" via the redirected stderr, answers a query and exits cleanly.
> The iOS build (Metal backend, Xcode linking) has **not** been run yet - it
> needs a Mac with Xcode 16+ or a macOS CI runner (Codemagic, GitHub Actions).

## Build steps (on macOS)

1. Fetch KataGo 1.18.1 (`engine/android/build.sh` downloads it into
   `engine/android/build/KataGo-1.18.1`, or clone the tag).
2. Build KataGo's sources as a static library for `iphoneos` / arm64 with the
   Metal backend (`-DUSE_BACKEND=METAL`), adding `engine/ios/katago_bridge.cpp`
   and compiling `cpp/main.cpp` with `-Dmain=katago_cli_main`. A practical
   route is the Xcode project used by the KataGo iOS port (KataGo Anytime,
   github.com/ChinChangYang/KataGo), which already builds these sources for
   iOS with Metal + Core ML.
3. Link the static library (and its Swift/CoreML parts) into `Runner` and make
   sure the `katago_*` symbols are kept (add `-Wl,-exported_symbol,_katago_*`
   or reference them), since Dart looks them up with `DynamicLibrary.process()`.
4. Add a folder reference named `katago` to the Runner target containing:
   - `kata1-b15c192-s1672170752-d466197061.txt.gz` (analysis)
   - `b18c384nbt-humanv0.bin.gz` (human-style levels)
   - `engine/configs/analysis_mobile.cfg`
   `AppDelegate.installEngineFiles` copies them to Application Support on
   first launch.
5. `flutter build ios`.
