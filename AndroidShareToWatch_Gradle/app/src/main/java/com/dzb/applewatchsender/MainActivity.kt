package com.dzb.applewatchsender

import android.Manifest
import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.graphics.Typeface
import android.location.Geocoder
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.os.Build
import android.os.Bundle
import android.os.IBinder
import android.view.Gravity
import android.view.ViewGroup
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import org.json.JSONObject
import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.HttpURLConnection
import java.net.Inet4Address
import java.net.NetworkInterface
import java.net.ServerSocket
import java.net.Socket
import java.net.URL
import java.net.URLDecoder
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

class MainActivity : Activity() {
    private lateinit var serviceAddressView: TextView
    private lateinit var targetInput: EditText
    private lateinit var sharedTextInput: EditText
    private lateinit var statusView: TextView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        requestNotificationPermissionIfNeeded()
        startLocalService()
        buildUi()
        handleIntent(intent, autoSend = true)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent, autoSend = true)
    }

    private fun buildUi() {
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(20), dp(18), dp(20), dp(20))
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
        }

        root.addView(TextView(this).apply {
            text = "发送到 Apple Watch"
            textSize = 24f
            typeface = Typeface.DEFAULT_BOLD
            setPadding(0, 0, 0, dp(14))
        })

        root.addView(label("本机服务地址"))
        serviceAddressView = TextView(this).apply {
            textSize = 16f
            setPadding(0, dp(8), 0, dp(8))
        }
        root.addView(serviceAddressView)

        root.addView(LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL

            addView(Button(this@MainActivity).apply {
                text = "启动服务"
                setOnClickListener {
                    startLocalService()
                    refreshServiceAddress()
                    statusView.text = "本机服务已启动"
                }
            }, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))

            addView(Button(this@MainActivity).apply {
                text = "刷新地址"
                setOnClickListener {
                    refreshServiceAddress()
                    statusView.text = "已刷新服务地址"
                }
            }, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
        })

        root.addView(label("目的地"))
        targetInput = EditText(this).apply {
            setSingleLine(false)
            minLines = 1
            hint = "等待地图分享"
        }
        root.addView(targetInput)

        root.addView(label("分享原文"))
        sharedTextInput = EditText(this).apply {
            setSingleLine(false)
            minLines = 4
            gravity = Gravity.TOP
        }
        root.addView(sharedTextInput)

        root.addView(Button(this).apply {
            text = "保存到本机服务"
            setOnClickListener {
                val parsed = DestinationParser.parse(sharedTextInput.text.toString())
                    .copy(name = targetInput.text.toString().trim().ifEmpty { "未命名地点" })
                saveDestination(parsed)
            }
        })

        statusView = TextView(this).apply {
            text = "等待分享"
            textSize = 16f
            setPadding(0, dp(14), 0, 0)
        }
        root.addView(statusView)

        setContentView(ScrollView(this).apply {
            addView(root)
        })
        refreshServiceAddress()
    }

    private fun handleIntent(intent: Intent?, autoSend: Boolean) {
        val sharedText = intent?.takeIf { it.action == Intent.ACTION_SEND }
            ?.getStringExtra(Intent.EXTRA_TEXT)

        if (sharedText.isNullOrBlank()) {
            return
        }

        sharedTextInput.setText(sharedText)
        val parsed = DestinationParser.parse(sharedText)
        targetInput.setText(parsed.name)
        statusView.text = "已接收分享，准备保存"

        if (autoSend) {
            saveDestination(parsed)
        }
    }

    private fun saveDestination(destination: ParsedDestination) {
        startLocalService()
        refreshServiceAddress()
        statusView.text = "保存中..."

        Thread {
            val result = runCatching {
                val resolvedDestination = resolveDestinationCoordinate(destination)
                DestinationStore.save(this, resolvedDestination)
            }

            runOnUiThread {
                statusView.text = result.fold(
                    onSuccess = { "已保存到本机服务\n$it" },
                    onFailure = { "保存失败：${it.message ?: it.javaClass.simpleName}" }
                )
            }
        }.start()
    }

    @Suppress("DEPRECATION")
    private fun resolveDestinationCoordinate(destination: ParsedDestination): ParsedDestination {
        if (destination.latitude != null && destination.longitude != null) {
            return destination
        }

        val destinationFromShortLink = DestinationParser.resolveAmapShortLink(destination)
        if (destinationFromShortLink.latitude != null && destinationFromShortLink.longitude != null) {
            return destinationFromShortLink
        }

        val destinationFromGoogleLink = DestinationParser.resolveGoogleMapsLink(destinationFromShortLink)
        if (destinationFromGoogleLink.latitude != null && destinationFromGoogleLink.longitude != null) {
            return destinationFromGoogleLink
        }

        if (!Geocoder.isPresent()) {
            return destinationFromGoogleLink
        }

        val query = listOfNotNull(destinationFromGoogleLink.address, destinationFromGoogleLink.name)
            .map { it.trim() }
            .filter { it.isNotEmpty() }
            .distinct()
            .joinToString(" ")

        if (query.isBlank()) {
            return destinationFromGoogleLink
        }

        val address = runCatching {
            Geocoder(this, Locale.CHINA).getFromLocationName(query, 1)?.firstOrNull()
        }.getOrNull() ?: return destinationFromGoogleLink

        return destinationFromGoogleLink.copy(
            latitude = address.latitude,
            longitude = address.longitude,
            coordinateSource = "android_geocoder",
            coordinateType = "unknown"
        )
    }

    private fun startLocalService() {
        val intent = Intent(this, NavigationHttpService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    private fun refreshServiceAddress() {
        val url = NavigationHttpService.serviceUrl()
        serviceAddressView.text = url ?: "未找到局域网 IP，请连接 Wi-Fi 或打开手机热点后刷新"
    }

    private fun requestNotificationPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), NOTIFICATION_PERMISSION_REQUEST)
        }
    }

    private fun label(text: String): TextView {
        return TextView(this).apply {
            this.text = text
            textSize = 13f
            typeface = Typeface.DEFAULT_BOLD
            setPadding(0, dp(12), 0, dp(4))
        }
    }

    private fun dp(value: Int): Int {
        return (value * resources.displayMetrics.density).toInt()
    }

    companion object {
        private const val NOTIFICATION_PERMISSION_REQUEST = 3001
    }
}

