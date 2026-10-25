package com.mybot.assistant

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {

    private var automation: A11yController? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Kept as a field so the controller (and its method channel handler)
        // cannot be garbage collected while the app is alive.
        automation = A11yController(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun onDestroy() {
        automation?.dispose()
        automation = null
        super.onDestroy()
    }
}
