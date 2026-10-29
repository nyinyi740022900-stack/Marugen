package com.marugen.marugen_app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterFragmentActivity

class MainActivity : FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createOrderUpdatesChannel()
    }

    // Matches ANDROID_CHANNEL_ID in supabase/functions/_shared/push.ts.
    // High importance is what lets a push ring and show a banner while the
    // app is closed; FCM's fallback channel only posts a quiet icon.
    private fun createOrderUpdatesChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            "order_updates",
            "Order updates",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Payment, shipping and delivery updates for your orders"
            enableVibration(true)
        }
        getSystemService(NotificationManager::class.java)
            .createNotificationChannel(channel)
    }
}
