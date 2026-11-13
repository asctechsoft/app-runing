package com.asc.app_runing

import android.app.ForegroundServiceStartNotAllowedException
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.util.Log

/**
 * Foreground service giữ thông báo số bước hôm nay luôn hiện (loại `health`, cần quyền ACTIVITY_RECOGNITION đã cấp).
 * Chỉ giữ tiến trình sống để Dart tiếp tục đếm; số liệu do Dart đẩy qua [update]. Vuốt app khỏi recents thì dừng,
 * để không bao giờ hiện số bước cũ khi không còn gì cập nhật nó.
 */
class OngoingService : Service() {
    companion object {
        private const val TAG = "OngoingService"
        private const val PREFS = "stride_ongoing"

        @Volatile
        var running = false
            private set

        /** Lưu bản mới nhất để dựng lại thông báo khi service được start. */
        private fun save(ctx: Context, channel: String, title: String, text: String, progress: Int?) {
            ctx.getSharedPreferences(PREFS, MODE_PRIVATE).edit()
                .putString("channel", channel).putString("title", title).putString("text", text)
                .putInt("progress", progress ?: -1).apply()
        }

        fun start(ctx: Context, channel: String, title: String, text: String, progress: Int?) {
            save(ctx, channel, title, text, progress)
            val intent = Intent(ctx, OngoingService::class.java)
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) ctx.startForegroundService(intent) else ctx.startService(intent)
            } catch (e: Exception) {
                // Không được phép chạy foreground lúc này (nền / thiếu quyền): bỏ qua, app vẫn dùng bình thường.
                Log.w(TAG, "Cannot start foreground service", e)
            }
        }

        /** Cập nhật nội dung khi service đang chạy; không tự bật lại thông báo đã bị dừng. */
        fun update(ctx: Context, channel: String, title: String, text: String, progress: Int?) {
            save(ctx, channel, title, text, progress)
            if (!running) return
            OngoingNotifications.notifySteps(ctx, OngoingNotifications.steps(ctx, channel, title, text, progress))
        }

        fun stop(ctx: Context) {
            ctx.stopService(Intent(ctx, OngoingService::class.java))
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val p = getSharedPreferences(PREFS, MODE_PRIVATE)
        val progress = p.getInt("progress", -1).takeIf { it >= 0 }
        val notification = OngoingNotifications.steps(
            this, p.getString("channel", "STRIDE") ?: "STRIDE", p.getString("title", "STRIDE") ?: "STRIDE",
            p.getString("text", "") ?: "", progress,
        )
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) ServiceInfo.FOREGROUND_SERVICE_TYPE_HEALTH else 0
                startForeground(OngoingNotifications.ID_STEPS, notification, type)
            } else {
                startForeground(OngoingNotifications.ID_STEPS, notification)
            }
            running = true
        } catch (e: SecurityException) {
            Log.w(TAG, "Missing permission for health foreground service", e)
            stopSelf()
        } catch (e: Exception) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && e is ForegroundServiceStartNotAllowedException) {
                Log.w(TAG, "Cannot promote to foreground from background", e)
                stopSelf()
            } else {
                throw e
            }
        }
        return START_NOT_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        OngoingNotifications.cancelRun(this)
        stopSelf()
    }

    override fun onDestroy() {
        running = false
        super.onDestroy()
    }
}
