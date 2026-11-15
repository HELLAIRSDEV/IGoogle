package com.igoogle.android

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.provider.Settings
import com.igoogle.shared.ClipboardPayload
import com.igoogle.shared.DeviceInfo
import com.igoogle.shared.FileMetaPayload
import com.igoogle.shared.Message
import com.igoogle.shared.MessageType
import com.igoogle.shared.Platform
import com.igoogle.shared.TransferCallbacks
import com.igoogle.shared.TransferEngine
import com.igoogle.shared.deviceDisplayName
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import javax.net.SocketFactory

data class UiState(
    val connected: Boolean = false,
    val macName: String? = null,
    val lastClipboard: String? = null,
)

/** Android-аналог `IGoogleHub` на Mac: связывает NSD, WebSocket и буфер обмена. */
class IGoogleController(context: Context) {
    private val app = context.applicationContext
    private val prefs = app.getSharedPreferences("igoogle", Context.MODE_PRIVATE)
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    val local: DeviceInfo = DeviceInfo(
        id = "android-" + Settings.Secure.getString(app.contentResolver, Settings.Secure.ANDROID_ID),
        name = deviceDisplayName(),
        platform = Platform.ANDROID,
    )

    private val _state = MutableStateFlow(UiState())
    val state: StateFlow<UiState> = _state

    private var lastHost: String? = prefs.getString("lastHost", null)
    private var lastPort: Int = prefs.getInt("lastPort", 0)
    private var macName: String? = prefs.getString("lastName", null)
    private var connectingHost: String? = null
    private var connectingPort: Int = 0
    private var started = false

    private val engine: TransferEngine = TransferEngine(local, object : TransferCallbacks {
        override fun onRemoteClipboard(text: String, from: DeviceInfo?) {
            clipboard.write(text)
            MacLink.lastClipboard = text
            _state.value = _state.value.copy(lastClipboard = text)
        }

        override fun onIncomingFile(meta: FileMetaPayload) {
            prepareIncomingFile(meta)
        }
    })

    private val clipboard: ClipboardSync = ClipboardSync(app) { text ->
        MacLink.lastClipboard = text
        engine.onLocalClipboardChanged(text) { msg -> wsClient?.send(msg) }
    }

    private var wsClient: WebSocketClient? = null
    private val incomingFiles = mutableMapOf<String, FileAssembly>()
    private val discovery = NsdDiscovery(app) { host, port, name ->
        scope.launch { connect(host, port, name) }
    }

    fun start() {
        if (started) return
        started = true
        MacLink.local = local
        clipboard.start()
        discovery.start()
        // Fallback: если NSD не нашёл (например, из-за VPN) — пробуем последний адрес.
        scope.launch {
            delay(4000)
            if (!_state.value.connected) {
                val h = lastHost
                val p = lastPort
                if (h != null && p != 0) connect(h, p, macName ?: "MacBook")
            }
        }
    }

    fun stop() {
        started = false
        clipboard.stop()
        discovery.stop()
        wsClient?.close()
        wsClient = null
        MacLink.client = null
    }

    private fun connect(host: String, port: Int, name: String) {
        if (_state.value.connected && host == lastHost && port == lastPort) return
        if (connectingHost == host && connectingPort == port) return
        connectingHost = host
        connectingPort = port
        wsClient?.close()
        wsClient = WebSocketClient(
            local = local,
            onMessage = { msg -> engine.onIncoming(msg) },
            onBinary = { data -> handleBinary(data) },
            onState = { up ->
                connectingHost = null
                connectingPort = 0
                _state.value = _state.value.copy(
                    connected = up,
                    macName = if (up) name else _state.value.macName,
                )
                MacLink.client = if (up) wsClient else null
                if (up) {
                    lastHost = host
                    lastPort = port
                    macName = name
                    prefs.edit()
                        .putString("lastHost", host)
                        .putInt("lastPort", port)
                        .putString("lastName", name)
                        .apply()
                    NotificationHelper.showConnected(app, name)
                } else {
                    NotificationHelper.clear(app)
                    scheduleReconnect()
                }
            },
            socketFactory = wifiSocketFactory(),
        )
        wsClient?.connect(host, port)
    }

    private fun scheduleReconnect() {
        val host = lastHost ?: return
        val port = lastPort
        if (port == 0) return
        scope.launch {
            delay(2500)
            if (!_state.value.connected) connect(host, port, macName ?: "MacBook")
        }
    }

    /** Сокет, привязанный к Wi-Fi (обход VPN TUN), с безопасным fallback. */
    private fun wifiSocketFactory(): SocketFactory? = try {
        val cm = app.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val wifi = cm.allNetworks.firstOrNull { network ->
            cm.getNetworkCapabilities(network)?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true
        }
        wifi?.let { WifiBindSocketFactory(it) }
    } catch (e: Exception) {
        null
    }

    private fun prepareIncomingFile(meta: FileMetaPayload) {
        val sink = openIncomingSink(app, meta.name, meta.mime)
        if (sink == null) {
            _state.value = _state.value.copy(lastClipboard = "⚠️ Не удалось принять ${meta.name}")
            return
        }
        incomingFiles[meta.id] = FileAssembly(meta.name, meta.size, sink.stream, sink.onComplete)
        _state.value = _state.value.copy(lastClipboard = "📥 Получение: ${meta.name}")
        wsClient?.send(Message(type = MessageType.ACK, device = local, file = meta))
    }

    private fun handleBinary(data: ByteArray) {
        val chunk = decodeChunk(data) ?: return
        val asm = incomingFiles[chunk.id.toString()] ?: return
        asm.write(chunk.data)
        if (asm.isComplete) {
            incomingFiles.remove(chunk.id.toString())
            asm.close()
            _state.value = _state.value.copy(lastClipboard = "📁 ${asm.name}")
        }
    }

    /** Отправить текущий буфер на Mac вручную (кнопка/свайп). */
    fun pushCurrentClipboard() {
        clipboard.read()?.let { text ->
            MacLink.lastClipboard = text
            engine.onLocalClipboardChanged(text) { msg -> wsClient?.send(msg) }
        }
    }

    /** Перезапустить поиск Mac (команда «Найти заново»). */
    fun refreshDiscovery() {
        discovery.stop()
        discovery.start()
    }

    companion object {
        @Volatile
        private var instance: IGoogleController? = null

        /** Синглтон: общий между Activity и foreground-service. */
        fun get(context: Context): IGoogleController =
            instance ?: synchronized(this) {
                instance ?: IGoogleController(context.applicationContext).also { instance = it }
            }

        fun clipboardMessage(text: String): Message =
            Message(type = MessageType.CLIPBOARD, clipboard = ClipboardPayload(text = text))
    }
}
