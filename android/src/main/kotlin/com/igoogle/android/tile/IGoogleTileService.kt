package com.igoogle.android.tile

import android.content.ClipboardManager
import android.content.Context
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import android.widget.Toast
import com.igoogle.android.MacLink
import com.igoogle.shared.ClipboardPayload
import com.igoogle.shared.Message
import com.igoogle.shared.MessageType

/**
 * Плитка IGoogle в шторке. Тап — отправить последний известный буфер на Mac.
 * Долгое нажатие — открыть приложение.
 */
class IGoogleTileService : TileService() {

    override fun onStartListening() {
        super.onStartListening()
        updateTile()
    }

    private fun updateTile() {
        val tile = qsTile ?: return
        val connected = MacLink.client != null
        tile.state = if (connected) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            tile.label = if (connected) "IGoogle ✓" else "IGoogle"
        }
        tile.updateTile()
    }

    override fun onClick() {
        super.onClick()
        val client = MacLink.client
        if (client == null) {
            Toast.makeText(this, "Откройте IGoogle и подключитесь к Mac", Toast.LENGTH_SHORT).show()
            updateTile()
            return
        }

        // Пробуем текущий буфер; если система не отдала (фон) — кэш последнего.
        val text = readClipboard() ?: MacLink.lastClipboard
        if (text != null) {
            client.send(Message(
                type = MessageType.CLIPBOARD,
                device = MacLink.local,
                clipboard = ClipboardPayload(text = text),
            ))
            Toast.makeText(this, "Буфер отправлен на MacBook", Toast.LENGTH_SHORT).show()
        } else {
            Toast.makeText(this, "Скопируйте текст и нажмите снова", Toast.LENGTH_SHORT).show()
        }
        updateTile()
    }

    private fun readClipboard(): String? = runCatching {
        val cm = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        cm.primaryClip?.takeIf { it.itemCount > 0 }
            ?.getItemAt(0)?.coerceToText(this)?.toString()
    }.getOrNull()
}
