package com.mybot.assistant

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {

    private var automation: A11yController? = null
    private var notifications: NotifyController? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        // Kept as fields so neither controller (nor its channel handler) can be
        // garbage collected while the app is alive.
        automation = A11yController(this, messenger)
        notifications = NotifyController(this, messenger)
    }

    override fun onDestroy() {
        automation?.dispose()
        notifications?.dispose()
        automation = null
        notifications = null
        super.onDestroy()
    }
}
