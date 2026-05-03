//
//  ContentView.swift
//  AppleWatchMaps Watch App
//
//  Created by dzb on 2026/5/1.
//

import SwiftUI

struct ContentView: View {
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var notificationManager: NavigationNotificationManager

    @State private var destination = ""

    var body: some View {
        Form {
            Section {
                TextField("服务地址", text: $notificationManager.serverURLString)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Button {
                    notificationManager.discoverServer()
                } label: {
                    Label("自动发现服务", systemImage: "dot.radiowaves.left.and.right")
                }

                Button {
                    Task {
                        await notificationManager.scanServerByAddress()
                    }
                } label: {
                    Label("扫描服务地址", systemImage: "magnifyingglass")
                }

                Text(notificationManager.serviceDiscoveryStatus)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text(notificationManager.serviceScanStatus)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Section {
                TextField("目的地", text: $destination)

                Button {
                    Task {
                        if let target = await notificationManager.fetchLatestDestination() {
                            destination = target.targetName
                        }
                    }
                } label: {
                    Label("获取最新目的地", systemImage: "arrow.down.circle")
                }

                Button {
                    Task {
                        await notificationManager.runNetworkDiagnostics()
                    }
                } label: {
                    Label("网络诊断", systemImage: "antenna.radiowaves.left.and.right")
                }

                Button {
                    Task {
                        await notificationManager.requestAuthorization()
                    }
                } label: {
                    Label("允许通知", systemImage: "bell.badge")
                }

                Button {
                    Task {
                        await notificationManager.scheduleTestNotification(destination: destination)
                    }
                } label: {
                    Label("发送测试通知", systemImage: "paperplane")
                }
            }

            Section {
                Toggle("直接进入路线", isOn: $notificationManager.opensRouteDirectly)

                Button {
                    notificationManager.previewMapsURL(for: destination)
                } label: {
                    Label("生成调试 URL", systemImage: "doc.text.magnifyingglass")
                }

                Button {
                    notificationManager.queueMapsURL(for: destination)
                } label: {
                    Label("直接打开地图", systemImage: "map")
                }
            }

            Section {
                Label(notificationManager.authorizationStatus, systemImage: "checkmark.shield")
                Label(notificationManager.fetchStatus, systemImage: "network")
                Text("Last: \(notificationManager.lastDestination)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("调试") {
                Text("服务端：\(notificationManager.latestServerDebug)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text("模式：\(notificationManager.lastMapMode)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text("搜索词：\(notificationManager.lastLookupQuery)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text("路线目的地：\(notificationManager.lastRouteDestination)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text("URL：\(notificationManager.lastMapURLDescription)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text("网络：\(notificationManager.networkDiagnosticStatus)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if let lastError = notificationManager.lastError {
                Section {
                    Label(lastError, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }
        }
        .onChange(of: notificationManager.pendingMapURL) { _, url in
            guard let url else { return }
            openURL(url)
            notificationManager.pendingMapURL = nil
        }
        .task {
            notificationManager.configure()
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(NavigationNotificationManager.shared)
}
