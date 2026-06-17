package com.safechild.safechild

import android.app.ActivityManager
import android.app.AppOpsManager
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Settings
import android.app.usage.UsageStatsManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.util.Base64
import java.io.ByteArrayOutputStream

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.safechild/native_helper"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "checkUsageAccessGranted" -> {
                    result.success(checkUsageAccessGranted())
                }
                "checkAccessibilityEnabled" -> {
                    result.success(isAccessibilityServiceEnabled())
                }
                "checkDeviceAdminActive" -> {
                    result.success(isDeviceAdminActive())
                }
                "getUsageStats" -> {
                    val startMs = call.argument<Long>("startMs") ?: 0L
                    val endMs = call.argument<Long>("endMs") ?: System.currentTimeMillis()
                    result.success(getUsageStats(startMs, endMs))
                }
                "killPackage" -> {
                    val pkg = call.argument<String>("package") ?: ""
                    if (pkg.isNotEmpty()) {
                        val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
                        am.killBackgroundProcesses(pkg)
                    }
                    result.success(null)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun checkUsageAccessGranted(): Boolean {
        val appOps = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            appOps.unsafeCheckOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, android.os.Process.myUid(), packageName)
        } else {
            appOps.checkOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, android.os.Process.myUid(), packageName)
        }
        return mode == AppOpsManager.MODE_ALLOWED
    }

    private fun isAccessibilityServiceEnabled(): Boolean {
        val expectedService = "$packageName/.SafeChildAccessibilityService" // Adjust if needed
        val enabledServices = Settings.Secure.getString(contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES)
        return enabledServices?.contains(packageName) == true
    }

    private fun isDeviceAdminActive(): Boolean {
        val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
        val adminComponent = ComponentName(this, SafeChildDeviceAdminReceiver::class.java)
        return dpm.isAdminActive(adminComponent)
    }

    private fun getUsageStats(startMs: Long, endMs: Long): List<Map<String, Any>> {
        val usageStatsManager = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val stats = usageStatsManager.queryAndAggregateUsageStats(startMs, endMs)
        
        val result = mutableListOf<Map<String, Any>>()
        val packageManager = packageManager

        for ((packageName, usageStat) in stats) {
            if (usageStat.totalTimeInForeground > 0) {
                var appName = packageName
                var iconBase64 = ""
                try {
                    val info = packageManager.getApplicationInfo(packageName, 0)
                    appName = packageManager.getApplicationLabel(info).toString()
                    
                    val drawable = packageManager.getApplicationIcon(info)
                    iconBase64 = encodeDrawableToBase64(drawable)
                } catch (e: Exception) {
                    // Ignore missing info
                }

                result.add(mapOf(
                    "packageName" to packageName,
                    "appName" to appName,
                    "iconBase64" to iconBase64,
                    "usageMs" to usageStat.totalTimeInForeground
                ))
            }
        }
        return result
    }

    private fun encodeDrawableToBase64(drawable: Drawable): String {
        val bitmap = if (drawable is BitmapDrawable) {
            drawable.bitmap
        } else {
            // Compress non-bitmap drawables into small 48x48 thumbnails
            val bmp = Bitmap.createBitmap(48, 48, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bmp)
            drawable.setBounds(0, 0, canvas.width, canvas.height)
            drawable.draw(canvas)
            bmp
        }

        // Scale bitmap to avoid massive firestore documents
        val scaledBitmap = Bitmap.createScaledBitmap(bitmap, 48, 48, true)
        val outputStream = ByteArrayOutputStream()
        scaledBitmap.compress(Bitmap.CompressFormat.PNG, 100, outputStream)
        val byteArray = outputStream.toByteArray()
        return Base64.encodeToString(byteArray, Base64.NO_WRAP)
    }
}
