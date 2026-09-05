package top.jtmonster.jhentai

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class BackgroundTaskActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == BackgroundTaskNotificationManager.ACTION_TOGGLE_PAUSE) {
            BackgroundTaskNotificationBridge.sendToggle()
        }
    }
}
