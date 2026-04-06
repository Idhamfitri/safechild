package com.safechild.safechild

import android.app.admin.DeviceAdminReceiver
import android.content.Context
import android.content.Intent
import android.widget.Toast

class SafeChildDeviceAdminReceiver : DeviceAdminReceiver() {

    override fun onEnabled(context: Context, intent: Intent) {
        Toast.makeText(context, "SafeChild protection enabled.", Toast.LENGTH_SHORT).show()
    }

    override fun onDisableRequested(context: Context, intent: Intent): CharSequence {
        return "Disabling SafeChild protection will remove parental monitoring from this device."
    }

    override fun onDisabled(context: Context, intent: Intent) {
        Toast.makeText(context, "SafeChild protection disabled.", Toast.LENGTH_SHORT).show()
    }
}