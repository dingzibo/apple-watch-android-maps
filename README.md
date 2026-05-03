# Apple Watch Android Maps

Send map locations from an Android phone to Apple Watch, then open them in Apple Maps.

## Project Structure

```text
AppleWatchMaps/              watchOS app
AndroidShareToWatch_Gradle/  Android share receiver and local HTTP service
```

The old `AndroidShareToWatch/` directory is kept locally for reference and is intentionally ignored by Git.

## How It Works

1. Share a location from an Android map app, such as Amap or Baidu Maps.
2. Android opens `AndroidShareToWatch_Gradle`.
3. The Android app parses the shared text/link, resolves destination coordinates when possible, and stores the latest destination.
4. The Android app runs a foreground HTTP service on port `8765`.
5. Apple Watch fetches `http://<android-phone-ip>:8765/latest`.
6. The watchOS app opens Apple Maps with the fetched destination.

No APNs, cloud server, or Mac forwarding service is required for the main flow.

## Android

Open `AndroidShareToWatch_Gradle/` in Android Studio and run the `app` module.

Build from terminal:

```bash
cd AndroidShareToWatch_Gradle
./gradlew :app:assembleDebug
```

APK output:

```text
AndroidShareToWatch_Gradle/app/build/outputs/apk/debug/app-debug.apk
```

## watchOS

Open `AppleWatchMaps/AppleWatchMaps.xcodeproj` in Xcode and run the Watch app target.

On the watch app:

1. Enter the Android service URL, for example `http://192.168.1.23:8765/latest`.
2. Or use service discovery / address scan when the network supports it.
3. Tap "获取最新目的地".
4. Tap "直接打开地图".

See `AppleWatchMaps/README.md` for watchOS-specific details.

## Git Hygiene

Ignored local-only files include:

- Android build outputs, APKs, Gradle caches, Android Studio local settings, and `local.properties`
- Xcode user settings and build outputs
- Optional mock server data under `AppleWatchMaps/server/`
- Old manual Android project under `AndroidShareToWatch/`

## License

MIT
