package com.igoogle.android

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.os.Build
import android.util.Log
import java.net.Inet4Address
import java.net.InetAddress

/** Обнаружение Mac в локальной сети через NSD (Bonjour-сервис `_igoogle._tcp`). */
class NsdDiscovery(
    context: Context,
    private val onFound: (host: String, port: Int, name: String) -> Unit,
) {
    private val nsd = context.applicationContext.getSystemService(Context.NSD_SERVICE) as NsdManager
    private var listener: NsdManager.DiscoveryListener? = null

    fun start() {
        val discovery = object : NsdManager.DiscoveryListener {
            override fun onDiscoveryStarted(serviceType: String) {
                Log.d(TAG, "discovery started $serviceType")
            }

            override fun onDiscoveryStopped(serviceType: String) {
                Log.d(TAG, "discovery stopped")
            }

            override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) {
                Log.d(TAG, "start failed errorCode=$errorCode")
            }

            override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) {
                Log.d(TAG, "stop failed errorCode=$errorCode")
            }

            override fun onServiceLost(info: NsdServiceInfo) {
                Log.d(TAG, "service lost ${info.serviceName}")
            }

            override fun onServiceFound(info: NsdServiceInfo) {
                Log.d(TAG, "onServiceFound: ${info.serviceName}")
                runCatching {
                    nsd.resolveService(info, object : NsdManager.ResolveListener {
                        override fun onResolveFailed(info: NsdServiceInfo, errorCode: Int) {
                            Log.d(TAG, "onResolveFailed: errorCode=$errorCode")
                        }

                        override fun onServiceResolved(info: NsdServiceInfo) {
                            val host = pickHost(info)
                            Log.d(TAG, "resolved: host=$host port=${info.port}")
                            if (host != null) {
                                runCatching { onFound(host, info.port, info.serviceName) }
                            }
                        }
                    })
                }
            }
        }
        listener = discovery
        nsd.discoverServices("_igoogle._tcp", NsdManager.PROTOCOL_DNS_SD, discovery)
    }

    /** Предпочитаем IPv4: link-local IPv6 без zone id часто не маршрутизируется. */
    private fun pickHost(info: NsdServiceInfo): String? {
        val addresses: List<InetAddress> = try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                info.hostAddresses
            } else {
                @Suppress("DEPRECATION")
                listOfNotNull(info.host)
            }
        } catch (e: Exception) {
            @Suppress("DEPRECATION")
            listOfNotNull(info.host)
        }
        val ipv4 = addresses.firstOrNull { it is Inet4Address }
        return (ipv4 ?: addresses.firstOrNull())?.hostAddress
    }

    fun stop() {
        listener?.let { runCatching { nsd.stopServiceDiscovery(it) } }
        listener = null
    }

    private companion object {
        const val TAG = "IGoogle"
    }
}
