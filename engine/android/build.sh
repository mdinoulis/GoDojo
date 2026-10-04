#!/usr/bin/env bash
# Cross-compiles KataGo (Eigen CPU backend) for Android and installs it into
# the Flutter app as app/android/app/src/main/jniLibs/<abi>/libkatago.so.
# Usage: engine/android/build.sh [abi...]   (default: arm64-v8a x86_64)
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
KATAGO_VERSION=1.18.1
EIGEN_VERSION=3.4.0
SDK="${GODOJO_ANDROID_SDK:-$LOCALAPPDATA/Android/Sdk}"
NDK="${GODOJO_NDK:-$SDK/ndk/27.0.12077973}"
CMAKE_DIR="$SDK/cmake/3.22.1/bin"
ABIS=("${@:-arm64-v8a x86_64}")
ABIS=(${ABIS[@]})
B="$HERE/build"
mkdir -p "$B"
cd "$B"
[ -d "KataGo-$KATAGO_VERSION" ] || { curl -sL "https://github.com/lightvector/KataGo/archive/refs/tags/v$KATAGO_VERSION.tar.gz" | tar xz; }
[ -d "eigen-$EIGEN_VERSION" ] || { curl -sL "https://gitlab.com/libeigen/eigen/-/archive/$EIGEN_VERSION/eigen-$EIGEN_VERSION.tar.gz" | tar xz; }

for ABI in "${ABIS[@]}"; do
  OUT="$B/out-$ABI"
  "$CMAKE_DIR/cmake" -S "KataGo-$KATAGO_VERSION/cpp" -B "$OUT" -G Ninja \
    -DCMAKE_MAKE_PROGRAM="$CMAKE_DIR/ninja" \
    -DCMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake" \
    -DANDROID_ABI="$ABI" -DANDROID_PLATFORM=android-26 -DANDROID_STL=c++_static \
    -DCMAKE_BUILD_TYPE=Release \
    -DUSE_BACKEND=EIGEN -DEIGEN3_INCLUDE_DIRS="$B/eigen-$EIGEN_VERSION" \
    -DNO_GIT_REVISION=1 -DCMAKE_CXX_FLAGS="-include endian.h"
  "$CMAKE_DIR/cmake" --build "$OUT" --target katago -j 16
  DEST="$HERE/../../app/android/app/src/main/jniLibs/$ABI"
  mkdir -p "$DEST"
  cp "$OUT/katago" "$DEST/libkatago.so"
  "$NDK/toolchains/llvm/prebuilt/windows-x86_64/bin/llvm-strip" "$DEST/libkatago.so"
  ls -la "$DEST/libkatago.so"
done

# Networks + config bundled into the APK (copied to app storage on first run).
ASSETS="$HERE/../../app/android/app/src/main/assets/katago"
mkdir -p "$ASSETS"
# The ".asset" suffix stops the Android build from gunzipping the networks
# (and stripping ".gz"); MainActivity removes it when installing.
rm -f "$ASSETS"/*
cp "$HERE/../models/kata1-b15c192-s1672170752-d466197061.txt.gz" "$ASSETS/kata1-b15c192-s1672170752-d466197061.txt.gz.asset"
cp "$HERE/../models/b18c384nbt-humanv0.bin.gz" "$ASSETS/b18c384nbt-humanv0.bin.gz.asset"
cp "$HERE/../configs/analysis_mobile.cfg" "$ASSETS/analysis_mobile.cfg.asset"
ls -la "$ASSETS"
