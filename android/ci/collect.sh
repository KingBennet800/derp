#!/usr/bin/env bash
# Copy the built APKs to $1 under their release names:
# derp-android-arm64.apk, derp-android-arm.apk, derp-android-x86_64.apk.
set -euo pipefail
out=$1 built=android/app/build/outputs/apk/release
mkdir -p "$out"
cp "$built/app-arm64-v8a-release.apk" "$out/derp-android-arm64.apk"
cp "$built/app-armeabi-v7a-release.apk" "$out/derp-android-arm.apk"
cp "$built/app-x86_64-release.apk" "$out/derp-android-x86_64.apk"
ls -la "$out"