class NavigationHttpService : Service() {
    private var serverSocket: ServerSocket? = null
    private var serverThread: Thread? = null
    private var nsdManager: NsdManager? = null
    private var nsdRegistrationListener: NsdManager.RegistrationListener? = null

    override fun onCreate() {
        super.onCreate()
        startForegroundNotification()
        startHttpServer()
        registerBonjourService()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForegroundNotification()
        startHttpServer()
        registerBonjourService()
        return START_STICKY
    }

    override fun onDestroy() {
        unregisterBonjourService()
        serverSocket?.close()
        serverSocket = null
        serverThread = null
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun startForegroundNotification() {
        val notification = buildNotification()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun buildNotification(): Notification {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Apple Watch 地图服务",
                NotificationManager.IMPORTANCE_LOW
            )
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }

        val pendingIntentFlags = PendingIntent.FLAG_UPDATE_CURRENT or
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            pendingIntentFlags
        )
        val address = serviceUrl() ?: "等待网络地址"

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            Notification.Builder(this)
        }

        return builder
            .setContentTitle("Apple Watch 地图服务运行中")
            .setContentText(address)
            .setSmallIcon(android.R.drawable.ic_dialog_map)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .build()
    }

    private fun startHttpServer() {
        if (serverThread?.isAlive == true) {
            return
        }

        serverThread = Thread {
            runCatching {
                ServerSocket(PORT).use { socket ->
                    serverSocket = socket
                    while (!socket.isClosed) {
                        val client = socket.accept()
                        Thread {
                            handleClient(client)
                        }.start()
                    }
                }
            }
        }.apply {
            name = "NavigationHttpServer"
            isDaemon = true
            start()
        }
    }

    private fun registerBonjourService() {
        if (nsdRegistrationListener != null) {
            return
        }

        val manager = getSystemService(Context.NSD_SERVICE) as NsdManager
        val serviceInfo = NsdServiceInfo().apply {
            serviceName = SERVICE_NAME
            serviceType = SERVICE_TYPE
            port = PORT
        }

        val listener = object : NsdManager.RegistrationListener {
            override fun onServiceRegistered(serviceInfo: NsdServiceInfo) = Unit

            override fun onRegistrationFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {
                nsdRegistrationListener = null
            }

            override fun onServiceUnregistered(serviceInfo: NsdServiceInfo) = Unit

            override fun onUnregistrationFailed(serviceInfo: NsdServiceInfo, errorCode: Int) = Unit
        }

        nsdManager = manager
        nsdRegistrationListener = listener
        manager.registerService(serviceInfo, NsdManager.PROTOCOL_DNS_SD, listener)
    }

    private fun unregisterBonjourService() {
        val listener = nsdRegistrationListener ?: return
        runCatching {
            nsdManager?.unregisterService(listener)
        }
        nsdRegistrationListener = null
    }

    private fun handleClient(socket: Socket) {
        socket.use { client ->
            client.soTimeout = 3000
            val reader = BufferedReader(InputStreamReader(client.getInputStream(), Charsets.UTF_8))
            val requestLine = reader.readLine() ?: return
            while (true) {
                val line = reader.readLine() ?: break
                if (line.isEmpty()) {
                    break
                }
            }

            val path = requestLine.split(" ").getOrNull(1)?.substringBefore("?") ?: "/"
            when (path) {
                "/health" -> sendJson(client, 200, "OK", """{"ok":true}""")
                "/latest" -> sendJson(client, 200, "OK", DestinationStore.latest(this))
                else -> sendJson(client, 404, "Not Found", """{"error":"not_found"}""")
            }
        }
    }

    private fun sendJson(socket: Socket, status: Int, statusText: String, body: String) {
        val bodyBytes = body.toByteArray(Charsets.UTF_8)
        val headers = buildString {
            append("HTTP/1.1 $status $statusText\r\n")
            append("Content-Type: application/json; charset=utf-8\r\n")
            append("Access-Control-Allow-Origin: *\r\n")
            append("Content-Length: ${bodyBytes.size}\r\n")
            append("Connection: close\r\n")
            append("\r\n")
        }.toByteArray(Charsets.UTF_8)

        socket.getOutputStream().use { output ->
            output.write(headers)
            output.write(bodyBytes)
            output.flush()
        }
    }

    companion object {
        const val PORT = 8765
        const val SERVICE_TYPE = "_applewatchmaps._tcp."
        private const val CHANNEL_ID = "navigation_http_service"
        private const val NOTIFICATION_ID = 8765
        private const val SERVICE_NAME = "AppleWatchMaps Android"

        fun serviceUrl(): String? {
            val ip = NetworkUtils.localIPv4Address() ?: return null
            return "http://$ip:$PORT/latest"
        }
    }
}

