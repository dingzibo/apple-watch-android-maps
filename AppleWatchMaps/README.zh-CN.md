# AppleWatchMaps

这是 Apple Watch 端应用，用来从 Android 手机获取最新地图目的地，并在 Apple 地图中打开。

## 在整体系统中的作用

这个 App 是 Apple Watch 客户端。它不负责启动服务，也不依赖 Mac 转发。

它读取的数据来自 Android 手机端：

```text
AndroidShareToWatch_Gradle 前台服务
http://<安卓手机IP>:8765/latest
```

## 主要功能

- 在手表上保存 Android 服务地址。
- 在网络支持时，通过 Bonjour 自动发现 Android 服务。
- 扫描常见局域网地址前缀，尝试找到 Android 服务。
- 从 `/latest` 获取最新目的地 JSON。
- 如果有经纬度，优先用经纬度打开 Apple 地图。
- 如果没有经纬度，使用地点名称或地址搜索。
- 提供网络诊断，用来检查公网和 Android 服务是否可达。

## 在 Xcode 中运行

1. 打开 `AppleWatchMaps.xcodeproj`。
2. 选择 Watch App scheme。
3. 选择已配对的 Apple Watch 或 watchOS 模拟器。
4. Build and Run。

真机测试网络问题时，建议把 App 正常安装到手表后，从手表上直接打开测试。Xcode 调试挂载状态下，watchOS 有时会出现和正常运行不同的网络错误。

## Android 服务地址

在手表 App 的“服务地址”输入框中，填写 Android App 显示的地址：

```text
http://<安卓手机IP>:8765/latest
```

示例：

```text
http://192.168.1.23:8765/latest
```

也可以输入较短形式，App 内部会自动补齐：

```text
192.168.1.23:8765/latest
```

## 期望的 JSON 数据

Android App 返回的数据类似：

```json
{
  "target_name": "示例地点",
  "address": "示例地址",
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

字段说明：

- `target_name`：目的地名称。
- `address`：目的地地址。
- `destination_lat` / `destination_lng`：目的地经纬度。
- `coord_source`：坐标来源，例如高德短链接解析、Android Geocoder。
- `coord_type`：坐标类型，例如 `gcj02`。

## 说明

`server/` 目录是早期本地 mock server，用来模拟 `/latest` 接口。当前主流程已经改为 Android App 提供服务，因此 `server/` 在总仓库中被忽略，不会提交。
