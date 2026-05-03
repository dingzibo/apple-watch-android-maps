# Share To Watch

Android 端分享接收应用，用来接收地图 App 分享的位置，并在手机本地提供 `/latest` 接口给 Apple Watch 读取。

## 工作流程

1. 从高德地图、百度地图或其他地图 App 分享一个地点。
2. Android 通过 `ACTION_SEND` 打开本应用。
3. 本应用解析分享文本、地址、短链接和经纬度。
4. 本应用把最新目的地保存到本机。
5. 本应用启动 Android 前台服务，并在 `8765` 端口提供 HTTP 接口。
6. Apple Watch 访问 `/latest` 获取目的地，然后打开 Apple 地图。

## 服务地址

Android App 页面会显示本机服务地址：

```text
http://<安卓手机IP>:8765/latest
```

Apple Watch 端需要填写或发现这个地址。

## 在 Android Studio 中运行

用 Android Studio 打开当前目录：

```text
AndroidShareToWatch_Gradle/
```

等待 Gradle Sync 完成后，运行 `app` 模块。

## 使用 Gradle 构建 APK

```bash
./gradlew :app:assembleDebug
```

APK 输出路径：

```text
app/build/outputs/apk/debug/app-debug.apk
```

## 旧手工脚本

项目仍保留早期手工构建脚本：

```bash
bash build.sh
```

输出路径：

```text
build/outputs/share-to-watch-debug.apk
```

现在推荐优先使用 Gradle 构建。

## 手动测试服务

在同一局域网的其他设备上可以访问：

```bash
curl http://<安卓手机IP>:8765/latest
```

如果返回 JSON，说明 Android 端服务已经正常运行。

## 主要代码位置

```text
app/src/main/java/com/dzb/applewatchsender/MainActivity.kt
```

其中：

- `MainActivity`：接收分享、展示页面、保存目的地。
- `NavigationHttpService`：Android 前台服务和本机 HTTP 服务。
- `DestinationParser`：解析高德、百度等地图分享文本。
- `DestinationStore`：保存和读取最新目的地 JSON。
- `NetworkUtils`：获取手机本机局域网 IP。