object DestinationStore {
    private const val PREFERENCES = "share_to_watch"
    private const val LATEST_DESTINATION = "latest_destination_json"

    fun save(context: Context, destination: ParsedDestination): String {
        val payload = JSONObject().apply {
            put("target_name", destination.name)
            put("address", destination.address ?: "")
            put("source_name", "")
            put("source_lat", JSONObject.NULL)
            put("source_lng", JSONObject.NULL)
            destination.latitude?.let { put("destination_lat", it) } ?: put("destination_lat", JSONObject.NULL)
            destination.longitude?.let { put("destination_lng", it) } ?: put("destination_lng", JSONObject.NULL)
            put("coord_source", destination.coordinateSource ?: "")
            put("coord_type", destination.coordinateType ?: "")
            put("share_url", destination.shareUrl ?: "")
            put("updated_at", utcNow())
        }.toString()

        context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            .edit()
            .putString(LATEST_DESTINATION, payload)
            .apply()

        return payload
    }

    fun latest(context: Context): String {
        return context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            .getString(LATEST_DESTINATION, null)
            ?: defaultPayload()
    }

    private fun defaultPayload(): String {
        return JSONObject().apply {
            put("target_name", "未设置目的地")
            put("address", "")
            put("source_name", "")
            put("source_lat", JSONObject.NULL)
            put("source_lng", JSONObject.NULL)
            put("destination_lat", JSONObject.NULL)
            put("destination_lng", JSONObject.NULL)
            put("coord_source", "")
            put("coord_type", "")
            put("share_url", "")
            put("updated_at", utcNow())
        }.toString()
    }

