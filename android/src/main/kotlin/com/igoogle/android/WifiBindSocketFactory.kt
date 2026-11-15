package com.igoogle.android

import android.net.Network
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.Socket
import javax.net.SocketFactory

/**
 * Сокет-фабрика, которая пытается привязать сокет к Wi-Fi (обход VPN TUN),
 * но при отказе (EPERM и т.п.) молча отдаёт обычный сокет — соединение не падает.
 */
class WifiBindSocketFactory(private val network: Network) : SocketFactory() {

    private fun boundSocket(): Socket {
        val socket = Socket()
        runCatching { network.bindSocket(socket) } // если нельзя — оставляем непривязанным
        return socket
    }

    override fun createSocket(): Socket = boundSocket()

    override fun createSocket(host: String, port: Int): Socket =
        boundSocket().apply { connect(InetSocketAddress(host, port)) }

    override fun createSocket(host: String, port: Int, localHost: InetAddress, localPort: Int): Socket =
        boundSocket().apply {
            bind(InetSocketAddress(localHost, localPort))
            connect(InetSocketAddress(host, port))
        }

    override fun createSocket(address: InetAddress, port: Int): Socket =
        boundSocket().apply { connect(InetSocketAddress(address, port)) }

    override fun createSocket(
        address: InetAddress,
        port: Int,
        localAddress: InetAddress,
        localPort: Int,
    ): Socket = boundSocket().apply {
        bind(InetSocketAddress(localAddress, localPort))
        connect(InetSocketAddress(address, port))
    }
}
