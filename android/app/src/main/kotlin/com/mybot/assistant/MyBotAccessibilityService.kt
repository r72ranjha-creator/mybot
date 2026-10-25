package com.mybot.assistant

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.accessibilityservice.GestureDescription
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Path
import android.os.Build
import android.util.Base64
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import java.io.ByteArrayOutputStream
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * The only component that can touch other apps. Everything it can do is
 * exposed to Flutter through [A11yController]; nothing here decides policy —
 * MyBot's Dart layer decides what is allowed and asks the user first.
 */
class MyBotAccessibilityService : AccessibilityService() {

    companion object {
        @Volatile
        var instance: MyBotAccessibilityService? = null
            private set

        @Volatile
        var lastPackage: String = ""

        /** takeScreenshot needs *an* executor; one reusable thread is enough. */
        private val screenshotExecutor: java.util.concurrent.Executor =
            java.util.concurrent.Executors.newSingleThreadExecutor()
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        serviceInfo = (serviceInfo ?: AccessibilityServiceInfo()).apply {
            eventTypes = AccessibilityEvent.TYPES_ALL_MASK
            feedbackType = AccessibilityServiceInfo.FEEDBACK_GENERIC
            notificationTimeout = 100
            flags = flags or
                AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS or
                AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS or
                AccessibilityServiceInfo.FLAG_INCLUDE_NOT_IMPORTANT_VIEWS
        }
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        val pkg = event?.packageName?.toString()
        if (!pkg.isNullOrBlank()) lastPackage = pkg
    }

    override fun onInterrupt() = Unit

    override fun onUnbind(intent: Intent?): Boolean {
        instance = null
        return super.onUnbind(intent)
    }

    fun root(): AccessibilityNodeInfo? = rootInActiveWindow

    fun back(): Boolean = performGlobalAction(GLOBAL_ACTION_BACK)
    fun home(): Boolean = performGlobalAction(GLOBAL_ACTION_HOME)
    fun recents(): Boolean = performGlobalAction(GLOBAL_ACTION_RECENTS)
    fun notifications(): Boolean = performGlobalAction(GLOBAL_ACTION_NOTIFICATIONS)

    fun tap(x: Float, y: Float): Boolean {
        val path = Path().apply { moveTo(x, y) }
        val gesture = GestureDescription.Builder()
            .addStroke(GestureDescription.StrokeDescription(path, 0, 60))
            .build()
        return dispatchGesture(gesture, null, null)
    }

    fun swipe(x1: Float, y1: Float, x2: Float, y2: Float, durationMs: Long): Boolean {
        val path = Path().apply {
            moveTo(x1, y1)
            lineTo(x2, y2)
        }
        val gesture = GestureDescription.Builder()
            .addStroke(GestureDescription.StrokeDescription(path, 0, durationMs.coerceIn(60L, 3000L)))
            .build()
        return dispatchGesture(gesture, null, null)
    }

    /**
     * Android 14 (API 34) added a display-id parameter to takeScreenshot and
     * the older two-argument form is no longer visible in the compile SDK, so
     * Android 11-13 devices are handled through reflection on that same
     * platform method.
     */
    private fun requestScreenshot(callback: TakeScreenshotCallback) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            takeScreenshot(
                android.view.Display.DEFAULT_DISPLAY,
                screenshotExecutor,
                callback,
            )
            return
        }
        try {
            val method = AccessibilityService::class.java.getMethod(
                "takeScreenshot",
                java.util.concurrent.Executor::class.java,
                AccessibilityService.TakeScreenshotCallback::class.java,
            )
            method.invoke(this, screenshotExecutor, callback)
        } catch (t: Throwable) {
            callback.onFailure(-1)
        }
    }

    /**
     * Screenshot of whatever is on screen, PNG, base64. Requires Android 11
     * (API 30) and the `canTakeScreenshot` flag in the service config.
     */
    fun screenshotBase64(timeoutMs: Long = 8000): String? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return null
        val latch = CountDownLatch(1)
        var png: ByteArray? = null
        val callback: TakeScreenshotCallback = object : TakeScreenshotCallback {
            override fun onSuccess(screenshot: ScreenshotResult) {
                try {
                    val buffer = screenshot.hardwareBuffer
                    val bitmap = Bitmap.wrapHardwareBuffer(buffer, screenshot.colorSpace)
                    val soft = bitmap?.copy(Bitmap.Config.ARGB_8888, false)
                    buffer.close()
                    if (soft != null) {
                        val out = ByteArrayOutputStream()
                        soft.compress(Bitmap.CompressFormat.PNG, 100, out)
                        png = out.toByteArray()
                        soft.recycle()
                    }
                } catch (t: Throwable) {
                    png = null
                } finally {
                    latch.countDown()
                }
            }

            override fun onFailure(errorCode: Int) {
                latch.countDown()
            }
        }
        requestScreenshot(callback)
        if (!latch.await(timeoutMs, TimeUnit.MILLISECONDS)) return null
        val bytes = png ?: return null
        return Base64.encodeToString(bytes, Base64.NO_WRAP)
    }
}
