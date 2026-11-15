package com.igoogle.shared

import platform.Foundation.NSDate
import platform.Foundation.timeIntervalSince1970

actual fun currentTimestampSeconds(): Double = NSDate().timeIntervalSince1970

actual fun deviceDisplayName(): String = "Mac"
