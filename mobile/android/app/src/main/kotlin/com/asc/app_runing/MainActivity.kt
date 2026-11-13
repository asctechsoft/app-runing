package com.asc.app_runing

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Thông báo đang chạy (số bước + thẻ buổi chạy): chữ do Dart truyền, native chỉ vẽ.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "stride/ongoing").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "startSteps" -> {
                        OngoingService.start(this, call.argument("channel")!!, call.argument("title")!!, call.argument("text")!!, call.argument<Int>("progress"))
                        result.success(null)
                    }
                    "updateSteps" -> {
                        OngoingService.update(this, call.argument("channel")!!, call.argument("title")!!, call.argument("text")!!, call.argument<Int>("progress"))
                        result.success(null)
                    }
                    "stopSteps" -> {
                        OngoingService.stop(this)
                        result.success(null)
                    }
                    "showRun" -> {
                        val n = OngoingNotifications.run(
                            this, call.argument("channel")!!, call.argument("title")!!, call.argument("subtitle")!!,
                            call.argument("timeLabel")!!, call.argument("distanceLabel")!!, call.argument("distance")!!,
                            (call.argument<Number>("movingMs") ?: 0).toLong(), call.argument<Boolean>("running") ?: true,
                        )
                        OngoingNotifications.notifyRun(this, n)
                        result.success(null)
                    }
                    "hideRun" -> {
                        OngoingNotifications.cancelRun(this)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("ongoing_failed", e.message, null)
            }
        }
    }
}
