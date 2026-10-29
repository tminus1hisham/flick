package dev.local.flick

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import java.io.File

/**
 * Keeps the process in the foreground while downloads run, so they continue with the app backgrounded or the
 * screen off. It holds no state: Torrents starts and stops it and refreshes its notification.
 */
class DownloadService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val n = notification(this, intent?.getIntExtra("count", 1) ?: 1, intent?.getIntExtra("percent", 0) ?: 0)
        if (Build.VERSION.SDK_INT >= 29) startForeground(ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        else startForeground(ID, n)
        // Without the engine there is no torrent session to keep alive.
        return START_NOT_STICKY
    }

    // Android 15 caps dataSync services at 6 hours a day and crashes the app if one keeps running past it.
    override fun onTimeout(startId: Int, fgsType: Int) = stopSelf()

    companion object {
        private const val ID = 1
        private const val CHANNEL = "downloads"

        fun show(context: Context, count: Int, percent: Int) =
            context.getSystemService(NotificationManager::class.java).notify(ID, notification(context, count, percent))

        private fun notification(context: Context, count: Int, percent: Int): Notification {
            val b = if (Build.VERSION.SDK_INT >= 26) {
                context.getSystemService(NotificationManager::class.java).createNotificationChannel(
                    NotificationChannel(CHANNEL, "Downloads", NotificationManager.IMPORTANCE_LOW))
                Notification.Builder(context, CHANNEL)
            } else {
                @Suppress("DEPRECATION") Notification.Builder(context)
            }
            val open = context.packageManager.getLaunchIntentForPackage(context.packageName)
            return b.setSmallIcon(android.R.drawable.stat_sys_download)
                .setContentTitle("Downloading $count")
                .setContentText("$percent%")
                .setProgress(100, percent, false)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setContentIntent(open?.let { PendingIntent.getActivity(context, 0, it, PendingIntent.FLAG_IMMUTABLE) })
                .build()
        }
    }
}

/** Streaming session directories in [root] other than [live], which may sit anywhere (a download, say). */
fun leftovers(root: File, live: File): List<File> =
    root.listFiles()?.filter { it.canonicalPath != live.canonicalPath }.orEmpty()

/** Whether [dir] is strictly inside [root]; "downloads2" is not inside "downloads". */
fun isUnder(dir: File, root: File): Boolean = dir.canonicalPath.startsWith(root.canonicalPath + File.separator)
