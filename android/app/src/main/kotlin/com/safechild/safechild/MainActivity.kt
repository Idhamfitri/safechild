package com.safechild.safechild

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
                val appName = try {
                    val info = packageManager.getApplicationInfo(packageName, 0)
                    packageManager.getApplicationLabel(info).toString()
                } catch (e: Exception) {
                    packageName
                }

                result.add(mapOf(
                    "packageName" to packageName,
                    "appName" to appName,
                    "usageMs" to usageStat.totalTimeInForeground
                ))
            }
        }
        return result
    }
}
