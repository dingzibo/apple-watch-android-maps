//
//  AppleWatchMapsApp.swift
//  AppleWatchMaps Watch App
//
//  Created by dzb on 2026/5/1.
//

import Foundation
import Network
import OSLog
import SwiftUI
import UserNotifications
import Darwin

@main
struct AppleWatchMaps_Watch_AppApp: App {
    @StateObject private var notificationManager = NavigationNotificationManager.shared

    init() {
        NavigationNotificationManager.shared.configure()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(notificationManager)
        }
    }
}

final class NavigationNotificationManager: NSObject, ObservableObject {
    static let shared = NavigationNotificationManager()

    static let navigateCategoryIdentifier = "NAVIGATE_ACTION"
    static let startNavigationActionIdentifier = "START_NAV_ACTION"
    static let defaultServerURLString = ""
    static let serverURLDefaultsKey = "navigation_server_url"
    static let bonjourServiceType = "_applewatchmaps._tcp."

    @Published var authorizationStatus = "Notification permission not requested"
    @Published var lastDestination = "未获取目的地"
    @Published var pendingMapURL: URL?
    @Published var lastError: String?
    @Published var opensRouteDirectly = false
    @Published var fetchStatus = "未获取服务端地址"
    @Published var serverURLString: String {
        didSet {
            UserDefaults.standard.set(serverURLString, forKey: Self.serverURLDefaultsKey)
        }
    }
    @Published var latestServerDebug = "未获取"
    @Published var lastLookupQuery = "未生成"
    @Published var lastRouteDestination = "未生成"
    @Published var lastMapURLDescription = "未生成"
    @Published var lastMapMode = "未打开地图"
    @Published var networkDiagnosticStatus = "未诊断"
    @Published var serviceDiscoveryStatus = "未发现服务"
    @Published var serviceScanStatus = "未扫描"

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.dzb.AppleWatchMaps.watchkitapp",
        category: "Navigation"
    )
    private var serviceBrowser: NWBrowser?
    private var discoveredServiceEndpoint: NWEndpoint?

    private override init() {
        let savedServerURLString = UserDefaults.standard.string(forKey: Self.serverURLDefaultsKey)
            ?? Self.defaultServerURLString
        serverURLString = savedServerURLString.hasPrefix("bonjour://") ? "" : savedServerURLString
        super.init()
    }

    func configure() {
        let startAction = UNNotificationAction(
            identifier: Self.startNavigationActionIdentifier,
            title: "开始导航",
            options: [.foreground]
        )

        let category = UNNotificationCategory(
            identifier: Self.navigateCategoryIdentifier,
            actions: [startAction],
            intentIdentifiers: [],
            options: []
        )

        let center = UNUserNotificationCenter.current()
        center.setNotificationCategories([category])
        center.delegate = self
    }

    @MainActor
    func requestAuthorization() async {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            authorizationStatus = granted ? "Notifications allowed" : "Notifications denied"
            lastError = nil
        } catch {
            authorizationStatus = "Notification permission failed"
            lastError = error.localizedDescription
        }
    }

    @MainActor
    func scheduleTestNotification(destination: String) async {
        let trimmedDestination = destination.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedDestination.isEmpty else {
            lastError = "Please enter a destination"
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "收到新的导航目标"
        content.body = "准备前往：\(trimmedDestination)"
        content.sound = .default
        content.categoryIdentifier = Self.navigateCategoryIdentifier
        let customData: [String: Any] = [
            "target_name": trimmedDestination,
            "source_name": ""
        ]

        content.userInfo = [
            "customData": customData
        ]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: trigger
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
            lastDestination = trimmedDestination
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    @MainActor
    func fetchLatestDestination() async -> NavigationTarget? {
        fetchStatus = "正在获取..."

        do {
            let (data, statusCode) = try await fetchServiceData(path: "/latest")

            guard (200..<300).contains(statusCode) else {
                fetchStatus = "获取失败"
                lastError = "Server returned HTTP \(statusCode)"
                return nil
            }

            let target = try JSONDecoder().decode(NavigationTarget.self, from: data)
            latestTarget = target
            lastDestination = target.targetName
            fetchStatus = "已获取：\(target.targetName)"
            latestServerDebug = target.debugSummary
            log("Fetched latest destination: \(target.debugSummary)")
            lastError = nil
            return target
        } catch {
            fetchStatus = "获取失败"
            lastError = error.localizedDescription
            return nil
        }
    }

    @MainActor
    func runNetworkDiagnostics() async {
        networkDiagnosticStatus = "诊断中..."

        let publicURL = URL(string: "https://www.apple.com/library/test/success.html")!
        let publicResult = await diagnosticResult(name: "公网", url: publicURL)
        let healthResult = await serviceDiagnosticResult(name: "Android health", path: "/health")
        let latestResult = await serviceDiagnosticResult(name: "Android latest", path: "/latest")
        networkDiagnosticStatus = [publicResult, healthResult, latestResult].joined(separator: "\n")
    }

    @MainActor
    func discoverServer() {
        serviceDiscoveryStatus = "正在发现安卓服务..."
        lastError = nil

        serviceBrowser?.cancel()

        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true
        let browser = NWBrowser(
            for: .bonjour(type: Self.bonjourServiceType, domain: nil),
            using: parameters
        )

        browser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready:
                    self?.serviceDiscoveryStatus = "正在搜索 \(Self.bonjourServiceType)"
                case .failed(let error):
                    self?.serviceDiscoveryStatus = "发现失败：\(error.localizedDescription)"
                case .cancelled:
                    break
                default:
                    break
                }
            }
        }

        browser.browseResultsChangedHandler = { [weak self] results, _ in
            guard let result = results.first else {
                return
            }

            browser.cancel()
            Task { @MainActor in
                self?.discoveredServiceEndpoint = result.endpoint
                self?.serviceDiscoveryStatus = "已发现：\(Self.displayString(for: result.endpoint))"
                self?.networkDiagnosticStatus = "未诊断"
                self?.lastError = nil
            }
        }

        serviceBrowser = browser
        browser.start(queue: .global(qos: .userInitiated))
    }

    @MainActor
    func scanServerByAddress() async {
        discoveredServiceEndpoint = nil
        serviceScanStatus = "正在扫描..."
        lastError = nil

        let candidates = scanCandidates()
        guard !candidates.isEmpty else {
            serviceScanStatus = "没有可扫描的地址"
            return
        }

        if let foundURL = await findFirstHealthyServer(in: candidates) {
            serverURLString = foundURL.absoluteString
            serviceScanStatus = "已找到：\(foundURL.absoluteString)"
            networkDiagnosticStatus = "未诊断"
        } else {
            serviceScanStatus = "未找到服务，已扫描 \(candidates.count) 个地址"
        }
    }

    private func endpointURL(path: String) -> URL? {
        var value = serverURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            return nil
        }

        if !value.lowercased().hasPrefix("http://") && !value.lowercased().hasPrefix("https://") {
            value = "http://\(value)"
        }

        guard var components = URLComponents(string: value) else {
            return nil
        }

        components.path = path
        components.query = nil
        components.fragment = nil
        return components.url
    }

    private func fetchServiceData(path: String) async throws -> (Data, Int) {
        if let url = endpointURL(path: path) {
            let (data, response) = try await URLSession.shared.data(from: url)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            return (data, statusCode)
        }

        if let discoveredServiceEndpoint {
            return try await fetchBonjourData(path: path, endpoint: discoveredServiceEndpoint)
        }

        throw URLError(.badURL)
    }

    private func fetchBonjourData(path: String, endpoint: NWEndpoint) async throws -> (Data, Int) {
        try await withCheckedThrowingContinuation { continuation in
            let parameters = NWParameters.tcp
            parameters.includePeerToPeer = true
            let connection = NWConnection(to: endpoint, using: parameters)
            let state = BonjourHTTPState()

            @Sendable func finish(_ result: Result<(Data, Int), Error>) {
                guard !state.didResume else {
                    return
                }

                state.didResume = true
                connection.cancel()
                continuation.resume(with: result)
            }

            @Sendable func parseResponse() {
                let separator = Data("\r\n\r\n".utf8)
                guard let headerRange = state.responseData.range(of: separator),
                      let statusLine = String(
                        data: state.responseData[..<headerRange.lowerBound],
                        encoding: .utf8
                      )?.components(separatedBy: "\r\n").first else {
                    finish(.failure(URLError(.badServerResponse)))
                    return
                }

                let statusCode = Int(statusLine.split(separator: " ").dropFirst().first ?? "") ?? 0
                let body = state.responseData[headerRange.upperBound...]
                finish(.success((Data(body), statusCode)))
            }

            @Sendable func receive() {
                connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
                    if let data {
                        state.responseData.append(data)
                    }

                    if let error {
                        finish(.failure(error))
                        return
                    }

                    if isComplete {
                        parseResponse()
                        return
                    }

                    receive()
                }
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let request = [
                        "GET \(path) HTTP/1.1",
                        "Host: applewatchmaps.local",
                        "Accept: application/json",
                        "Connection: close",
                        "",
                        ""
                    ].joined(separator: "\r\n")

                    connection.send(content: Data(request.utf8), completion: .contentProcessed { error in
                        if let error {
                            finish(.failure(error))
                            return
                        }

                        receive()
                    })
                case .failed(let error):
                    finish(.failure(error))
                case .cancelled:
                    finish(.failure(URLError(.cancelled)))
                default:
                    break
                }
            }

            connection.start(queue: .global(qos: .userInitiated))
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 8) {
                finish(.failure(URLError(.timedOut)))
            }
        }
    }

    private func diagnosticResult(name: String, url: URL) async -> String {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 6
        configuration.timeoutIntervalForResource = 8
        configuration.waitsForConnectivity = false

        do {
            let (_, response) = try await URLSession(configuration: configuration).data(from: url)
            if let httpResponse = response as? HTTPURLResponse {
                return "\(name): HTTP \(httpResponse.statusCode)"
            }

            return "\(name): 已连接"
        } catch {
            let nsError = error as NSError
            return "\(name): \(nsError.domain) \(nsError.code) \(nsError.localizedDescription)"
        }
    }

    private func scanCandidates() -> [URL] {
        let prefixes = scanPrefixes()
        return prefixes.flatMap { prefix in
            (1...254).compactMap { hostLastPart in
                URL(string: "http://\(prefix).\(hostLastPart):8765/health")
            }
        }
    }

    private func scanPrefixes() -> [String] {
        var prefixes: [String] = []

        if let host = endpointURL(path: "/health")?.host(),
           let prefix = ipv4Prefix(from: host) {
            prefixes.append(prefix)
        }

        prefixes.append(contentsOf: localIPv4Prefixes())

        prefixes.append(contentsOf: [
            "192.168.0",
            "192.168.1",
            "10.16.0",
            "10.16.1"
        ])

        return Array(NSOrderedSet(array: prefixes)) as? [String] ?? prefixes
    }

    private func localIPv4Prefixes() -> [String] {
        localIPv4Addresses().compactMap { ipv4Prefix(from: $0) }
    }

    private func localIPv4Addresses() -> [String] {
        var interfacePointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfacePointer) == 0, let firstInterface = interfacePointer else {
            return []
        }
        defer {
            freeifaddrs(interfacePointer)
        }

        var addresses: [String] = []
        var cursor: UnsafeMutablePointer<ifaddrs>? = firstInterface

        while let interface = cursor {
            defer {
                cursor = interface.pointee.ifa_next
            }

            let flags = Int32(interface.pointee.ifa_flags)
            guard flags & IFF_UP != 0,
                  flags & IFF_LOOPBACK == 0,
                  let address = interface.pointee.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_INET) else {
                continue
            }

            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                address,
                socklen_t(address.pointee.sa_len),
                &hostname,
                socklen_t(hostname.count),
                nil,
                0,
                NI_NUMERICHOST
            )

            guard result == 0 else {
                continue
            }

            addresses.append(String(cString: hostname))
        }

        return addresses
    }

    private func ipv4Prefix(from host: String) -> String? {
        let parts = host.split(separator: ".")
        guard parts.count == 4,
              parts.allSatisfy({ Int($0) != nil }) else {
            return nil
        }

        return parts.prefix(3).joined(separator: ".")
    }

    private func findFirstHealthyServer(in urls: [URL]) async -> URL? {
        await withTaskGroup(of: URL?.self) { group in
            let batchSize = 32
            var nextIndex = 0

            func addNextBatch() {
                let endIndex = min(nextIndex + batchSize, urls.count)
                guard nextIndex < endIndex else {
                    return
                }

                for url in urls[nextIndex..<endIndex] {
                    group.addTask {
                        await Self.isHealthyServer(url) ? url : nil
                    }
                }
                nextIndex = endIndex
            }

            addNextBatch()

            while let result = await group.next() {
                if let result {
                    group.cancelAll()
                    return normalizedLatestURL(from: result)
                }

                if nextIndex < urls.count {
                    addNextBatch()
                }
            }

            return nil
        }
    }

    private static func isHealthyServer(_ url: URL) async -> Bool {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 0.8
        configuration.timeoutIntervalForResource = 1.2
        configuration.waitsForConnectivity = false

        do {
            let (_, response) = try await URLSession(configuration: configuration).data(from: url)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    private func normalizedLatestURL(from healthURL: URL) -> URL? {
        guard var components = URLComponents(url: healthURL, resolvingAgainstBaseURL: false) else {
            return nil
        }

        components.path = "/latest"
        components.query = nil
        components.fragment = nil
        return components.url
    }

    private func serviceDiagnosticResult(name: String, path: String) async -> String {
        do {
            let (_, statusCode) = try await fetchServiceData(path: path)
            return "\(name): HTTP \(statusCode)"
        } catch {
            let nsError = error as NSError
            return "\(name): \(nsError.domain) \(nsError.code) \(nsError.localizedDescription)"
        }
    }

    @MainActor
    func previewMapsURL(for destination: String) {
        guard let request = makeMapsRequest(for: destination) else {
            return
        }

        recordMapsRequest(request)
        lastDestination = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        lastError = nil
    }

    @MainActor
    func queueMapsURL(for destination: String) {
        guard let request = makeMapsRequest(for: destination) else {
            return
        }

        recordMapsRequest(request)
        lastDestination = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        pendingMapURL = request.url
        lastError = nil
    }

    @MainActor
    private func makeMapsRequest(for destination: String) -> MapsRequest? {
        let trimmedDestination = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        let fetchedTarget = latestTarget?.targetName == trimmedDestination ? latestTarget : nil
        let coordinate = fetchedTarget?.destinationCoordinate
        let searchName = fetchedTarget?.lookupQuery ?? trimmedDestination
        let routeDestination = coordinate ?? searchName
        let sourceCoordinate = fetchedTarget?.sourceCoordinate

        let mode: String
        let url: URL?

        if opensRouteDirectly {
            mode = coordinate == nil ? "route-by-text" : "route-by-coordinate"
            url = Self.mapsURL(source: sourceCoordinate, destination: routeDestination)
        } else if let coordinate {
            mode = "show-coordinate"
            url = Self.coordinateURL(coordinate: coordinate)
        } else if fetchedTarget?.hasAddress == true {
            mode = "show-address"
            url = Self.addressURL(address: searchName)
        } else {
            mode = "search"
            url = Self.searchURL(query: searchName)
        }

        guard let url else {
            lastError = "Could not build Apple Maps URL"
            return nil
        }

        return MapsRequest(
            url: url,
            mode: mode,
            lookupQuery: searchName,
            routeDestination: routeDestination,
            source: sourceCoordinate
        )
    }

    static func mapsURL(for destination: String) -> URL? {
        mapsURL(source: nil, destination: destination)
    }

    static func mapsURL(source: String?, destination: String) -> URL? {
        var components = URLComponents()
        components.scheme = "http"
        components.host = "maps.apple.com"
        components.path = "/"

        var queryItems = [
            URLQueryItem(name: "daddr", value: destination),
            URLQueryItem(name: "dirflg", value: "d")
        ]

        if let source {
            queryItems.insert(URLQueryItem(name: "saddr", value: source), at: 0)
        }

        components.queryItems = queryItems
        return components.url
    }

    static func coordinateURL(coordinate: String) -> URL? {
        var components = URLComponents()
        components.scheme = "http"
        components.host = "maps.apple.com"
        components.path = "/"
        components.queryItems = [
            URLQueryItem(name: "ll", value: coordinate),
            URLQueryItem(name: "z", value: "18")
        ]
        return components.url
    }

    static func addressURL(address: String) -> URL? {
        var components = URLComponents()
        components.scheme = "http"
        components.host = "maps.apple.com"
        components.path = "/"
        components.queryItems = [
            URLQueryItem(name: "address", value: address),
            URLQueryItem(name: "z", value: "18")
        ]
        return components.url
    }

    static func searchURL(query: String) -> URL? {
        var components = URLComponents()
        components.scheme = "http"
        components.host = "maps.apple.com"
        components.path = "/"
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "z", value: "15")
        ]
        return components.url
    }

    private func mapsRequest(from userInfo: [AnyHashable: Any]) -> MapsRequest? {
        guard let customData = customData(from: userInfo),
              let targetName = customData["target_name"] as? String else {
            return nil
        }

        let source = coordinateString(
            latitude: customData["source_lat"],
            longitude: customData["source_lng"]
        )

        let address = customData["address"] as? String
        let searchName = Self.lookupQuery(targetName: targetName, address: address)

        let destination = coordinateString(
            latitude: customData["destination_lat"],
            longitude: customData["destination_lng"]
        ) ?? searchName

        guard let url = Self.mapsURL(source: source, destination: destination) else {
            return nil
        }

        return MapsRequest(
            url: url,
            mode: "notification-route",
            lookupQuery: searchName,
            routeDestination: destination,
            source: source
        )
    }

    static func lookupQuery(targetName: String, address: String?) -> String {
        [targetName, address]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func targetName(from userInfo: [AnyHashable: Any]) -> String? {
        customData(from: userInfo)?["target_name"] as? String
    }

    private func customData(from userInfo: [AnyHashable: Any]) -> [AnyHashable: Any]? {
        if let customData = userInfo["customData"] as? [String: Any] {
            return Dictionary(uniqueKeysWithValues: customData.map { key, value in
                (AnyHashable(key), value)
            })
        }

        if let customData = userInfo["customData"] as? [AnyHashable: Any] {
            return customData
        }

        return nil
    }

    private func coordinateString(latitude: Any?, longitude: Any?) -> String? {
        guard let latitude = coordinateValue(from: latitude),
              let longitude = coordinateValue(from: longitude) else {
            return nil
        }

        return "\(latitude),\(longitude)"
    }

    private func coordinateValue(from value: Any?) -> Double? {
        if let double = value as? Double {
            return double
        }

        if let number = value as? NSNumber {
            return number.doubleValue
        }

        if let string = value as? String {
            return Double(string)
        }

        return nil
    }

    private func recordMapsRequest(_ request: MapsRequest) {
        lastMapMode = request.mode
        lastLookupQuery = request.lookupQuery
        lastRouteDestination = request.routeDestination
        lastMapURLDescription = Self.displayString(for: request.url)

        log(
            "Opening Maps mode=\(request.mode), lookup=\(request.lookupQuery), routeDestination=\(request.routeDestination), source=\(request.source ?? "nil"), url=\(lastMapURLDescription)"
        )
    }

    private func log(_ message: String) {
        logger.info("\(message, privacy: .public)")
        print("[AppleWatchMaps] \(message)")
    }

    private static func displayString(for url: URL) -> String {
        url.absoluteString.removingPercentEncoding ?? url.absoluteString
    }

    private static func displayString(for endpoint: NWEndpoint) -> String {
        switch endpoint {
        case .service(let name, let type, let domain, _):
            return "bonjour://\(name).\(type)\(domain)"
        case .hostPort(let host, let port):
            return "http://\(host):\(port)/latest"
        case .url(let url):
            return url.absoluteString
        case .unix(let path):
            return "unix://\(path)"
        default:
            return "\(endpoint)"
        }
    }

    private var latestTarget: NavigationTarget?
}

