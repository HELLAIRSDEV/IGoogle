package com.igoogle.android

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.material3.MaterialTheme
import com.igoogle.android.ui.IGoogleScreen

class MainActivity : ComponentActivity() {
    private lateinit var controller: IGoogleController

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        controller = IGoogleController.get(this)

        // Держим соединение в фоне через foreground-service.
        val serviceIntent = Intent(this, IGoogleService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(serviceIntent)
        } else {
            startService(serviceIntent)
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1)
        }

        setContent {
            MaterialTheme {
                IGoogleScreen(controller)
            }
        }
    }

    // Соединение живёт в сервисе — не останавливаем при закрытии активити.
    override fun onDestroy() {
        super.onDestroy()
    }
}
