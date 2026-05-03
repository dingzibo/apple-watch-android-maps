# Apple Watch Android Maps

把安卓手机地图 App 分享出来的位置发送到 Apple Watch，并在 Apple 地图中打开。

## 项目结构

```text
AppleWatchMaps/              watchOS 应用
AndroidShareToWatch_Gradle/  Android 分享接收应用和本机 HTTP 服务
```

旧的 `AndroidShareToWatch/` 目录只保留在本机作为参考，已经被 Git 忽略，不会提交到仓库。

## 工作流程

1. 在安卓地图 App 中分享一个地点，例如高德地图或百度地图。
2. Android 系统通过 `ACTION_SEND` 打开 `AndroidShareToWatch_Gradle`。
3. Android App 解析分享文本或短链接，尽量解析出目的地名称、地址和经纬度。
4. Android App 把最新目的地保存到本机。
5. Android App 启动前台服务，在手机本地监听 `8765` 端口。
6. Apple Watch 访问 `http://<安卓手机IP>:8765/latest` 获取最新目的地。
7. watchOS App 使用目的地信息打开 Apple 地图。

主流程不需要 APNs、不需要云服务器，也不需要 Mac 做转发。

## Android 端

用 Android Studio 打开：

```text
AndroidShareToWatch_Gradle/
```

然后运行 `app` 模块。

也可以在终端构建 APK：

```bash
cd AndroidShareToWatch_Gradle
./gradlew :app:assembleDebug
```

APK 输出路径：

```text
AndroidShareToWatch_Gradle/app/build/outputs/apk/debug/app-debug.apk
```

Android App 启动后会显示本机服务地址，格式类似：

```text
http://192.168.1.23:8765/latest
```

## Apple Watch 端

用 Xcode 打开：

```text
AppleWatchMaps/AppleWatchMaps.xcodeproj
```

选择 Watch App target，然后运行到 Apple Watch 或 watchOS 模拟器。

在手表 App 中：

1. 输入 Android App 显示的服务地址，例如 `http://192.168.1.23:8765/latest`。
2. 如果局域网支持，也可以使用“自动发现服务”或“扫描服务地址”。
3. 点击“获取最新目的地”。
4. 点击“直接打开地图”。

更详细的 watchOS 说明见：

```text
AppleWatchMaps/README.zh-CN.md
```

## 为什么不用服务器

这个项目当前采用局域网本机通信：

```text
Android 手机本机 HTTP 服务 -> Apple Watch 拉取最新目的地
```

这样实现简单、调试直接，也不需要维护云端服务。缺点是 Apple Watch 和 Android 手机需要处在能互相访问的网络环境中。

## Git 忽略内容

仓库不会提交这些本机或临时文件：

- Android 构建产物、APK、Gradle 缓存、Android Studio 本机配置、`local.properties`
- Xcode 用户配置和构建产物
- `AppleWatchMaps/server/` 下的本地 mock server 和测试数据
- 旧的手工 Android 项目 `AndroidShareToWatch/`

## License

MIT
