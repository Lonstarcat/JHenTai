package top.jtmonster.jhentai

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.view.View
import android.widget.RemoteViews
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat

class BackgroundTaskNotificationManager(private val context: Context) {
    companion object {
        const val CHANNEL_ID = "jhentai_background_tasks"
        const val NOTIFICATION_ID = 328
        const val ACTION_TOGGLE_PAUSE = "top.jtmonster.jhentai.action.TOGGLE_BACKGROUND_TASKS"
        const val EXTRA_OPEN_TASK = "jhentai_open_background_task"
        const val EXTRA_TASK_TYPE = "jhentai_task_type"
    }

    init {
        createChannel()
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(
            CHANNEL_ID,
            "JHenTai background tasks",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Download, archive download and favorite progress"
            setSound(null, null)
            enableVibration(false)
            setShowBadge(false)
        }
        manager.createNotificationChannel(channel)
    }

    fun notificationsEnabled(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            return false
        }
        return NotificationManagerCompat.from(context).areNotificationsEnabled()
    }

    fun show(args: Map<*, *>): Boolean {
        if (!notificationsEnabled()) return false

        val title = args["title"] as? String ?: "JHenTai"
        val content = args["content"] as? String ?: ""
        val lines = (args["lines"] as? List<*>)?.mapNotNull { it as? String } ?: emptyList()
        val primaryTitle = args["primaryTitle"] as? String ?: content
        val primaryDetail = args["primaryDetail"] as? String ?: content
        val speedText = args["speedText"] as? String ?: ""
        val progress = (args["progress"] as? Number)?.toInt()?.coerceAtLeast(0) ?: 0
        val max = (args["max"] as? Number)?.toInt()?.coerceAtLeast(0) ?: 0
        val indeterminate = args["indeterminate"] as? Boolean ?: (max <= 0)
        val ongoing = args["ongoing"] as? Boolean ?: true
        val paused = args["paused"] as? Boolean ?: false
        val showAction = args["showAction"] as? Boolean ?: true
        val pauseLabel = args["pauseLabel"] as? String ?: "Pause"
        val resumeLabel = args["resumeLabel"] as? String ?: "Resume"
        val taskType = args["taskType"] as? String ?: "download"

        val openIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(EXTRA_OPEN_TASK, true)
            putExtra(EXTRA_TASK_TYPE, taskType)
        }
        val contentIntent = PendingIntent.getActivity(
            context,
            NOTIFICATION_ID,
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val builder = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentTitle(title)
            .setContentText(content)
            .setContentIntent(contentIntent)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOnlyAlertOnce(true)
            .setOngoing(ongoing)
            .setAutoCancel(!ongoing)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)

        val toggleIntent = Intent(context, BackgroundTaskActionReceiver::class.java).apply {
            action = ACTION_TOGGLE_PAUSE
        }
        val actionIntent = PendingIntent.getBroadcast(
            context,
            NOTIFICATION_ID + 1,
            toggleIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val actionLabel = if (paused) resumeLabel else pauseLabel
        val expandedView = createExpandedView(
            primaryTitle = primaryTitle,
            detail = primaryDetail,
            speed = speedText,
            lines = lines,
            max = max,
            progress = progress,
            indeterminate = indeterminate,
            showAction = showAction,
            actionLabel = actionLabel,
            contentIntent = contentIntent,
            actionIntent = actionIntent,
        )
        builder
            .setStyle(NotificationCompat.DecoratedCustomViewStyle())
            .setCustomBigContentView(expandedView)

        return try {
            NotificationManagerCompat.from(context).notify(NOTIFICATION_ID, builder.build())
            true
        } catch (_: RuntimeException) {
            showFallbackNotification(
                title = title,
                content = content,
                lines = lines,
                ongoing = ongoing,
                showAction = showAction,
                paused = paused,
                pauseLabel = pauseLabel,
                resumeLabel = resumeLabel,
                contentIntent = contentIntent,
                actionIntent = actionIntent,
            )
        }
    }

    fun cancel() {
        NotificationManagerCompat.from(context).cancel(NOTIFICATION_ID)
    }

    private fun createExpandedView(
        primaryTitle: String,
        detail: String,
        speed: String,
        lines: List<String>,
        max: Int,
        progress: Int,
        indeterminate: Boolean,
        showAction: Boolean,
        actionLabel: String,
        contentIntent: PendingIntent,
        actionIntent: PendingIntent,
    ): RemoteViews = RemoteViews(context.packageName, R.layout.notification_background_task_expanded).apply {
        setTextViewText(R.id.background_task_title, primaryTitle)
        setTextViewText(R.id.background_task_detail, detail)
        setTextViewText(R.id.background_task_speed, speed)
        setViewVisibility(R.id.background_task_speed, if (speed.isEmpty()) View.GONE else View.VISIBLE)
        setTextViewText(R.id.background_task_lines, lines.take(4).joinToString("\n"))
        setViewVisibility(R.id.background_task_lines, if (lines.size > 1) View.VISIBLE else View.GONE)
        setProgressBar(R.id.background_task_progress, max.coerceAtLeast(1), progress.coerceAtMost(max.coerceAtLeast(1)), indeterminate)
        setTextViewText(R.id.background_task_action, actionLabel)
        setViewVisibility(R.id.background_task_action, if (showAction) View.VISIBLE else View.GONE)
        setViewVisibility(R.id.background_task_action_divider, if (showAction) View.VISIBLE else View.GONE)
        setOnClickPendingIntent(R.id.background_task_content, contentIntent)
        if (showAction) {
            setOnClickPendingIntent(R.id.background_task_action, actionIntent)
        }
    }

    private fun showFallbackNotification(
        title: String,
        content: String,
        lines: List<String>,
        ongoing: Boolean,
        showAction: Boolean,
        paused: Boolean,
        pauseLabel: String,
        resumeLabel: String,
        contentIntent: PendingIntent,
        actionIntent: PendingIntent,
    ): Boolean {
        val fallback = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentTitle(title)
            .setContentText(content)
            .setContentIntent(contentIntent)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOnlyAlertOnce(true)
            .setOngoing(ongoing)
            .setAutoCancel(!ongoing)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)

        if (lines.isNotEmpty()) {
            val inboxStyle = NotificationCompat.InboxStyle()
            inboxStyle.setBigContentTitle(title)
            lines.take(6).forEach { inboxStyle.addLine(it) }
            fallback.setStyle(inboxStyle)
        }
        if (showAction) {
            fallback.addAction(
                if (paused) android.R.drawable.ic_media_play else android.R.drawable.ic_media_pause,
                if (paused) resumeLabel else pauseLabel,
                actionIntent,
            )
        }

        return try {
            NotificationManagerCompat.from(context).notify(NOTIFICATION_ID, fallback.build())
            true
        } catch (_: RuntimeException) {
            false
        }
    }
}
