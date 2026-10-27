package com.mybot.assistant

import android.app.Activity
import android.content.ComponentName
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.view.accessibility.AccessibilityNodeInfo
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject

/**
 * Bridge between the Flutter layer and [MyBotAccessibilityService].
 *
 * Every method is a primitive. Policy — what may be tapped, whether the user
 * approved, whether an app is blocked — lives in Dart, so this class can stay
 * a thin, auditable layer over the Android APIs.
 */
class A11yController(
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

    private fun service(): MyBotAccessibilityService? = MyBotAccessibilityService.instance

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "isServiceEnabled" -> result.success(isServiceEnabled())
                "openAccessibilitySettings" -> {
                    activity.startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                    result.success(true)
                }
                "openApp" -> result.success(openApp(call.argument<String>("package")))
                "openUrl" -> result.success(openUrl(call.argument<String>("url")))
                "installedApps" -> result.success(installedApps())
                "currentPackage" -> result.success(MyBotAccessibilityService.lastPackage)
                "dumpTree" -> result.success(dumpTree())
                "tapText" -> result.success(
                    tapText(
                        text = call.argument<String>("text") ?: "",
                        exact = call.argument<Boolean>("exact") ?: false,
                        index = call.argument<Int>("index") ?: 0,
                    )
                )
                "tapViewId" -> result.success(
                    tapViewId(
                        viewId = call.argument<String>("viewId") ?: "",
                        index = call.argument<Int>("index") ?: 0,
                    )
                )
                "tapPoint" -> {
                    val s = service()
                    val x = (call.argument<Number>("x") ?: 0).toFloat()
                    val y = (call.argument<Number>("y") ?: 0).toFloat()
                    result.success(s?.tap(x, y) ?: false)
                }
                "typeText" -> result.success(typeText(call.argument<String>("text") ?: ""))
                "setText" -> result.success(
                    setText(
                        call.argument<String>("hint") ?: "",
                        call.argument<String>("text") ?: "",
                    )
                )
                "scroll" -> result.success(
                    scroll(call.argument<String>("direction") ?: "down")
                )
                "swipe" -> {
                    val s = service()
                    result.success(
                        s?.swipe(
                            (call.argument<Number>("x1") ?: 0).toFloat(),
                            (call.argument<Number>("y1") ?: 0).toFloat(),
                            (call.argument<Number>("x2") ?: 0).toFloat(),
                            (call.argument<Number>("y2") ?: 0).toFloat(),
                            (call.argument<Number>("duration") ?: 300).toLong(),
                        ) ?: false
                    )
                }
                "back" -> result.success(service()?.back() ?: false)
                "home" -> result.success(service()?.home() ?: false)
                "recents" -> result.success(service()?.recents() ?: false)
                "screenshot" -> result.success(service()?.screenshotBase64())
                else -> result.notImplemented()
            }
        } catch (t: Throwable) {
            result.error("MYBOT_A11Y", t.message ?: t.javaClass.simpleName, null)
        }
    }

    // ---------------------------------------------------------------- queries

    private fun isServiceEnabled(): Boolean {
        val expected = ComponentName(activity, MyBotAccessibilityService::class.java)
        val enabled = Settings.Secure.getString(
            activity.contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES,
        ) ?: return false
        return enabled.split(':').any { entry ->
            ComponentName.unflattenFromString(entry) == expected
        }
    }

    private fun openApp(pkg: String?): Boolean {
        if (pkg.isNullOrBlank()) return false
        val intent = activity.packageManager.getLaunchIntentForPackage(pkg) ?: return false
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED)
        activity.startActivity(intent)
        return true
    }

    private fun openUrl(url: String?): Boolean {
        if (url.isNullOrBlank()) return false
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        activity.startActivity(intent)
        return true
    }

    private fun installedApps(): List<Map<String, String>> {
        val pm = activity.packageManager
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        val resolved = pm.queryIntentActivities(intent, 0)
        val seen = HashMap<String, String>()
        for (info in resolved) {
            val pkg = info.activityInfo?.packageName ?: continue
            if (pkg == activity.packageName) continue
            if (seen.containsKey(pkg)) continue
            val label = try {
                pm.getApplicationLabel(pm.getApplicationInfo(pkg, 0)).toString()
            } catch (t: Throwable) {
                pkg
            }
            seen[pkg] = label
        }
        return seen.entries
            .map { mapOf("package" to it.key, "label" to it.value) }
            .sortedBy { it["label"]?.lowercase() }
    }

    private fun dumpTree(): String {
        val root = service()?.root() ?: return "[]"
        val out = JSONArray()
        fun walk(node: AccessibilityNodeInfo?, depth: Int) {
            if (node == null || depth > 40 || out.length() > 900) return
            val rect = android.graphics.Rect()
            node.getBoundsInScreen(rect)
            out.put(
                JSONObject().apply {
                    put("depth", depth)
                    put("text", node.text?.toString() ?: "")
                    put("desc", node.contentDescription?.toString() ?: "")
                    put("viewId", node.viewIdResourceName ?: "")
                    put("cls", node.className?.toString() ?: "")
                    put("clickable", node.isClickable)
                    put("editable", node.isEditable)
                    put("scrollable", node.isScrollable)
                    put("enabled", node.isEnabled)
                    put("x", rect.centerX())
                    put("y", rect.centerY())
                }
            )
            for (i in 0 until node.childCount) {
                walk(node.getChild(i), depth + 1)
            }
        }
        walk(root, 0)
        return out.toString()
    }

    // ------------------------------------------------------------- node match

    private fun collect(root: AccessibilityNodeInfo?, query: String, exact: Boolean): MutableList<AccessibilityNodeInfo> {
        val hits = mutableListOf<AccessibilityNodeInfo>()
        if (root == null || query.isBlank()) return hits

        fun matches(node: AccessibilityNodeInfo): Boolean {
            val text = node.text?.toString()?.trim().orEmpty()
            val desc = node.contentDescription?.toString()?.trim().orEmpty()
            return if (exact) {
                text.equals(query, true) || desc.equals(query, true)
            } else {
                text.contains(query, true) || desc.contains(query, true)
            }
        }

        fun walk(node: AccessibilityNodeInfo?, depth: Int) {
            if (node == null || depth > 40 || hits.size > 60) return
            if (matches(node) && node.isVisibleToUser) hits.add(node)
            for (i in 0 until node.childCount) walk(node.getChild(i), depth + 1)
        }
        walk(root, 0)
        return hits
    }

    private fun tapNode(node: AccessibilityNodeInfo?): Boolean {
        if (node == null) return false
        var current: AccessibilityNodeInfo? = node
        var guard = 0
        while (current != null && guard < 8) {
            if (current.isClickable) {
                return current.performAction(AccessibilityNodeInfo.ACTION_CLICK)
            }
            current = current.parent
            guard++
        }
        // Not clickable anywhere up the chain: fall back to a real tap on the
        // centre of the node's bounds.
        val rect = android.graphics.Rect()
        node.getBoundsInScreen(rect)
        if (rect.width() <= 0 || rect.height() <= 0) return false
        return service()?.tap(rect.exactCenterX(), rect.exactCenterY()) ?: false
    }

    private fun tapText(text: String, exact: Boolean, index: Int): Boolean {
        val hits = collect(service()?.root(), text, exact)
        return tapNode(hits.getOrNull(index.coerceAtLeast(0)))
    }

    private fun tapViewId(viewId: String, index: Int): Boolean {
        val root = service()?.root() ?: return false
        val hits = root.findAccessibilityNodeInfosByViewId(viewId) ?: return false
        return tapNode(hits.getOrNull(index.coerceAtLeast(0)))
    }

    private fun editableNode(hint: String): AccessibilityNodeInfo? {
        val root = service()?.root() ?: return null
        val focused = root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
        if (focused != null && focused.isEditable) return focused
        val wanted = collect(root, hint, exact = false).firstOrNull { it.isEditable }
        if (wanted != null) return wanted
        val all = mutableListOf<AccessibilityNodeInfo>()
        fun walk(node: AccessibilityNodeInfo?, depth: Int) {
            if (node == null || depth > 30 || all.size > 20) return
            if (node.isEditable && node.isVisibleToUser) all.add(node)
            for (i in 0 until node.childCount) walk(node.getChild(i), depth + 1)
        }
        walk(root, 0)
        return all.firstOrNull()
    }

    private fun typeText(text: String): Boolean {
        val node = editableNode("") ?: return false
        // A raw key-by-key injection is unreliable across keyboards; setting
        // the text directly is what an accessibility automation tool should do.
        node.performAction(AccessibilityNodeInfo.ACTION_FOCUS)
        val args = Bundle().apply {
            putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, text)
        }
        return node.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
    }

    private fun setText(hint: String, text: String): Boolean {
        val node = editableNode(hint) ?: return false
        node.performAction(AccessibilityNodeInfo.ACTION_FOCUS)
        val args = Bundle().apply {
            putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, text)
        }
        return node.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
    }

    private fun scroll(direction: String): Boolean {
        val root = service()?.root() ?: return false
        var target: AccessibilityNodeInfo? = root
        var guard = 0
        while (target != null && !target.isScrollable && guard < 20) {
            target = target.parent ?: break
            guard++
        }
        val action = if (direction == "up" || direction == "back") {
            AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD
        } else {
            AccessibilityNodeInfo.ACTION_SCROLL_FORWARD
        }
        if (target != null && target.isScrollable) {
            return target.performAction(action)
        }
        val metrics = activity.resources.displayMetrics
        val cx = metrics.widthPixels / 2f
        val stepped = if (action == AccessibilityNodeInfo.ACTION_SCROLL_FORWARD) {
            service()?.swipe(cx, metrics.heightPixels * 0.72f, cx, metrics.heightPixels * 0.28f, 260) ?: false
        } else {
            service()?.swipe(cx, metrics.heightPixels * 0.28f, cx, metrics.heightPixels * 0.72f, 260) ?: false
        }
        return stepped
    }

    companion object {
        const val CHANNEL = "mybot/automation"
    }
}
