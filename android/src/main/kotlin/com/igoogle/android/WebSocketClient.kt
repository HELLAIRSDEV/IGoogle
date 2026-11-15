package com.igoogle.android

import android.util.Log
import com.igoogle.shared.DeviceInfo
import com.igoogle.shared.Message
import com.igoogle.shared.MessageType
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import okio.ByteString
import javax.net.SocketFactory

/** WebSocket-клиент до Mac (OkHttp). Mac при этом — сервер. */
class WebSocketClient(
    private val local: DeviceInfo,
    private val onMessage: (Message) -> Unit,
    private val onBinary: (ByteArray) -> Unit = {},
    private val onState: (Boolean) -> Unit,
    socketFactory: SocketFactory? = null,
) {
    private val client = OkHttpClient.Builder()
        .pingInterval(15, java.util.concurrent.TimeUnit.SECONDS) // «бесшовный режим»
        // Сокет, привязанный к Wi-Fi, идёт мимо VPN (обход TUN).
        .apply { if (socketFactory != null) socketFactory(socketFactory) }
        .build()
    private var ws: WebSocket? = null

    fun connect(host: String, port: Int) {
        val bareHost = host.substringBefore('%')
        val hostPart = if (bareHost.contains(':')) "[$bareHost]" else bareHost
        val url = try {
            "http://$hostPart:$port/igoogle".toHttpUrl()
        } catch (e: Exception) {
            Log.d(TAG, "bad url host=$host port=$port: ${e.message}")
            onState(false)
            return
        }
        Log.d(TAG, "connecting to $url")

        ws = client.newWebSocket(Request.Builder().url(url).build(), object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                Log.d(TAG, "ws open")
                onState(true)
                webSocket.send(Message(type = MessageType.HELLO, device = local).encode())
            }

            override fun onMessage(webSocket: WebSocket, text: String) {
                runCatching { onMessage(Message.decode(text)) }
            }

            override fun onMessage(webSocket: WebSocket, bytes: ByteString) {
                onBinary(bytes.toByteArray())
            }

            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                Log.d(TAG, "ws closed $code $reason")
                onState(false)
            }

            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                Log.d(TAG, "ws failure: ${t.javaClass.simpleName}: ${t.message}")
                onState(false)
            }
        })
    }

    fun send(message: Message) {
        ws?.send(message.encode())
    }

    fun sendBinary(data: ByteArray) {
        ws?.send(ByteString.of(*data))
    }

    fun close() {
        ws?.close(1000, "bye")
        ws = null
    }

    private companion object {
        const val TAG = "IGoogle"
    }
}
