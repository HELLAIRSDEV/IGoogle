package com.igoogle.shared

import android.os.Build

actual fun currentTimestampSeconds(): Double = System.currentTimeMillis() / 1000.0

actual fun deviceDisplayName(): String = Build.MODEL ?: "Android"
