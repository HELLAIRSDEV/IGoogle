package com.igoogle.shared

/** Текущее время в секундах с эпохи Unix (для меток сообщений). */
expect fun currentTimestampSeconds(): Double

/** Человекочитаемое имя устройства (например, «Pixel 8»). */
expect fun deviceDisplayName(): String
