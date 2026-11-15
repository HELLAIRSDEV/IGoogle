package com.igoogle.android

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.os.Handler
import android.os.Looper

/**
 * Следит за системным буфером обмена Android.
 * Аналог `ClipboardMonitor` на Mac.
 */
class ClipboardSync(context: Context, private val onLocalChange: (String) -> Unit) {
    private val appContext = context.applicationContext
    private val cm = appContext.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
    private val main = Handler(Looper.getMainLooper())
    private var suppress = false

    private val listener = ClipboardManager.OnPrimaryClipChangedListener {
        if (suppress) {
            suppress = false
            return@OnPrimaryClipChangedListener
        }
        read()?.let(onLocalChange)
    }

    fun start() = cm.addPrimaryClipChangedListener(listener)

    fun stop() = cm.removePrimaryClipChangedListener(listener)

    fun read(): String? =
        cm.primaryClip?.takeIf { it.itemCount > 0 }
            ?.getItemAt(0)
            ?.coerceToText(appContext)
            ?.toString()

    fun write(text: String) {
        suppress = true
        cm.setPrimaryClip(ClipData.newPlainText("IGoogle", text))
    }
}
