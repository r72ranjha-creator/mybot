package com.mybot.assistant

import android.Manifest
import android.app.Activity
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Local notifications for the two moments that matter when the app is in the
 * background: a new signal, and an approval that is waiting for a tap.
 *
 * Only primitives here — whether to notify at all is decided in Dart by the
 * Notifications setting.
 */
class NotifyController(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, CHANNEL)

    init {
        channel.setMethodCallHandler(this)
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "ensurePermission" -> result.success(ensurePermission())
                "show" -> result.success(
                    show(
                        title = call.argument<String>("title") ?: "MyBot",
                        body = call.argument<String>("body") ?: "",
                        id = call.argument<Int>("id") ?: 1,
                    )
                )
                else -> result.notImplemented()
            }
        } catch (t: Throwable) {
            result.error("MYBOT_NOTIFY", t.message ?: t.javaClass.simpleName, null)
        }
    }

    private fun granted(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return true
        return ContextCompat.checkSelfPermission(
            activity,
            Manifest.permission.POST_NOTIFICATIONS,
        ) == PackageManager.PERMISSION_GRANTED
    }

    private fun ensurePermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return true
        if (granted()) return true
        ActivityCompat.requestPermissions(
            activity,
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            PERMISSION_REQUEST,
        )
        return false
    }

    private fun show(title: String, body: String, id: Int): Boolean {
        if (!granted()) return false
        val manager = activity.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    "Signals and approvals",
                    NotificationManager.IMPORTANCE_DEFAULT,
                ).apply { description = "MyBot signals and approval requests" }
            )
        }
        val intent = Intent(activity, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pending = PendingIntent.getActivity(
            activity,
            id,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val notification = NotificationCompat.Builder(activity, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setAutoCancel(true)
            .setContentIntent(pending)
            .build()
        manager.notify(id, notification)
        return true
    }

    companion object {
        const val CHANNEL = "mybot/notify"
        private const val CHANNEL_ID = "mybot_signals"
        private const val PERMISSION_REQUEST = 4711
    }
}
