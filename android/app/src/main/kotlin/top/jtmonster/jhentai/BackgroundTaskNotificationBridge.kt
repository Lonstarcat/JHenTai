package top.jtmonster.jhentai

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel

/** Keeps notification actions independent from the Activity lifecycle. */
object BackgroundTaskNotificationBridge {
    private var channel: MethodChannel? = null
    private var pendingToggle = false

    fun attach(methodChannel: MethodChannel) {
        channel = methodChannel
        if (pendingToggle) {
            pendingToggle = false
            sendToggle()
        }
    }

    fun detach(methodChannel: MethodChannel) {
        if (channel === methodChannel) {
            channel = null
        }
    }

    fun sendToggle() {
        val currentChannel = channel
        if (currentChannel == null) {
            pendingToggle = true
            return
        }
        Handler(Looper.getMainLooper()).post {
            currentChannel.invokeMethod("togglePause", null)
        }
    }
}