    private fun utcNow(): String {
        return SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US).apply {
            timeZone = TimeZone.getTimeZone("UTC")
        }.format(Date())
    }
}

data class ParsedDestination(
    val name: String,
    val address: String? = null,
    val latitude: Double? = null,
    val longitude: Double? = null,
    val coordinateSource: String? = null,
    val coordinateType: String? = null,
    val shareUrl: String? = null
)

object DestinationParser {
    private val positionPattern = Regex("""(?:position|location)=(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)""")
    private val namePattern = Regex("""(?:name|poiname|keywords)=([^&\s]+)""")
    private val hereIsPattern = Regex("""^这里是(.+?)[：:](.+)$""")
    private val urlPattern = Regex("""https?://[^\s，。；、]+""")
    private val googleAtCoordinatePattern = Regex("""@(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?),""")
    private val googleBangCoordinatePattern = Regex("""!3d(-?\d+(?:\.\d+)?)!4d(-?\d+(?:\.\d+)?)""")
    private val googleQueryCoordinatePattern = Regex("""[?&](?:q|query|destination)=(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)""")

    fun parse(rawText: String): ParsedDestination {
        val decoded = decode(rawText).replace("\r", "\n")
        val amapPlace = parseAmapPlace(decoded)
        val coordinate = amapPlace?.coordinate ?: parseAmapCoordinate(decoded)
        val namedAddress = parseChineseSharedPlace(decoded)
        val name = amapPlace?.name ?: namedAddress?.first ?: parseName(decoded)
        val address = amapPlace?.address ?: namedAddress?.second

        return ParsedDestination(
            name = name,
            address = address,
            latitude = coordinate?.first,
            longitude = coordinate?.second,
            coordinateSource = when {
                amapPlace?.coordinate != null -> "amap_share"
                coordinate != null -> "share_text"
                else -> null
            },
            coordinateType = when {
                amapPlace?.coordinate != null -> "gcj02"
                coordinate != null -> "unknown"
                else -> null
            },
            shareUrl = parseShareUrl(decoded)
        )
    }

    fun resolveAmapShortLink(destination: ParsedDestination): ParsedDestination {
        val shareUrl = destination.shareUrl ?: return destination
        if (!shareUrl.contains("amap.com", ignoreCase = true)) {
            return destination
        }

        var currentUrl = shareUrl
        repeat(6) {
            val connection = runCatching {
                (URL(currentUrl).openConnection() as HttpURLConnection).apply {
                    instanceFollowRedirects = false
                    connectTimeout = 5000
                    readTimeout = 5000
                    requestMethod = "GET"
                    setRequestProperty("User-Agent", "Mozilla/5.0")
                }
            }.getOrNull() ?: return destination

            val location = runCatching {
                connection.responseCode
                connection.getHeaderField("Location")
            }.getOrNull()
            connection.disconnect()

            if (!location.isNullOrBlank()) {
                parseAmapPlace(decode(location))?.let { amapPlace ->
                    val coordinate = amapPlace.coordinate
                    if (coordinate != null) {
                        return destination.copy(
                            name = amapPlace.name ?: destination.name,
                            address = amapPlace.address ?: destination.address,
                            latitude = coordinate.first,
                            longitude = coordinate.second,
                            coordinateSource = "amap_redirect",
                            coordinateType = "gcj02"
                        )
                    }
                }

                currentUrl = runCatching {
                    URL(URL(currentUrl), location).toString()
                }.getOrDefault(location)
            } else {
                return destination
            }
        }

        return destination
    }

