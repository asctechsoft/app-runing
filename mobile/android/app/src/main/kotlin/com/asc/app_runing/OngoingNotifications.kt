package com.asc.app_runing

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.SystemClock
import android.widget.RemoteViews

/**
 * Hai thông báo đang chạy của STRIDE, dựng hoàn toàn ở native để vẫn hiển thị khi app ở nền:
 *  - số bước hôm nay (foreground service [OngoingService], mở app là hiện);
 *  - thẻ buổi chạy đang ghi (thời gian + quãng đường), nằm trên thông báo bước.
 * Mọi chữ do Dart truyền sang (đã dịch theo ngôn ngữ app); native không có chuỗi riêng.
 */
object OngoingNotifications {
    const val ID_STEPS = 7101
    const val ID_RUN = 7102
    private const val CH_STEPS = "stride_ongoing_steps"
    private const val CH_RUN = "stride_ongoing_run"

    private fun manager(ctx: Context) = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    private fun ensureChannel(ctx: Context, id: String, name: String, importance: Int) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(id, name, importance).apply {
            setSound(null, null)
            enableVibration(false)
            setShowBadge(false)
        }
        manager(ctx).createNotificationChannel(channel)
    }

    private fun builder(ctx: Context, channel: String): Notification.Builder =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) Notification.Builder(ctx, channel) else Notification.Builder(ctx)

    private fun openApp(ctx: Context): PendingIntent {
        val launch = ctx.packageManager.getLaunchIntentForPackage(ctx.packageName)
            ?.apply { flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED }
        return PendingIntent.getActivity(ctx, 0, launch, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }

    /** Số bước hôm nay; [progress] 0..100, null = chưa đặt mục tiêu (không vẽ thanh tiến độ). */
    fun steps(ctx: Context, channelName: String, title: String, text: String, progress: Int?): Notification {
        ensureChannel(ctx, CH_STEPS, channelName, NotificationManager.IMPORTANCE_LOW)
        return builder(ctx, CH_STEPS)
            .setSmallIcon(R.drawable.ic_stat_stride)
            .setContentTitle(title)
            .setContentText(text)
            .setContentIntent(openApp(ctx))
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setCategory(Notification.CATEGORY_STATUS)
            .apply { if (progress != null) setProgress(100, progress.coerceIn(0, 100), false) }
            .build()
    }

    /** Thẻ buổi chạy; đồng hồ do hệ thống tự chạy ([running]) nên không phải cập nhật mỗi giây. */
    fun run(
        ctx: Context, channelName: String, title: String, subtitle: String,
        timeLabel: String, distanceLabel: String, distance: String, movingMs: Long, running: Boolean,
    ): Notification {
        ensureChannel(ctx, CH_RUN, channelName, NotificationManager.IMPORTANCE_DEFAULT)
        val views = RemoteViews(ctx.packageName, R.layout.notif_run).apply {
            setTextViewText(R.id.run_title, title)
            setTextViewText(R.id.run_subtitle, subtitle)
            setTextViewText(R.id.run_time_label, timeLabel)
            setTextViewText(R.id.run_distance_label, distanceLabel)
            setTextViewText(R.id.run_distance, distance)
            setChronometer(R.id.run_time, SystemClock.elapsedRealtime() - movingMs, null, running)
        }
        return builder(ctx, CH_RUN)
            .setSmallIcon(R.drawable.ic_stat_stride)
            .setStyle(Notification.DecoratedCustomViewStyle())
            .setCustomContentView(views)
            .setContentTitle(title)
            .setContentIntent(openApp(ctx))
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setCategory(Notification.CATEGORY_WORKOUT)
            .build()
    }

    fun notifySteps(ctx: Context, n: Notification) = manager(ctx).notify(ID_STEPS, n)

    fun notifyRun(ctx: Context, n: Notification) = manager(ctx).notify(ID_RUN, n)

    fun cancelRun(ctx: Context) = manager(ctx).cancel(ID_RUN)
}
