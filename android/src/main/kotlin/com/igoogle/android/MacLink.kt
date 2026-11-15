package com.igoogle.android

import com.igoogle.shared.DeviceInfo

/**
 * Общее состояние для системных расширений (share, «поделиться текстом», плитка).
 * Живёт, пока жив процесс приложения.
 */
object MacLink {
    var client: WebSocketClient? = null
    var local: DeviceInfo? = null
    var lastClipboard: String? = null
}