    fun resolveGoogleMapsLink(destination: ParsedDestination): ParsedDestination {
        val shareUrl = destination.shareUrl ?: return destination
        if (!isGoogleMapsUrl(shareUrl)) {
            return destination
        }

        var resolvedDestination = parseGoogleMapsPlace(shareUrl)?.mergeInto(destination) ?: destination
        var currentUrl = shareUrl

        repeat(8) {
            val connection = runCatching {
                (URL(currentUrl).openConnection() as HttpURLConnection).apply {
                    instanceFollowRedirects = false
                    connectTimeout = 5000
                    readTimeout = 5000
                    requestMethod = "GET"
                    setRequestProperty("User-Agent", "Mozilla/5.0")
                }
            }.getOrNull() ?: return resolvedDestination

            val location = runCatching {
                connection.responseCode
                connection.getHeaderField("Location")
            }.getOrNull()
            connection.disconnect()

            if (location.isNullOrBlank()) {
                return resolvedDestination
            }

            val nextUrl = runCatching {
                URL(URL(currentUrl), location).toString()
            }.getOrDefault(location)

            parseGoogleMapsPlace(nextUrl)?.let { place ->
                resolvedDestination = place.mergeInto(resolvedDestination)
                if (resolvedDestination.latitude != null && resolvedDestination.longitude != null) {
                    return resolvedDestination
                }
            }

            currentUrl = nextUrl
        }

        return resolvedDestination
    }

    private fun parseAmapCoordinate(text: String): Pair<Double, Double>? {
        val match = positionPattern.find(text) ?: return null
        val first = match.groupValues[1].toDoubleOrNull() ?: return null
        val second = match.groupValues[2].toDoubleOrNull() ?: return null

        return normalizeCoordinate(first, second)
    }

    private fun parseAmapPlace(text: String): AmapPlace? {
        val decoded = decode(text)
        val query = Regex("""[?&]p=([^&#\s]+)""").find(decoded)?.groupValues?.getOrNull(1)
            ?: return null
        val parts = query.split(",").map { decode(it).trim() }

        if (parts.size < 3) {
            return null
        }

        val latitude = parts.getOrNull(1)?.toDoubleOrNull() ?: return null
        val longitude = parts.getOrNull(2)?.toDoubleOrNull() ?: return null

        return AmapPlace(
            coordinate = normalizeCoordinate(latitude, longitude),
            name = parts.getOrNull(3)?.takeIf { it.isNotBlank() },
            address = parts.getOrNull(4)?.takeIf { it.isNotBlank() }
        )
    }

    private fun parseGoogleMapsPlace(text: String): GoogleMapsPlace? {
        val decoded = decode(text).replace("+", " ")
        val coordinate = parseGoogleCoordinate(decoded)
        val placeText = parseGooglePlaceText(decoded)

        if (coordinate == null && placeText.isNullOrBlank()) {
            return null
        }

        return GoogleMapsPlace(
            coordinate = coordinate,
            name = placeText,
            address = placeText
        )
    }

    private fun parseGoogleCoordinate(text: String): Pair<Double, Double>? {
        listOf(
            googleAtCoordinatePattern,
            googleBangCoordinatePattern,
            googleQueryCoordinatePattern
        ).forEach { pattern ->
            val match = pattern.find(text) ?: return@forEach
            val first = match.groupValues[1].toDoubleOrNull() ?: return@forEach
            val second = match.groupValues[2].toDoubleOrNull() ?: return@forEach
            return normalizeCoordinate(first, second)
        }

        return null
    }

    private fun parseGooglePlaceText(text: String): String? {
        val placeSegment = Regex("""/maps/place/([^/?#]+)""")
            .find(text)
            ?.groupValues
            ?.getOrNull(1)
            ?: return null

        return decode(placeSegment)
            .replace("+", " ")
            .replace(Regex("""\s+"""), " ")
            .replace(Regex("""\s*邮政编码[:：]?\s*\d+"""), "")
            .trim()
            .takeIf { it.isNotBlank() }
    }

