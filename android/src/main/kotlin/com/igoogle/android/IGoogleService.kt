package com.igoogle.android

import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

/**
 * Foreground-service: держит соединение с Mac живым в фоне (даже когда приложение
 * закрыто/свёрнуто), с постоянным уведомлением и действием «Отправить буфер».
 */
class IGoogleService : Service() {
    private lateinit var controller: IGoogleController

    override fun onCreate() {
        super.onCreate()
        controller = IGoogleController.get(this)

        val notification = NotificationHelper.build(this, "Подключение к Mac…")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NotificationHelper.NOTIF_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
            )
        } else {
            startForeground(NotificationHelper.NOTIF_ID, notification)
        }

        controller.start()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        controller.start()
        return START_STICKY
    }

    override fun onDestroy() {
        controller.stop()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
