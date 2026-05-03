# Share To Watch

Small Android share receiver for the AppleWatchMaps MVP.

中文说明见 [README.zh-CN.md](README.zh-CN.md).

Flow:

1. Share a location from Amap or another map app.
2. Android opens this app through `ACTION_SEND`.
3. The app saves the destination locally.
4. The app exposes `/latest` from an Android foreground HTTP service.
5. Apple Watch pulls the latest destination and opens Apple Maps.

Android service endpoint:

```text
http://<android-phone-ip>:8765/latest
```

Standard Gradle module (in Android Studio):
1. Open this folder in Android Studio.
2. Allow project sync.
3. Run **app** directly.

You can also build from terminal:

```bash
./gradlew :app:assembleDebug
```

Gradle output:

```text
app/build/outputs/apk/debug/app-debug.apk
```

Note: if you prefer old manual compile, keep using:

```bash
bash build.sh
```

Output:

```text
build/outputs/share-to-watch-debug.apk
```

Manual service test from another device on the same network:

```bash
curl http://<android-phone-ip>:8765/latest
```