private final class BonjourHTTPState: @unchecked Sendable {
    var responseData = Data()
    var didResume = false
}

struct MapsRequest {
    let url: URL
    let mode: String
    let lookupQuery: String
    let routeDestination: String
    let source: String?
}

struct NavigationTarget: Codable {
    let targetName: String
    let address: String?
    let sourceName: String?
    let sourceLat: Double?
    let sourceLng: Double?
    let destinationLat: Double?
    let destinationLng: Double?
    let updatedAt: String?

    var sourceCoordinate: String? {
        coordinate(latitude: sourceLat, longitude: sourceLng)
    }

    var destinationCoordinate: String? {
        coordinate(latitude: destinationLat, longitude: destinationLng)
    }

    var lookupQuery: String {
        NavigationNotificationManager.lookupQuery(targetName: targetName, address: address)
    }

    var hasAddress: Bool {
        guard let address else {
            return false
        }

        return !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var debugSummary: String {
        let destination = destinationCoordinate ?? "nil"
        let source = sourceCoordinate ?? "nil"
        let addressValue = address?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? address! : "nil"

        return "target=\(targetName), address=\(addressValue), lookup=\(lookupQuery), destination=\(destination), source=\(source)"
    }

    enum CodingKeys: String, CodingKey {
        case targetName = "target_name"
        case address
        case sourceName = "source_name"
        case sourceLat = "source_lat"
        case sourceLng = "source_lng"
        case destinationLat = "destination_lat"
        case destinationLng = "destination_lng"
        case updatedAt = "updated_at"
    }

    private func coordinate(latitude: Double?, longitude: Double?) -> String? {
        guard let latitude, let longitude else {
            return nil
        }

        return "\(latitude),\(longitude)"
    }
}

extension NavigationNotificationManager: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let actionIdentifier = response.actionIdentifier
        let shouldOpenMaps = actionIdentifier == Self.startNavigationActionIdentifier
            || actionIdentifier == UNNotificationDefaultActionIdentifier

        guard shouldOpenMaps else {
            completionHandler()
            return
        }

        let userInfo = response.notification.request.content.userInfo

        Task { @MainActor in
            if let request = self.mapsRequest(from: userInfo) {
                self.lastDestination = self.targetName(from: userInfo) ?? "Navigation target"
                self.recordMapsRequest(request)
                self.pendingMapURL = request.url
                self.lastError = nil
            } else {
                self.lastError = "Notification did not include customData.target_name"
            }
            completionHandler()
        }
    }
}
