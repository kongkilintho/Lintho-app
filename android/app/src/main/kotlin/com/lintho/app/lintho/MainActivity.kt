package com.lintho.app.lintho

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

// 🔒 [AUDIT N-03 / 2026-08-08 — High, notification E2E audit] Cloud Functions
// (functions/index.js processFCMQueue) sends every push with an
// android.notification.channel_id of 'lintho_jobs' / 'lintho_chat' /
// 'lintho_payment' (see _getChannelId()), but nothing in this app ever
// created those channels — no flutter_local_notifications plugin, no native
// NotificationChannel calls, no manifest default_notification_channel_id.
// On Android 8.0+ (API 26+), a notification referencing a channel that
// doesn't exist on the device can fail to display, especially while the app
// is backgrounded/terminated. Create the channels here so they exist before
// any push can arrive — by the time a device even has an FCM token
// registered (FCMService.instance.init(), fcm_service.dart), the app must
// already have launched at least once, so MainActivity.onCreate() is
// guaranteed to have run and these channels to already exist for every
// subsequent background/terminated delivery.
class MainActivity: FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createNotificationChannels()
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        val channels = listOf(
            Triple("lintho_jobs", "ວຽກ ແລະ ການຈອງ", "ແຈ້ງເຕືອນວຽກໃໝ່ ແລະ ສະຖານະການຈອງ"),
            Triple("lintho_chat", "ແຊັດ", "ຂໍ້ຄວາມແຊັດລະຫວ່າງລູກຄ້າ ແລະ ຊ່າງ"),
            Triple("lintho_payment", "ການເງິນ", "ແຈ້ງເຕືອນລາຍຮັບ ແລະ wallet"),
        )
        for ((id, name, description) in channels) {
            val channel = NotificationChannel(id, name, NotificationManager.IMPORTANCE_HIGH)
            channel.description = description
            manager.createNotificationChannel(channel)
        }
    }
}
