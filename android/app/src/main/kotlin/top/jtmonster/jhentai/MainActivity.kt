package top.jtmonster.jhentai

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.KeyEvent
import androidx.core.view.WindowCompat
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.EventChannel.EventSink
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.GeneratedPluginRegistrant

class MainActivity : FlutterFragmentActivity() {
    private var interceptVolumeEvent = false
    private lateinit var volumeMethodChannel: MethodChannel
    private lateinit var backgroundTaskMethodChannel: MethodChannel
    private lateinit var backgroundTaskNotificationManager: BackgroundTaskNotificationManager
    private var pendingNotificationOpen: Map<String, Any>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        GeneratedPluginRegistrant.registerWith(flutterEngine)

        volumeMethodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "top.jtmonster.jhentai.volume.event.intercept"
        )

        volumeMethodChannel.setMethodCallHandler { call, result ->
            if (call.method == "set") {
                val value = call.arguments<Boolean>()
                if (value != null) {
                    interceptVolumeEvent = value
                }
                result.success(null)
            } else {
                result.notImplemented()
            }
        }

        backgroundTaskNotificationManager = BackgroundTaskNotificationManager(applicationContext)
        backgroundTaskMethodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "top.jtmonster.jhentai.background_tasks"
        )
        BackgroundTaskNotificationBridge.attach(backgroundTaskMethodChannel)
        backgroundTaskMethodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "show" -> {
                    @Suppress("UNCHECKED_CAST")
                    result.success(backgroundTaskNotificationManager.show(call.arguments as? Map<*, *> ?: emptyMap<String, Any>()))
                }
                "cancel" -> {
                    backgroundTaskNotificationManager.cancel()
                    result.success(null)
                }
                "requestPermission" -> {
                    result.success(requestNotificationPermissionIfNeeded())
                }
                "getInitialAction" -> {
                    val action = pendingNotificationOpen ?: notificationActionFromIntent(intent)
                    pendingNotificationOpen = null
                    result.success(action)
                }
                else -> result.notImplemented()
            }
        }
        pendingNotificationOpen = notificationActionFromIntent(intent)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        WindowCompat.setDecorFitsSystemWindows(getWindow(), false)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            // Disable the Android splash screen fade out animation to avoid
            // a flicker before the similar frame is drawn in Flutter.
            splashScreen.setOnExitAnimationListener { splashScreenView -> splashScreenView.remove() }
        }

        super.onCreate(savedInstanceState)
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        if (interceptVolumeEvent && (keyCode == KeyEvent.KEYCODE_VOLUME_UP || keyCode == KeyEvent.KEYCODE_VOLUME_DOWN)) {
            volumeMethodChannel.invokeMethod(
                "event",
                if (keyCode == KeyEvent.KEYCODE_VOLUME_UP) 1 else -1
            )
            return true
        }
        return super.onKeyDown(keyCode, event)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val action = notificationActionFromIntent(intent) ?: return
        if (::backgroundTaskMethodChannel.isInitialized) {
            backgroundTaskMethodChannel.invokeMethod("openTask", action)
        } else {
            pendingNotificationOpen = action
        }
    }

    private fun notificationActionFromIntent(intent: Intent?): Map<String, Any>? {
        if (intent?.getBooleanExtra(BackgroundTaskNotificationManager.EXTRA_OPEN_TASK, false) != true) return null
        intent.removeExtra(BackgroundTaskNotificationManager.EXTRA_OPEN_TASK)
        return mapOf(
            "taskType" to (intent.getStringExtra(BackgroundTaskNotificationManager.EXTRA_TASK_TYPE) ?: "download"),
        )
    }

    private fun requestNotificationPermissionIfNeeded(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return true
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) return true
        ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.POST_NOTIFICATIONS), 328)
        return false
    }

    override fun onKeyUp(keyCode: Int, event: KeyEvent?): Boolean {
        if (interceptVolumeEvent && (keyCode == KeyEvent.KEYCODE_VOLUME_UP || keyCode == KeyEvent.KEYCODE_VOLUME_DOWN)) {
            return true
        }
        return super.onKeyUp(keyCode, event)
    }

    override fun onDestroy() {
        volumeMethodChannel.setMethodCallHandler(null)
        if (::backgroundTaskMethodChannel.isInitialized) {
            BackgroundTaskNotificationBridge.detach(backgroundTaskMethodChannel)
            backgroundTaskMethodChannel.setMethodCallHandler(null)
        }
        super.onDestroy()
    }
}
