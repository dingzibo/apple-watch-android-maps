#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
SDK_DIR="${ANDROID_HOME:-"$HOME/Library/Android/sdk"}"
BUILD_TOOLS_DIR="${BUILD_TOOLS_DIR:-"$SDK_DIR/build-tools/35.0.0"}"
ANDROID_JAR="${ANDROID_JAR:-"$SDK_DIR/platforms/android-34/android.jar"}"
KOTLINC="${KOTLINC:-"/Applications/Android Studio.app/Contents/plugins/Kotlin/kotlinc/bin/kotlinc"}"
KOTLIN_STDLIB="${KOTLIN_STDLIB:-"/Applications/Android Studio.app/Contents/plugins/Kotlin/kotlinc/lib/kotlin-stdlib.jar"}"

OUT_DIR="$ROOT_DIR/build"
INTERMEDIATES_DIR="$OUT_DIR/intermediates"
OUTPUT_DIR="$OUT_DIR/outputs"
KEYSTORE="$OUT_DIR/debug.keystore"
APP_ID="com.dzb.applewatchsender"

if [[ ! -f "$ANDROID_JAR" ]]; then
  echo "Missing Android platform jar: $ANDROID_JAR" >&2
  exit 1
fi

if [[ ! -f "$KOTLINC" ]]; then
  echo "Missing Kotlin compiler: $KOTLINC" >&2
  exit 1
fi

rm -rf "$INTERMEDIATES_DIR" "$OUTPUT_DIR"
mkdir -p "$INTERMEDIATES_DIR/res" "$INTERMEDIATES_DIR/generated" "$INTERMEDIATES_DIR/dex" "$OUTPUT_DIR"

"$BUILD_TOOLS_DIR/aapt2" compile \
  --dir "$ROOT_DIR/app/src/main/res" \
  -o "$INTERMEDIATES_DIR/res/compiled-res.zip"

"$BUILD_TOOLS_DIR/aapt2" link \
  -I "$ANDROID_JAR" \
  --manifest "$ROOT_DIR/app/src/main/AndroidManifest.xml" \
  --java "$INTERMEDIATES_DIR/generated" \
  --auto-add-overlay \
  -R "$INTERMEDIATES_DIR/res/compiled-res.zip" \
  -o "$INTERMEDIATES_DIR/linked.apk"

bash "$KOTLINC" \
  "$ROOT_DIR/app/src/main/java/com/dzb/applewatchsender/MainActivity.kt" \
  -cp "$ANDROID_JAR" \
  -d "$INTERMEDIATES_DIR/classes.jar" \
  -jvm-target 1.8

"$BUILD_TOOLS_DIR/d8" \
  --lib "$ANDROID_JAR" \
  --output "$INTERMEDIATES_DIR/dex" \
  "$INTERMEDIATES_DIR/classes.jar" \
  "$KOTLIN_STDLIB"

cp "$INTERMEDIATES_DIR/linked.apk" "$INTERMEDIATES_DIR/unsigned.apk"
(cd "$INTERMEDIATES_DIR/dex" && zip -q -r "$INTERMEDIATES_DIR/unsigned.apk" classes.dex)

"$BUILD_TOOLS_DIR/zipalign" -p -f 4 \
  "$INTERMEDIATES_DIR/unsigned.apk" \
  "$INTERMEDIATES_DIR/aligned.apk"

if [[ ! -f "$KEYSTORE" ]]; then
  keytool -genkeypair \
    -keystore "$KEYSTORE" \
    -storepass android \
    -alias androiddebugkey \
    -keypass android \
    -keyalg RSA \
    -keysize 2048 \
    -validity 10000 \
    -dname "CN=Android Debug,O=Android,C=US" >/dev/null
fi

"$BUILD_TOOLS_DIR/apksigner" sign \
  --ks "$KEYSTORE" \
  --ks-pass pass:android \
  --key-pass pass:android \
  --out "$OUTPUT_DIR/share-to-watch-debug.apk" \
  "$INTERMEDIATES_DIR/aligned.apk"

"$BUILD_TOOLS_DIR/apksigner" verify "$OUTPUT_DIR/share-to-watch-debug.apk"

echo "Built $OUTPUT_DIR/share-to-watch-debug.apk"
echo "Package: $APP_ID"