    private fun normalizeCoordinate(first: Double, second: Double): Pair<Double, Double> {
        return if (first > 70 && second in -90.0..90.0) {
            second to first
        } else {
            first to second
        }
    }

    private fun parseName(text: String): String {
        namePattern.find(text)?.groupValues?.getOrNull(1)?.let { encodedName ->
            decode(encodedName).trim().takeIf { it.isNotBlank() }?.let { return it }
        }

        parseChineseSharedPlace(text)?.first?.let { return it }

        val candidates = cleanedLines(text)

        return candidates.firstOrNull()
            ?: urlPattern.replace(text, "").take(80).trim().ifBlank { "未命名地点" }
    }

    private fun parseChineseSharedPlace(text: String): Pair<String, String?>? {
        cleanedLines(text).forEach { line ->
            val match = hereIsPattern.find(line) ?: return@forEach
            val name = match.groupValues[1].trim()
            val address = match.groupValues[2].trim().ifBlank { null }

            if (name.isNotBlank()) {
                return name to address
            }
        }

        return null
    }

    private fun cleanedLines(text: String): List<String> {
        return text
            .lineSequence()
            .map { line ->
                line
                    .replace("#百度地图#", "")
                    .replace("#高德地图#", "")
                    .replace("#Google地图#", "")
                    .replace("#Google Maps#", "")
                    .replace("查看详情>>", "")
                    .let { urlPattern.replace(it, "") }
                    .trim()
            }
            .filter { it.isNotBlank() }
            .filterNot { it.startsWith("http://") || it.startsWith("https://") }
            .filterNot { it.contains("amap.com") || it.contains("map.baidu.com") || isGoogleMapsUrl(it) }
            .filterNot { it == "百度地图" || it == "高德地图" || it == "Google地图" || it == "Google Maps" }
            .toList()
    }

    private fun decode(value: String): String {
        return runCatching {
            URLDecoder.decode(value, "UTF-8")
        }.getOrDefault(value)
    }

    private fun parseShareUrl(text: String): String? {
        return urlPattern.find(text)?.value?.trim()
    }

    private fun isGoogleMapsUrl(value: String): Boolean {
        return value.contains("maps.app.goo.gl", ignoreCase = true) ||
            value.contains("google.com/maps", ignoreCase = true) ||
            value.contains("goo.gl/maps", ignoreCase = true)
    }

    private data class AmapPlace(
        val coordinate: Pair<Double, Double>?,
        val name: String?,
        val address: String?
    )

    private data class GoogleMapsPlace(
        val coordinate: Pair<Double, Double>?,
        val name: String?,
        val address: String?
    ) {
        fun mergeInto(destination: ParsedDestination): ParsedDestination {
            return destination.copy(
                name = name?.takeIf { it.isNotBlank() && destination.name == "未命名地点" }
                    ?: destination.name,
                address = address?.takeIf { it.isNotBlank() } ?: destination.address,
                latitude = coordinate?.first ?: destination.latitude,
                longitude = coordinate?.second ?: destination.longitude,
                coordinateSource = if (coordinate != null) "google_maps_link" else destination.coordinateSource,
                coordinateType = if (coordinate != null) "wgs84" else destination.coordinateType
            )
        }
    }
}

object NetworkUtils {
    fun localIPv4Address(): String? {
        return runCatching {
            val addresses = NetworkInterface.getNetworkInterfaces()
                ?.toList()
                .orEmpty()
                .filter { runCatching { it.isUp && !it.isLoopback }.getOrDefault(false) }
                .flatMap { networkInterface ->
                    networkInterface.inetAddresses.toList()
                        .filterIsInstance<Inet4Address>()
                        .filterNot { it.isLoopbackAddress }
                }

            addresses.firstOrNull { it.isSiteLocalAddress }?.hostAddress
                ?: addresses.firstOrNull()?.hostAddress
        }.getOrNull()
    }
}
