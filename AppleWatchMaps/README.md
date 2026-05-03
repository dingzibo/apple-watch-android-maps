# AppleWatchMaps

watchOS app for fetching the latest map destination from an Android phone and opening it in Apple Maps.

## Role In The System

This app is the Apple Watch client. It does not host a server and does not require a Mac-side proxy in the main flow.

Expected data source:

```text
AndroidShareToWatch_Gradle foreground service
http://<android-phone-ip>:8765/latest
```

## Main Features

- Save an Android service URL on the watch.
- Discover the Android service through Bonjour when the network supports it.
- Scan common local network prefixes for the Android service.
- Fetch the latest destination JSON from `/latest`.
- Open Apple Maps by destination coordinates when available.
- Fall back to name/address search when coordinates are unavailable.
- Provide network diagnostics for public connectivity and Android service reachability.

## Run In Xcode

1. Open `AppleWatchMaps.xcodeproj`.
2. Select the Watch app scheme.
3. Select a paired Apple Watch or watchOS simulator.
4. Build and run.

For real-device testing, install the watch app normally and test outside Xcode debug mode when diagnosing network behavior. Xcode-attached watch debugging can sometimes report network errors that do not happen when the app is launched normally.

## Android Service URL

In the watch app, enter the Android URL shown by the Android app:

```text
http://<android-phone-ip>:8765/latest
```

Example:

```text
http://192.168.1.23:8765/latest
```

The app also accepts the shorter host form and normalizes it internally:

```text
192.168.1.23:8765/latest
```

## Expected JSON

The Android app returns JSON similar to:

```json
{
  "target_name": "Example Place",
  "address": "Example Address",
  "source_name": "",
  "source_lat": null,
  "source_lng": null,
  "destination_lat": 31.230416,
  "destination_lng": 121.473701,
  "coord_source": "amap_redirect",
  "coord_type": "gcj02",
  "share_url": "",
  "updated_at": "2026-01-01T00:00:00.000Z"
}
```

## Notes

The optional `server/` mock server directory is intentionally ignored in the monorepo. The current production flow uses the Android app as the local service provider.
